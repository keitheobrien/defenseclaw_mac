// Root observable state + tiered RefreshEngine (spec §3.2/§3.3).
// Pulse tier feeds the menu bar icon, Overview health, and new-alert detection.

import Foundation
import Observation
import SwiftUI
import UserNotifications

enum MenuBarState {
    case healthy, alerting(count: Int), degraded, offline, scanning, paused
}

enum PanelID: String, CaseIterable, Identifiable {
    case overview, alerts, logs, audit, activity
    case skills, mcps, plugins, tools
    case inventory, aiDiscovery, registries
    case setup

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .alerts: "Alerts"
        case .logs: "Logs"
        case .audit: "Audit"
        case .activity: "Activity"
        case .skills: "Skills"
        case .mcps: "MCPs"
        case .plugins: "Plugins"
        case .tools: "Tools"
        case .inventory: "Inventory"
        case .aiDiscovery: "AI Discovery"
        case .registries: "Registries"
        case .setup: "Setup"
        }
    }

    var systemImage: String {
        switch self {
        case .overview: "gauge.with.dots.needle.50percent"
        case .alerts: "exclamationmark.shield"
        case .logs: "text.alignleft"
        case .audit: "checklist"
        case .activity: "clock.arrow.circlepath"
        case .skills: "wand.and.stars"
        case .mcps: "server.rack"
        case .plugins: "puzzlepiece.extension"
        case .tools: "wrench.and.screwdriver"
        case .inventory: "shippingbox"
        case .aiDiscovery: "sparkle.magnifyingglass"
        case .registries: "books.vertical"
        case .setup: "gearshape.2"
        }
    }
}

enum AlertPanelRequest: Equatable {
    case all
    case blocks
}

struct LogPanelRequest: Equatable {
    var preset: LogPreset
    var actionFilter: String = "all"
    var eventTypeFilter: String = "all"
}

@Observable
@MainActor
final class AppState {
    // Data layer singletons
    let configStore = ConfigStore()
    let gateway = GatewayClient()
    let audit = AuditStore()
    let stream = EventStreamReader()
    let cli = CLIRunner()
    let updater = UpdateChecker()

    // Self-update state (this Mac app)
    var availableUpdate: ReleaseInfo?
    var upgradeState: UpgradeState = .idle
    var updateBannerDismissed = false
    /// Persisted across launches: GitHub's unauthenticated API allows 60
    /// requests/hour per IP, so app relaunches must not re-check each time.
    @ObservationIgnored @AppStorage("lastUpdateCheckTime") private var lastUpdateCheckTime: Double = 0
    @ObservationIgnored @AppStorage("lastMacAppUpdateCheckTime") private var lastMacAppUpdateCheckTime: Double = 0

    // DefenseClaw runtime (CLI + gateway) update state
    var installedRuntimeVersion: String?
    var availableRuntimeUpdate: ReleaseInfo?
    var runtimeUpgradeState: UpgradeState = .idle
    var runtimeBannerDismissed = false
    var runtimeUpgradeLogTail = ""
    @ObservationIgnored @AppStorage("lastRuntimeUpdateCheckTime") private var lastRuntimeUpdateCheckTime: Double = 0
    /// Full `defenseclaw upgrade` output from the last failed run (for Copy).
    var runtimeUpgradeLog = ""
    /// True when the last release lookup failed (offline / GitHub rate limit) —
    /// "Up to date" must not be claimed on a failed check.
    var lastCheckFailed = false
    var appUpdateCheckFailed = false
    var runtimeUpdateCheckFailed = false

    // Pulse state
    var health: HealthSnapshot = HealthSnapshot()
    var scanners: [ScannerStatus] = []
    var gatewayReachable = false
    var lastGatewayError: GatewayError?
    var config = DefenseClawConfig()
    var installDetected = true

    // Alerts state
    var unackedAlerts: [AlertRow] = []
    var dismissedIDs: Set<String> = []
    /// Last `alerts acknowledge` failure, surfaced in the popover/panel.
    var ackError: String?
    var scanInFlight = false

    // UI state
    var selectedPanel: PanelID = .overview
    var monitoringPaused = false
    /// Connector filter shared by Alerts/Audit/Logs/Activity ("" = All),
    /// the multi-connector equivalent of the TUI's connector-filter chip.
    var connectorFilter: String = ""
    var alertPanelRequest: AlertPanelRequest?
    var auditPresetRequest: String?
    var logPanelRequest: LogPanelRequest?

    // Settings (mirrored via @AppStorage in views; defaults here)
    @ObservationIgnored @AppStorage("pulseInterval") var pulseInterval: Double = 5
    @ObservationIgnored @AppStorage("backgroundInterval") var backgroundInterval: Double = 60
    @ObservationIgnored @AppStorage("notifyCritical") var notifyCritical = true
    @ObservationIgnored @AppStorage("notifyHigh") var notifyHigh = true
    @ObservationIgnored @AppStorage("notifyGatewayOffline") var notifyGatewayOffline = true
    @ObservationIgnored @AppStorage("seenAlertHighWater") var seenAlertHighWater: Double = 0

    private var pulseTask: Task<Void, Never>?
    private var wasReachable: Bool?

    var menuBarState: MenuBarState {
        if monitoringPaused { return .paused }
        if scanInFlight { return .scanning }
        if !gatewayReachable { return .offline }
        // Same definition as the Findings tile and Alerts badge (C/H/M/L).
        let count = unackedAlerts.filter { $0.severity > .info }.count
        if count > 0 { return .alerting(count: count) }
        let degraded = health.subsystems.contains { EntityState.classify($0.state) == .warn || EntityState.classify($0.state) == .blocked }
        if degraded || EntityState.classify(health.state) == .warn { return .degraded }
        return .healthy
    }

    // MARK: - Lifecycle

    func start() {
        Task {
            let cfg = await configStore.reload()
            config = cfg
            installDetected = await configStore.installPresent
            await gateway.update(config: cfg)
            startPulse()
            // Respect the persisted 6h check window — relaunches must not
            // burn the unauthenticated GitHub API quota (60/hr per IP).
            await checkForUpdates()
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    func startPulse() {
        pulseTask?.cancel()
        pulseTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, !self.monitoringPaused {
                    await self.pulse()
                }
                let interval = self?.pulseInterval ?? 5
                try? await Task.sleep(for: .seconds(max(2, interval)))
            }
        }
    }

    func pulse() async {
        do {
            var snap = try await gateway.health()
            // Enrich connector rows: mode/rule pack from config, and
            // audit-derived activity (hook connectors deliver calls
            // out-of-band, so /health counters can sit at zero).
            let stats = await audit.connectorStats()
            for i in snap.connectors.indices {
                let name = snap.connectors[i].name
                snap.connectors[i].mode = config.connectorModes[name]
                    ?? config.guardrailMode ?? "observe"
                snap.connectors[i].rulePack = config.connectorRulePacks[name] ?? "default"
                if let s = stats[name] {
                    if snap.connectors[i].calls == 0 { snap.connectors[i].calls = s.hookCalls }
                    if snap.connectors[i].blocks == 0 { snap.connectors[i].blocks = s.blocks }
                    snap.connectors[i].alerts = s.alerts
                    snap.connectors[i].lastActivity = s.lastActivity
                }
            }
            health = snap
            if !gatewayReachable, wasReachable == false, notifyGatewayOffline {
                notify(title: "DefenseClaw gateway recovered",
                       body: "Gateway is reachable again on port \(config.gatewayPort).", id: "gw-recovered-\(Date().timeIntervalSince1970)")
            }
            gatewayReachable = true
            lastGatewayError = nil
        } catch let err as GatewayError {
            if gatewayReachable, notifyGatewayOffline, case .offline = err {
                notify(title: "DefenseClaw gateway offline",
                       body: "Lost contact with the gateway on port \(config.gatewayPort).", id: "gw-offline-\(Date().timeIntervalSince1970)")
            }
            gatewayReachable = false
            lastGatewayError = err
        } catch {
            gatewayReachable = false
        }
        wasReachable = gatewayReachable

        // Scanner statuses don't depend on the gateway (binaries on PATH,
        // config, .env) — refresh them even when offline so the card stays
        // useful. guardrailState falls back to the last-known subsystem.
        let guardrailState = health.subsystems.first { $0.name == "guardrail" }?.state
        scanners = ScannerProbe.statuses(config: config, guardrailState: guardrailState)

        // Tail the JSONL stream and refresh the alert set.
        _ = await stream.poll()
        await refreshAlerts()
        await checkForUpdates() // no-op unless 6h have passed
    }

    func refreshAlerts() async {
        // Parity with the TUI's flat_rows: audit alert queue (severity-bearing
        // rows from list_alerts) + one row per scan block grouped by scan_id
        // from gateway.jsonl + egress rows. Nested findings stay inside their
        // block (the chips never count them).
        let queue = await audit.alertQueueEvents(limit: 500)
        let blocks = await stream.scanBlocks
        let egress = await stream.egress

        var rows: [AlertRow] = queue.map { .audit($0) }
        rows += blocks.map { .scan($0) }
        rows += egress.suffix(100).filter { $0.decision.lowercased() != "allowed" || $0.looksLikeLLM }.map { .egress($0) }
        rows.sort { $0.timestamp > $1.timestamp }

        let fresh = rows.filter { !dismissedIDs.contains($0.id) }

        // Notify on rows newer than the persisted high-water mark.
        let highWater = Date(timeIntervalSince1970: seenAlertHighWater)
        var newest = highWater
        for row in fresh where row.timestamp > highWater {
            newest = max(newest, row.timestamp)
            let wantNotify = (row.severity == .critical && notifyCritical) || (row.severity == .high && notifyHigh)
            if wantNotify {
                notify(
                    title: "\(row.severity.rawValue): \(row.action)",
                    body: "Target: \(row.target)", // target + severity only — never payload contents
                    id: row.id
                )
            }
        }
        if newest > highWater { seenAlertHighWater = newest.timeIntervalSince1970 }
        // Publish only on real change — replacing the array every 5s pulse
        // makes Table re-diff mid-gesture and disturbs trackpad scrolling.
        if fresh.map(\.id) != unackedAlerts.map(\.id) {
            unackedAlerts = fresh
        }
    }

    // MARK: - Actions

    /// Mirrors the TUI exactly: `defenseclaw alerts acknowledge --severity <S>`
    /// downgrades that whole severity class to ACK in the audit DB. Audit rows
    /// then drop out of the queue on refresh by themselves. Scan blocks and
    /// egress rows are NOT suppressed — they come from the immutable
    /// gateway.jsonl and the TUI re-shows them on every reload; hiding them
    /// locally made Findings drift to zero against the TUI. Use Dismiss for a
    /// view-local hide (also TUI parity: cleared on next app launch).
    func acknowledge(_ rows: [AlertRow]) async {
        ackError = nil
        var severities = Set<Severity>()
        for row in rows {
            if case .audit = row {
                severities.insert(row.severity)
            } else {
                // Scan blocks / egress rows have no DB-side ack (they live in
                // gateway.jsonl). An explicit Ack is still a user request to
                // clear them, so hide them view-locally — the TUI's
                // "Dismiss all" does the same local clear. Passive refreshes
                // never suppress them (Findings parity).
                dismissedIDs.insert(row.id)
            }
        }
        for severity in severities {
            let result = await cli.run(arguments: ["alerts", "acknowledge", "--severity", severity.rawValue])
            if !result.succeeded {
                ackError = "alerts acknowledge \(severity.rawValue) failed (exit \(result.exitCode))"
            }
        }
        await refreshAlerts()
    }

    /// `defenseclaw alerts dismiss --severity <S|all>` — same DB semantics as the TUI.
    func dismissViaCLI(severity: Severity?) async {
        _ = await cli.run(arguments: ["alerts", "dismiss", "--severity", severity?.rawValue ?? "all"])
        await refreshAlerts()
    }

    func dismiss(_ rows: [AlertRow]) {
        for row in rows { dismissedIDs.insert(row.id) }
        unackedAlerts.removeAll { row in rows.contains { $0.id == row.id } }
    }

    // MARK: - Panel deep links

    func openAlerts(filter: AlertPanelRequest) {
        alertPanelRequest = filter
        selectedPanel = .alerts
    }

    func consumeAlertPanelRequest() -> AlertPanelRequest? {
        defer { alertPanelRequest = nil }
        return alertPanelRequest
    }

    func openAudit(preset: String) {
        auditPresetRequest = preset
        selectedPanel = .audit
    }

    func consumeAuditPresetRequest() -> String? {
        defer { auditPresetRequest = nil }
        return auditPresetRequest
    }

    func openLogs(_ request: LogPanelRequest) {
        logPanelRequest = request
        selectedPanel = .logs
    }

    func consumeLogPanelRequest() -> LogPanelRequest? {
        defer { logPanelRequest = nil }
        return logPanelRequest
    }

    // MARK: - Self-update

    /// Check GitHub for newer releases of BOTH the Mac app and the
    /// DefenseClaw runtime; re-checked every 6h by the pulse.
    func checkForUpdates(force: Bool = false) async {
        guard force || Date().timeIntervalSince1970 - lastUpdateCheckTime > 6 * 3600 else { return }
        let now = Date().timeIntervalSince1970
        lastUpdateCheckTime = now
        lastMacAppUpdateCheckTime = now
        lastRuntimeUpdateCheckTime = now

        let appRelease = await refreshMacAppUpdate()
        let runtimeRelease = await refreshRuntimeUpdate()
        lastCheckFailed = (appRelease == nil || runtimeRelease == nil)
    }

    /// Check only this macOS app. Used by Settings when the user wants to keep
    /// the DefenseClaw runtime untouched.
    func checkForMacAppUpdate(force: Bool = false) async {
        guard force || Date().timeIntervalSince1970 - lastMacAppUpdateCheckTime > 6 * 3600 else { return }
        lastMacAppUpdateCheckTime = Date().timeIntervalSince1970

        _ = await refreshMacAppUpdate()
        lastCheckFailed = appUpdateCheckFailed || runtimeUpdateCheckFailed
    }

    /// Check only the underlying DefenseClaw runtime.
    func checkForRuntimeUpdate(force: Bool = false) async {
        guard force || Date().timeIntervalSince1970 - lastRuntimeUpdateCheckTime > 6 * 3600 else { return }
        lastRuntimeUpdateCheckTime = Date().timeIntervalSince1970

        _ = await refreshRuntimeUpdate()
        lastCheckFailed = appUpdateCheckFailed || runtimeUpdateCheckFailed
    }

    private func refreshMacAppUpdate() async -> ReleaseInfo? {
        upgradeState = .checking
        defer {
            if upgradeState == .checking { upgradeState = .idle }
        }

        // Mac app. A nil release means the check FAILED (offline, API rate
        // limit) — keep any previously known update rather than clearing it.
        let appRelease = await updater.latestRelease()
        if let release = appRelease {
            appUpdateCheckFailed = false
            if UpdateChecker.isNewer(release.version, than: UpdateChecker.currentVersion) {
                if release != availableUpdate { updateBannerDismissed = false }
                availableUpdate = release
            } else {
                availableUpdate = nil
            }
        } else {
            appUpdateCheckFailed = true
        }
        return appRelease
    }

    private func refreshRuntimeUpdate() async -> ReleaseInfo? {
        runtimeUpgradeState = .checking
        defer {
            if runtimeUpgradeState == .checking { runtimeUpgradeState = .idle }
        }

        // DefenseClaw runtime: installed via `defenseclaw --version`,
        // latest from the upstream repo's releases.
        let versionResult = await cli.run(arguments: ["--version"])
        installedRuntimeVersion = UpdateChecker.parseVersion(versionResult.output)
        let runtimeRelease = await updater.latestRuntimeRelease()
        runtimeUpdateCheckFailed = runtimeRelease == nil
        if let installed = installedRuntimeVersion, let latest = runtimeRelease {
            if UpdateChecker.isNewer(latest.version, than: installed) {
                if latest != availableRuntimeUpdate { runtimeBannerDismissed = false }
                availableRuntimeUpdate = latest
            } else {
                availableRuntimeUpdate = nil
            }
        }
        return runtimeRelease
    }

    /// Runs `defenseclaw upgrade --yes` — downloads release artifacts,
    /// migrates, and restarts the gateway. Non-destructive per upstream docs.
    /// Turn raw `defenseclaw upgrade` output into a human message. The common
    /// case today is an UPSTREAM packaging conflict (the 0.7.2 wheel pins
    /// click==8.3.1 while its own cisco-ai-mcp-scanner→litellm dep pins
    /// click==8.1.8) — unsatisfiable in any environment, so it is not an app
    /// problem and no app-side flag fixes it. Name that explicitly.
    nonisolated static func summarizeUpgradeFailure(_ output: String, exitCode: Int32) -> String {
        if output.contains("No solution found when resolving dependencies") {
            // Pull the conflicting package names if present, for specificity.
            let pkg = output.contains("cisco-ai-mcp-scanner") ? "cisco-ai-mcp-scanner" : "a dependency"
            return "Upstream packaging conflict in this DefenseClaw release: its Python wheel and \(pkg) pin incompatible versions of the same library, so it cannot be installed in any environment. This is a bug in the release itself — not the app — and there is no upgrade flag that fixes it. Wait for a corrected upstream release. (Copy Full Upgrade Log in Settings for details.)"
        }
        if output.localizedCaseInsensitiveContains("could not determine latest release") {
            return "Couldn't reach the release server (offline or GitHub rate-limited). Try again shortly."
        }
        // Fall back to the most meaningful single line.
        let errorLine = output.split(separator: "\n")
            .first { $0.contains("×") || $0.localizedCaseInsensitiveContains("error:") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        return errorLine ?? "defenseclaw upgrade exited \(exitCode). See Copy Full Upgrade Log in Settings."
    }

    func performMacAppUpgradeCheck() {
        Task {
            await checkForMacAppUpdate(force: true)
            performUpgrade()
        }
    }

    func performRuntimeUpgradeCheck() {
        Task {
            await checkForRuntimeUpdate(force: true)
            _ = await runRuntimeUpgradeIfAvailable()
        }
    }

    func performBothUpgrades() {
        Task {
            await checkForUpdates(force: true)
            let shouldRefreshRuntimeAfterUpgrade = availableUpdate == nil
            let runtimeUpgradeSucceeded = await runRuntimeUpgradeIfAvailable(refreshAfterSuccess: shouldRefreshRuntimeAfterUpgrade)
            guard runtimeUpgradeSucceeded else { return }
            performUpgrade()
        }
    }

    func performRuntimeUpgrade() {
        Task {
            _ = await runRuntimeUpgradeIfAvailable()
        }
    }

    private func runRuntimeUpgradeIfAvailable(refreshAfterSuccess: Bool = true) async -> Bool {
        switch runtimeUpgradeState {
        case .downloading, .installing:
            return false
        default:
            break
        }
        guard availableRuntimeUpdate != nil else { return true }
        runtimeUpgradeState = .installing
        runtimeUpgradeLogTail = ""
        let result = await cli.run(arguments: ["upgrade", "--yes"]) { line in
            Task { @MainActor in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { self.runtimeUpgradeLogTail = trimmed }
            }
        }
        if result.succeeded {
            runtimeUpgradeState = .idle
            runtimeUpgradeLogTail = ""
            runtimeUpgradeLog = ""
            availableRuntimeUpdate = nil
            if refreshAfterSuccess {
                await checkForRuntimeUpdate(force: true) // re-read installed version
            }
            reloadConfig()                    // gateway restarted; reconnect
            return true
        } else {
            runtimeUpgradeLog = result.output // full log, for Copy in Settings
            runtimeUpgradeState = .failed(Self.summarizeUpgradeFailure(result.output, exitCode: result.exitCode))
            return false
        }
    }

    /// Download, install over the current bundle, and restart the app.
    func performUpgrade() {
        guard let release = availableUpdate, upgradeState == .idle || upgradeState == .checking else { return }
        upgradeState = .downloading
        Task {
            let failure = await updater.downloadAndInstall(release) { state in
                Task { @MainActor in self.upgradeState = state }
            }
            if let failure {
                upgradeState = .failed(failure)
            }
            // On success the app terminates and relaunches — nothing to do here.
        }
    }

    // MARK: - Services card (Overview hero, parity with the TUI SERVICES panel)

    /// The nine SERVICES rows mirrored from the TUI's `service_cards()`, in the
    /// same order: each carries a runtime state (from /health) and a one-line
    /// detail sourced from the matching subsystem's details and/or config.
    var services: [ServiceStatus] {
        let running = Set(["running", "active", "enabled"])

        // Agent: roll the per-connector states into one aggregate, the way an
        // operator reads the CONNECTORS table — running only when all are up,
        // degraded when some are, disabled when every one is down/absent.
        let connStates = health.connectors.map { $0.state.lowercased() }
        let up = connStates.filter { running.contains($0) }.count
        let total = connStates.count
        let agentState: String = {
            guard total > 0 else { return health.connectors.isEmpty && config.connectors.isEmpty ? "unknown" : "disabled" }
            if up == total { return "running" }
            if up > 0 { return "degraded" }
            return connStates.first ?? "unknown"
        }()
        let agentDetail: String = {
            guard total > 0 else {
                let n = config.connectors.count
                return n > 0 ? "\(n) connector\(n == 1 ? "" : "s") configured" : ""
            }
            if up == total { return "\(total) connector\(total == 1 ? "" : "s") active" }
            return "\(up)/\(total) connectors running"
        }()

        func sub(_ key: String) -> HealthSnapshot.Subsystem? { health.subsystem(key) }
        func state(_ key: String, default def: String = "disabled") -> String {
            sub(key)?.state ?? def
        }

        // Gateway: standalone-mode summary when disabled, else uptime.
        let gatewayDetail: String = {
            let g = sub("gateway")
            if (g?.state.lowercased() ?? "") == "disabled", let summary = g?.details["summary"], !summary.isEmpty {
                return summary
            }
            let secs = health.uptimeMs / 1000
            guard secs > 0 else { return "" }
            let h = secs / 3600, m = (secs % 3600) / 60
            return h > 0 ? "up \(h)h \(m)m" : "up \(m)m"
        }()

        // Watchdog: "N skill dirs, M plugin dirs".
        let watchdogDetail: String = {
            guard let d = sub("watcher")?.details else { return "" }
            var parts: [String] = []
            if let s = d["skill_dirs"] { parts.append("\(s) skill dirs") }
            if let p = d["plugin_dirs"] { parts.append("\(p) plugin dirs") }
            return parts.joined(separator: ", ")
        }()

        // Guardrail: from config (mode, port, rule pack) — only when enabled.
        let guardrailDetail: String = {
            guard config.guardrailEnabled else { return "" }
            var parts: [String] = []
            if let m = config.guardrailMode, !m.isEmpty { parts.append(m) }
            if let p = config.guardrailPort { parts.append("port \(p)") }
            if !config.guardrailRulePack.isEmpty { parts.append(config.guardrailRulePack) }
            return parts.joined(separator: ", ")
        }()

        // AI Discovery: "N active, M new, mode".
        let aiDetail: String = {
            guard let d = sub("ai_discovery")?.details else { return "" }
            var parts: [String] = []
            if let a = d["active_signals"] { parts.append("\(a) active") }
            if let n = d["new_signals"] { parts.append("\(n) new") }
            if let mode = d["mode"], !mode.isEmpty { parts.append(mode) }
            return parts.joined(separator: ", ")
        }()

        return [
            ServiceStatus(key: "gateway", name: "Gateway", state: state("gateway"), detail: gatewayDetail),
            ServiceStatus(key: "agent", name: "Agent", state: agentState, detail: agentDetail),
            ServiceStatus(key: "watchdog", name: "Watchdog", state: state("watcher"), detail: watchdogDetail),
            ServiceStatus(key: "guardrail", name: "Guardrail", state: state("guardrail"), detail: guardrailDetail),
            ServiceStatus(key: "api", name: "API", state: state("api"), detail: sub("api")?.details["addr"] ?? ""),
            ServiceStatus(key: "sinks", name: "Sinks", state: state("sinks"), detail: ""),
            ServiceStatus(key: "telemetry", name: "Telemetry", state: state("telemetry"), detail: ""),
            ServiceStatus(key: "ai_discovery", name: "AI Discovery", state: state("ai_discovery"), detail: aiDetail),
            ServiceStatus(key: "sandbox", name: "Sandbox", state: state("sandbox"), detail: ""),
        ]
    }

    // MARK: - Configuration box (Overview, parity with the TUI CONFIGURATION panel)

    /// The global CONFIGURATION rows shown above the Connectors table, mirroring
    /// the TUI's "All connectors" configuration view (Agents / Redaction /
    /// Policy posture / Enforcement / Human approval / Environment / dirs / LLM
    /// / AI Defense).
    var configurationRows: [ConfigurationRow] {
        // Roster size: live connector rows first, then the config roster.
        let agentCount = health.connectors.isEmpty ? config.connectors.count : health.connectors.count
        let multiConnector = config.connectorModes.count > 1 || config.connectors.count > 1

        // First row: "Agents: N active" when multi-connector, else the single
        // connector's name (TUI's active_connector_name()).
        let agentRow: ConfigurationRow = {
            if multiConnector || agentCount > 1 {
                return .init(label: "Agents", value: "\(agentCount) active")
            }
            let name = (config.connectorName ?? config.connectorMode ?? "").lowercased()
            return .init(label: "Agent", value: name)
        }()

        let redaction = config.redactionEnabled ? "ON (redacted)" : "OFF (RAW)"
        let approval = config.hiltEnabled ? "ON (min \(config.hiltMinSeverity))" : "OFF"

        var rows: [ConfigurationRow] = [
            agentRow,
            .init(label: "Redaction", value: redaction),
            .init(label: "Policy posture", value: policyPosture),
            .init(label: "Enforcement", value: enforcementLabel),
            .init(label: "Human approval", value: approval),
            .init(label: "Environment", value: (config.environment?.isEmpty == false ? config.environment! : "unknown")),
            .init(label: "Policy dir", value: config.policyDir?.nonEmpty ?? "—"),
            .init(label: "Data dir", value: config.dataDir?.nonEmpty ?? "—"),
        ]
        if let provider = config.llmProvider?.nonEmpty {
            rows.append(.init(label: "LLM provider", value: provider))
        }
        if let model = config.llmModel?.nonEmpty {
            rows.append(.init(label: "LLM model", value: model))
        }
        if let endpoint = config.aiDefenseEndpoint?.nonEmpty {
            rows.append(.init(label: "AI Defense", value: endpoint))
        }
        return rows
    }

    /// Mirrors the TUI's `_policy_posture`.
    private var policyPosture: String {
        let mode = config.guardrailMode?.nonEmpty ?? "observe"
        let scanner = config.guardrailRulePack.nonEmpty ?? "default"
        let packs = Set(config.connectorRulePacks.values.filter { !$0.isEmpty })
        if config.connectorModes.count > 1 {
            let modes = Set(config.connectorModes.values.filter { !$0.isEmpty })
            if packs.count > 1 || modes.count > 1 { return "per-connector (see roster)" }
            let onlyPack = packs.first ?? scanner
            let onlyMode = modes.first ?? mode
            return "all connectors: \(onlyMode) (\(onlyPack))"
        }
        if mode == "action" { return "action: block CRIT, alert MED+ (\(scanner))" }
        return "balanced: block CRIT, alert MED+ (\(scanner))"
    }

    /// Mirrors the TUI's `_enforcement_label`.
    private var enforcementLabel: String {
        if config.connectorModes.count > 1 {
            return "\(config.connectorModes.count) connectors (hook observability)"
        }
        let connector = (config.connectorName ?? config.connectorMode ?? "").lowercased()
        let mode = config.guardrailMode?.nonEmpty ?? "observe"
        if connector.isEmpty { return "not configured (\(mode))" }
        if connector == "openclaw" || connector == "zeptoclaw" {
            return "\(connector) proxy guardrail (\(mode))"
        }
        return "\(connector) hook observability (\(mode))"
    }

    // MARK: - Connector filter (multi-connector parity, connector_filter.py)

    /// Active connector names in roster order — live health first, then config.
    /// ≤1 means single-connector: no filter chrome (the TUI hides the chip).
    var activeConnectorNames: [String] {
        let fromHealth = health.connectors.map(\.name).filter { !$0.isEmpty }
        if !fromHealth.isEmpty { return fromHealth }
        return config.connectors
    }

    /// Step the filter All → conn0 → conn1 → … → All (collapses to All when ≤1).
    func cycleConnectorFilter() {
        let names = activeConnectorNames
        guard names.count > 1 else { connectorFilter = ""; return }
        let order = [""] + names
        let idx = order.firstIndex(of: connectorFilter) ?? 0
        connectorFilter = order[(idx + 1) % order.count]
    }

    /// True when a row attributed to `connector` is visible under the filter.
    /// All shows everything; an explicit filter requires an exact match and
    /// hides unattributed rows (connector_filter.filter_allows).
    func connectorFilterAllows(_ connector: String) -> Bool {
        let current = connectorFilter.trimmingCharacters(in: .whitespaces).lowercased()
        if current.isEmpty { return true }
        return current == connector.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Connector roster for filesystem catalog scans: live health first,
    /// then config's guardrail.connectors, then every known connector so
    /// the panels work regardless of agent type.
    func configuredConnectors() -> [String] {
        let fromHealth = health.connectors.map(\.name)
        if !fromHealth.isEmpty { return fromHealth }
        if !config.connectors.isEmpty { return config.connectors }
        return ["openclaw", "zeptoclaw", "codex", "claudecode", "hermes",
                "cursor", "windsurf", "geminicli", "copilot", "openhands", "antigravity"]
    }

    func reloadConfig() {
        Task {
            let cfg = await configStore.reload()
            config = cfg
            await gateway.update(config: cfg)
            await pulse()
        }
    }

    private func notify(title: String, body: String, id: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
