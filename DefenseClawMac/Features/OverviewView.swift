// Overview dashboard (spec §9.1): health, connectors, 24h enforcement,
// hourly histogram, doctor, AI discovery, credentials.

import SwiftUI
import Charts

struct OverviewView: View {
    @Environment(AppState.self) private var appState
    @State private var tiles: (hookCalls: Int, blocks: Int, findings: Int) = (0, 0, 0)
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
                // Hero row: compact health card beside the enforcement tile grid —
                // no full-width card with dead space in the middle.
                HStack(alignment: .top, spacing: 14) {
                    healthCard
                        .frame(maxWidth: .infinity)
                    enforcementTilesCard
                        .frame(maxWidth: .infinity)
                }
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

    private var healthCard: some View {
        DCCard("System Health", systemImage: "heart.text.square") {
            if appState.gatewayReachable {
                // Headline: state + uptime side by side, no dead space.
                HStack(spacing: 10) {
                    StatePill(raw: appState.health.state)
                    Text(uptimeText)
                        .font(.title3.weight(.semibold))
                    Text("uptime")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let version = appState.health.version {
                        Text("v\(version)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let lastError = appState.health.lastError, !lastError.isEmpty {
                    Label(lastError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Cisco.orange)
                        .lineLimit(2)
                }
                Divider()
                // Subsystems as a two-column chip grid that fills the card.
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          alignment: .leading, spacing: 6) {
                    ForEach(appState.health.subsystems) { sub in
                        HStack {
                            Text(sub.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            StatePill(raw: sub.state)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Cisco.surfaceRaised, in: RoundedRectangle(cornerRadius: 7))
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

    private var uptimeText: String {
        let secs = appState.health.uptimeMs / 1000
        let h = secs / 3600, m = (secs % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
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
        DCCard("Enforcement", systemImage: "checkmark.shield") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                StatCard(
                    title: "Hook Calls (\(max(appState.health.connectors.count, 1)) connectors)",
                    value: "\(tiles.hookCalls)", tint: Cisco.blue
                )
                StatCard(title: "Blocks", value: "\(tiles.blocks)",
                         tint: tiles.blocks > 0 ? Cisco.red : .secondary)
                StatCard(title: "Findings", value: "\(findingsCount)", tint: Cisco.orange)
                StatCard(
                    title: "Guardrail",
                    value: appState.config.guardrailEnabled ? "ON" : "OFF",
                    tint: appState.config.guardrailEnabled ? Cisco.green : .secondary
                ) {
                    if let mode = appState.config.guardrailMode {
                        Text(mode).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
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

    /// The TUI's Findings tile counts ALL severity-bearing alert rows
    /// (CRITICAL/HIGH/MEDIUM/LOW across audit queue + scan blocks + egress) —
    /// disambiguated against TUI 0.7.0 live: 290 = C+H+LOW when the app's
    /// C+H-only count read 265. The menu bar badge stays C+H ("critical/high").
    private var findingsCount: Int {
        appState.unackedAlerts.filter { $0.severity > .info }.count
    }

    private func summaryItem(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.medium))
        }
    }

    private func refresh() {
        Task {
            await appState.pulse()
            await loadData()
        }
    }

    /// Tile/summary/chart reload WITHOUT triggering a pulse — also driven by
    /// the pulse tick (task(id: fetchedAt)) so the tiles track live data the
    /// way the TUI's refresh does, without a pulse→fetchedAt→pulse loop.
    private func loadData() async {
        tiles = await appState.audit.overviewTileCounts()
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
