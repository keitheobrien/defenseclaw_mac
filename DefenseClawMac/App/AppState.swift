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

    // DefenseClaw runtime (CLI + gateway) update state
    var installedRuntimeVersion: String?
    var availableRuntimeUpdate: ReleaseInfo?
    var runtimeUpgradeState: UpgradeState = .idle
    var runtimeBannerDismissed = false
    var runtimeUpgradeLogTail = ""
    /// Full `defenseclaw upgrade` output from the last failed run (for Copy).
    var runtimeUpgradeLog = ""
    /// True when the last release lookup failed (offline / GitHub rate limit) —
    /// "Up to date" must not be claimed on a failed check.
    var lastCheckFailed = false

    // Pulse state
    var health: HealthSnapshot = HealthSnapshot()
    var gatewayReachable = false
    var lastGatewayError: GatewayError?
    var config = DefenseClawConfig()
    var installDetected = true

    // Alerts state
    var unackedAlerts: [AlertRow] = []
    var dismissedIDs: Set<String> = []
    var scanInFlight = false

    // UI state
    var selectedPanel: PanelID = .overview
    var monitoringPaused = false

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
        let count = unackedAlerts.filter { $0.severity >= .high }.count
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
            let snap = try await gateway.health()
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
        var severities = Set<Severity>()
        for row in rows {
            if case .audit = row { severities.insert(row.severity) }
        }
        for severity in severities {
            _ = await cli.run(arguments: ["alerts", "acknowledge", "--severity", severity.rawValue])
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

    // MARK: - Self-update

    /// Check GitHub for newer releases of BOTH the Mac app and the
    /// DefenseClaw runtime; re-checked every 6h by the pulse.
    func checkForUpdates(force: Bool = false) async {
        guard force || Date().timeIntervalSince1970 - lastUpdateCheckTime > 6 * 3600 else { return }
        lastUpdateCheckTime = Date().timeIntervalSince1970
        upgradeState = .checking

        // Mac app. A nil release means the check FAILED (offline, API rate
        // limit) — keep any previously known update rather than clearing it.
        let appRelease = await updater.latestRelease()
        if let release = appRelease {
            if UpdateChecker.isNewer(release.version, than: UpdateChecker.currentVersion) {
                if release != availableUpdate { updateBannerDismissed = false }
                availableUpdate = release
            } else {
                availableUpdate = nil
            }
        }
        upgradeState = .idle

        // DefenseClaw runtime: installed via `defenseclaw --version`,
        // latest from the upstream repo's releases.
        let versionResult = await cli.run(arguments: ["--version"])
        installedRuntimeVersion = UpdateChecker.parseVersion(versionResult.output)
        let runtimeRelease = await updater.latestRuntimeRelease()
        if let installed = installedRuntimeVersion, let latest = runtimeRelease {
            if UpdateChecker.isNewer(latest.version, than: installed) {
                if latest != availableRuntimeUpdate { runtimeBannerDismissed = false }
                availableRuntimeUpdate = latest
            } else {
                availableRuntimeUpdate = nil
            }
        }
        lastCheckFailed = (appRelease == nil || runtimeRelease == nil)
    }

    /// Runs `defenseclaw upgrade --yes` — downloads release artifacts,
    /// migrates, and restarts the gateway. Non-destructive per upstream docs.
    func performRuntimeUpgrade() {
        guard runtimeUpgradeState == .idle || runtimeUpgradeState == .checking,
              availableRuntimeUpdate != nil else { return }
        runtimeUpgradeState = .installing
        runtimeUpgradeLogTail = ""
        Task {
            let result = await cli.run(arguments: ["upgrade", "--yes"]) { line in
                Task { @MainActor in
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { self.runtimeUpgradeLogTail = trimmed }
                }
            }
            if result.succeeded {
                runtimeUpgradeState = .idle
                runtimeUpgradeLogTail = ""
                availableRuntimeUpdate = nil
                await checkForUpdates(force: true) // re-read installed version
                reloadConfig()                     // gateway restarted; reconnect
            } else {
                runtimeUpgradeLog = result.output // full log, for Copy in Settings
                // Surface the most meaningful line: prefer the resolver/installer
                // error over the Python traceback tail.
                let errorLine = result.output.split(separator: "\n")
                    .first { $0.contains("×") || $0.localizedCaseInsensitiveContains("error:") }
                    .map(String.init)
                runtimeUpgradeState = .failed(
                    errorLine ?? "defenseclaw upgrade exited \(result.exitCode): \(String(result.output.suffix(200)))"
                )
            }
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
