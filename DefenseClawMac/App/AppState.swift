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

    // Pulse state
    var health: HealthSnapshot = HealthSnapshot()
    var gatewayReachable = false
    var lastGatewayError: GatewayError?
    var config = DefenseClawConfig()
    var installDetected = true

    // Alerts state
    var unackedAlerts: [AlertRow] = []
    var acknowledgedIDs: Set<String> = []
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

        let fresh = rows.filter { !acknowledgedIDs.contains($0.id) && !dismissedIDs.contains($0.id) }

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
    /// downgrades that whole severity class to ACK in the audit DB.
    func acknowledge(_ rows: [AlertRow]) async {
        var severities = Set<Severity>()
        for row in rows {
            if case .audit = row { severities.insert(row.severity) }
            acknowledgedIDs.insert(row.id) // hides findings/egress rows locally
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
