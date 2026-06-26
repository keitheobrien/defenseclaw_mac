// Overview dashboard (spec §9.1): health, connectors, 24h enforcement,
// hourly histogram, doctor, AI discovery, credentials.

import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @State private var summary: (blockedSkills: Int, allowedSkills: Int, blockedMCPs: Int, allowedMCPs: Int, totalScans: Int, activeAlerts: Int) = (0, 0, 0, 0, 0, 0)
    @State private var hourly: [HourlyPoint] = []
    @State private var doctorChecks: [DoctorCheck] = []
    @State private var doctorRunning = false
    @State private var doctorOutput = ""
    @State private var showDoctorSheet = false
    @State private var aiSnapshot = AIUsageSnapshot()

    struct HourlyPoint: Identifiable {
        let hour: Date
        let klass: String
        let count: Int
        var id: String { "\(hour.timeIntervalSince1970)-\(klass)" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Hero row: System Health · Scanners · Enforcement —
                // the three at-a-glance status blocks, all equal height.
                // fixedSize pins the row to its tallest card; fillHeight on
                // each card stretches the shorter ones to match.
                HStack(alignment: .top, spacing: 14) {
                    servicesCard
                        .frame(maxWidth: .infinity)
                    scannersCard
                        .frame(maxWidth: .infinity)
                    enforcementTilesCard
                        .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
                configurationCard
                if !appState.health.connectors.isEmpty { connectorCard }
                activityCard
                HStack(alignment: .top, spacing: 14) {
                    doctorCard
                    aiCard
                }
            }
            .padding(16)
        }
        .toolbar {
            ToolbarItemGroup {
                StaleBadge(date: appState.health.fetchedAt)
                Button {
                    runDoctor()
                } label: {
                    Label("Run Health Check", systemImage: "stethoscope")
                }
                .disabled(doctorRunning)
                Button {
                    refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { refresh() }
        .task(id: appState.health.fetchedAt) { await loadData() } // pulse-fed
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in refresh() }
        .sheet(isPresented: $showDoctorSheet) {
            VStack(alignment: .leading, spacing: 10) {
                Text("defenseclaw doctor").font(.headline)
                ScrollView {
                    Text(doctorOutput.isEmpty ? "Running…" : doctorOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(minHeight: 300)
                Button("Close") { showDoctorSheet = false }
            }
            .padding(16)
            .frame(width: 620, height: 420)
        }
    }

    // MARK: Cards

    /// Hero left: the TUI's SERVICES box — the nine subsystems (Gateway, Agent,
    /// Watchdog, Guardrail, API, Sinks, Telemetry, AI Discovery, Sandbox), each
    /// with a state-colored bullet, name, running/disabled state word, and
    /// detail. Falls back to a gateway-unreachable hint when the API is down.
    private var servicesCard: some View {
        DCCard("Services", systemImage: "square.stack.3d.up", fillHeight: true) {
            if appState.gatewayReachable {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(appState.services) { svc in
                        HStack(spacing: 8) {
                            serviceBullet(svc.state)
                            Text(svc.name)
                                .font(.caption.weight(.medium))
                                .frame(width: 92, alignment: .leading)
                            Text(svc.state)
                                .font(.caption.monospaced())
                                .foregroundStyle(Cisco.stateColor(raw: svc.state))
                                .frame(width: 66, alignment: .leading)
                            Text(svc.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Gateway unreachable on port \(appState.config.gatewayPort)", systemImage: "bolt.slash")
                        .foregroundStyle(Cisco.red)
                    Text("File-based panels (Audit, Logs, Activity, alert history) keep working. Start the gateway with:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text("defenseclaw gateway start")
                            .font(.system(.caption, design: .monospaced))
                        Button {
                            copyToPasteboard("defenseclaw gateway start")
                        } label: { Image(systemName: "doc.on.doc") }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }

    /// Filled dot for a running-ish service, hollow ring otherwise — the TUI's
    /// ●/○ convention, colored by state.
    @ViewBuilder
    private func serviceBullet(_ state: String) -> some View {
        let running = ["running", "active", "enabled", "clean", "allowed"].contains(state.lowercased())
        let color = Cisco.stateColor(raw: state)
        if running {
            Circle().fill(color).frame(width: 7, height: 7)
        } else {
            Circle().strokeBorder(color, lineWidth: 1).frame(width: 7, height: 7)
        }
    }


    /// Full-width CONFIGURATION box (parity with the TUI's global configuration
    /// panel). Uses the same DCCard chrome as the Connectors box — navy panel
    /// background and blue header — with the same zebra-striped table rows. The
    /// stripes use the system's *neutral* alternating content background colors
    /// (the exact colors SwiftUI's Table paints in the Connectors box), so the
    /// rows read black/grey over the blue card rather than blue-on-blue.
    private var configurationCard: some View {
        DCCard("Configuration", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(appState.configurationRows.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .top, spacing: 12) {
                        Text(row.label)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .frame(width: 150, alignment: .leading)
                        Text(row.value)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Self.zebra(index))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    /// The two neutral, opaque alternating-row colors for the config table —
    /// true black/grey (no blue tint) covering the navy card, matching the
    /// black/grey zebra striping of the Connectors table.
    private static func zebra(_ index: Int) -> Color {
        index.isMultiple(of: 2)
            ? Color.adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)   // base row (near-black)
            : Color.adaptive(light: 0xEFEFEF, dark: 0x2A2A2C)   // alternate row (grey)
    }

    private var connectorCard: some View {
        DCCard("Connectors", systemImage: "cable.connector") {
            Table(appState.health.connectors) {
                TableColumn("Connector") { c in
                    HStack {
                        Circle().fill(Cisco.stateColor(raw: c.state)).frame(width: 7, height: 7)
                        Text(c.name)
                    }
                }
                TableColumn("Mode", value: \.mode)
                TableColumn("Rule Pack", value: \.rulePack)
                TableColumn("Last Activity") { c in Text(DCDates.relative(c.lastActivity)) }
                TableColumn("Calls") { c in Text("\(c.calls)") }
                TableColumn("Blocks") { c in Text("\(c.blocks)") }
                TableColumn("Alerts") { c in Text("\(c.alerts)") }
            }
            .frame(height: CGFloat(appState.health.connectors.count) * 28 + 32)
            .scrollDisabled(true)
        }
    }

    /// Hero right half: the TUI's four tiles as a 2×2 grid.
    private var enforcementTilesCard: some View {
        DCCard("Enforcement", systemImage: "checkmark.shield", fillHeight: true) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                Button {
                    appState.openLogs(.init(stream: .otel, preset: .hooks))
                } label: {
                    StatCard(
                        title: "Hook Calls (\(max(appState.health.connectors.count, 1)) connectors)",
                        value: "\(heroHookCalls)", tint: Cisco.blue
                    )
                }
                .buttonStyle(.plain)
                .help("Open hook logs")

                Button {
                    appState.openAudit(preset: "blocks")
                } label: {
                    StatCard(title: "Blocks", value: "\(heroBlocks)",
                             tint: heroBlocks > 0 ? Cisco.red : .secondary)
                }
                .buttonStyle(.plain)
                .help("Open blocked audit events")

                Button {
                    appState.openAlerts(filter: .all)
                } label: {
                    StatCard(title: "Findings", value: "\(findingsCount)", tint: Cisco.orange)
                }
                .buttonStyle(.plain)
                .help("Open all alerts")

                Button {
                    appState.openLogs(.init(preset: .guardrail))
                } label: {
                    StatCard(
                        title: guardrailTileTitle,
                        value: appState.config.guardrailEnabled ? "ON" : "OFF",
                        tint: appState.config.guardrailEnabled ? Cisco.green : .secondary
                    )
                }
                .buttonStyle(.plain)
                .help("Open guardrail logs")
            }
        }
    }

    private var guardrailTileTitle: String {
        if let mode = appState.config.guardrailMode, !mode.isEmpty {
            return "Guardrail - \(mode)"
        }
        return "Guardrail"
    }

    /// Hero card: scanner/guardrail/keys status, mirroring the TUI's SCANNERS box.
    private var scannersCard: some View {
        DCCard("Scanners", systemImage: "magnifyingglass.circle", fillHeight: true) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(appState.scanners) { s in
                    HStack(spacing: 6) {
                        Circle().fill(scannerColor(s.level)).frame(width: 7, height: 7)
                        Text(s.name)
                            .font(.caption.weight(.medium))
                        Spacer(minLength: 8)
                        Text(s.detail)
                            .font(.caption)
                            .foregroundStyle(scannerColor(s.level))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                if appState.scanners.isEmpty {
                    Text("Probing scanners…").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func scannerColor(_ level: ScannerStatus.Level) -> Color {
        switch level {
        case .active: Cisco.green
        case .builtin: .secondary
        case .warn: Cisco.orange
        case .missing: Cisco.red
        }
    }

    /// Full-width: enforcement summary counters + 24h histogram.
    private var activityCard: some View {
        DCCard("Activity — last 24h", systemImage: "chart.bar.xaxis") {
            HStack(spacing: 18) {
                summaryItem("Skills", "\(summary.blockedSkills) blocked · \(summary.allowedSkills) allowed")
                summaryItem("MCPs", "\(summary.blockedMCPs) blocked · \(summary.allowedMCPs) allowed")
                summaryItem("Total scans", "\(summary.totalScans)")
                summaryItem("Active alerts", "\(summary.activeAlerts)")
                Spacer()
            }
            if !hourly.isEmpty {
                Chart(hourly) { point in
                    BarMark(
                        x: .value("Hour", point.hour, unit: .hour),
                        y: .value("Events", point.count)
                    )
                    .foregroundStyle(by: .value("Class", point.klass))
                }
                .chartForegroundStyleScale(["allowed": Cisco.green, "blocked": Cisco.red])
                .frame(height: 110)
            }
        }
    }

    private var doctorCard: some View {
        DCCard("Doctor", systemImage: "stethoscope") {
            if doctorChecks.isEmpty {
                Text(doctorRunning ? "Running health probe…" : "No health check run yet. Use “Run Health Check” in the toolbar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(doctorChecks) { check in
                    HStack(spacing: 6) {
                        Image(systemName: icon(for: check.result))
                            .foregroundStyle(color(for: check.result))
                        Text(check.name).font(.caption)
                        Spacer()
                    }
                }
                Button("Deep-dive output…") { showDoctorSheet = true }
                    .controlSize(.small)
            }
        }
    }

    private var aiCard: some View {
        DCCard("AI Discovery", systemImage: "sparkle.magnifyingglass") {
            if aiSnapshot.signals.isEmpty {
                Text("No AI components detected (or discovery disabled).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Grouped one-row-per-product, same as the AI Discovery panel/TUI.
                ForEach(aiSnapshot.rows.prefix(8)) { row in
                    HStack {
                        Text(row.vendor.isEmpty ? row.product : "\(row.vendor)/\(row.product)")
                            .font(.caption)
                            .lineLimit(1)
                        Text("×\(row.count)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        ConfidenceGauge(value: row.maxConfidence)
                    }
                }
                Button("See all →") { appState.selectedPanel = .aiDiscovery }
                    .controlSize(.small)
            }
        }
    }

    // MARK: Actions

    /// Same TUI-parity Findings count used by the menu bar.
    private var findingsCount: Int {
        appState.overviewEnforcementMetrics.findings
    }

    private var heroHookCalls: Int {
        appState.overviewEnforcementMetrics.hookCalls
    }

    private var heroBlocks: Int {
        appState.overviewEnforcementMetrics.blocks
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium))
        }
    }

    private func refresh() {
        Task {
            let before = appState.health.fetchedAt
            await appState.pulse()
            // Online: pulse advances fetchedAt → task(id:) re-runs loadData on its own.
            // Offline: fetchedAt is unchanged, so reload tiles explicitly from the audit DB.
            if appState.health.fetchedAt == before {
                await loadData()
            }
        }
    }

    /// Summary/chart reload WITHOUT triggering a pulse — also driven by the
    /// pulse tick (task(id: fetchedAt)) so the panels track live data without a
    /// pulse→fetchedAt→pulse loop. Hero enforcement counts come from
    /// AppState.overviewEnforcementMetrics so they reconcile with the menu bar.
    private func loadData() async {
        summary = await appState.audit.enforcementSummary()
        hourly = await appState.audit.hourlyEnforcement24h()
            .map { HourlyPoint(hour: $0.hour, klass: $0.action, count: $0.count) }
        if appState.gatewayReachable {
            aiSnapshot = (try? await appState.gateway.aiUsage()) ?? AIUsageSnapshot()
        }
    }

    private func runDoctor() {
        doctorRunning = true
        doctorOutput = ""
        Task {
            let result = await appState.cli.run(arguments: ["doctor"]) { line in
                Task { @MainActor in doctorOutput += line + "\n" }
            }
            doctorChecks = await appState.cli.doctor()
            if doctorChecks.isEmpty {
                doctorChecks = [DoctorCheck(name: "doctor exited \(result.exitCode)",
                                            result: result.succeeded ? .pass : .fail,
                                            detail: result.output)]
            }
            doctorRunning = false
        }
    }

    private func icon(for r: DoctorCheck.Result) -> String {
        switch r {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .fail: "xmark.circle.fill"
        }
    }
    private func color(for r: DoctorCheck.Result) -> Color {
        switch r {
        case .pass: Cisco.green
        case .warn: Cisco.orange
        case .fail: Cisco.red
        }
    }
}
