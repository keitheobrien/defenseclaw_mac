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
    @State private var configurationExpanded = false

    struct HourlyPoint: Identifiable {
        let hour: Date
        let klass: String
        let count: Int
        var id: String { "\(hour.timeIntervalSince1970)-\(klass)" }
    }

    /// The shared connector filter ("" = All) — scopes Configuration,
    /// Enforcement, Scanners, and highlights the Connectors row (TUI parity).
    private var scopeConnector: String { appState.connectorFilter }

    /// " · name" suffix for card titles when a connector is selected.
    private var scopeSuffix: String { scopeConnector.isEmpty ? "" : " · \(scopeConnector.lowercased())" }

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
                quickActionsCard
                configurationCard
                if !appState.health.connectors.isEmpty { connectorCard }
                observabilityCard
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
                connectorScopeChip
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
        .onChange(of: appState.connectorFilter, initial: true) { _, newValue in
            // The TUI dispatches the lazy per-connector aibom load whenever
            // the ENFORCEMENT box renders with a connector selected —
            // `initial: true` covers a filter set before Overview mounted.
            if !newValue.isEmpty { appState.requestEnforcementInventory() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .dcRunHealthCheck)) { _ in runDoctor() }
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

    /// Toolbar connector-scope picker (multi-connector only) — the Overview
    /// equivalent of the TUI's "Connector scope: … (press m to switch)" line.
    @ViewBuilder
    private var connectorScopeChip: some View {
        @Bindable var state = appState
        ConnectorFilterChip(names: appState.activeConnectorNames, selection: $state.connectorFilter)
    }

    private var quickActionsCard: some View {
        DCCard("Quick Actions", systemImage: "bolt") {
            HStack(spacing: 8) {
                Button {
                    runOverviewCommand(
                        title: "Scan all skills",
                        arguments: ["skill", "scan", "--all"],
                        category: "scan",
                        effects: ["Skill scan results refreshed"]
                    )
                } label: {
                    Label("Scan Skills", systemImage: "wand.and.rays")
                }
                Button {
                    appState.selectedPanel = .inventory
                } label: {
                    Label("Open Inventory", systemImage: "shippingbox")
                }
                Button {
                    let action = appState.gatewayReachable ? "restart" : "start"
                    runOverviewCommand(
                        title: "\(action.capitalized) gateway",
                        binary: "defenseclaw-gateway",
                        arguments: [action],
                        category: "daemon",
                        effects: [appState.gatewayReachable ? "Gateway restarted" : "Gateway started"]
                    )
                } label: {
                    Label(appState.gatewayReachable ? "Restart Gateway" : "Start Gateway",
                          systemImage: appState.gatewayReachable ? "arrow.clockwise.circle" : "play.circle")
                }
                Button {
                    runDoctor()
                } label: {
                    Label("Run Doctor", systemImage: "stethoscope")
                }
                .disabled(doctorRunning)
                Menu {
                    Button("Validate Configuration") {
                        runOverviewCommand(title: "Validate configuration", arguments: ["config", "validate"], category: "info")
                    }
                    Button("Check Credentials") {
                        runOverviewCommand(title: "Check credentials", arguments: ["keys", "check"], category: "info")
                    }
                    Button("Gateway Status") {
                        runOverviewCommand(title: "Gateway status", binary: "defenseclaw-gateway", arguments: ["status"], category: "info")
                    }
                    Button("Show Provenance") {
                        runOverviewCommand(title: "Show gateway provenance", binary: "defenseclaw-gateway", arguments: ["provenance", "show"], category: "info")
                    }
                    Divider()
                    Button("Open Command Palette") { appState.commandPalettePresented = true }
                } label: {
                    Label("Diagnostics", systemImage: "ellipsis.circle")
                }
                Spacer()
            }
            .controlSize(.small)
        }
    }

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
                                .font(.callout.weight(.medium))
                                .frame(width: 92, alignment: .leading)
                            Text(svc.state)
                                .font(.caption.monospaced())
                                .foregroundStyle(Cisco.stateColor(raw: svc.state))
                                .frame(width: 66, alignment: .leading)
                            Text(svc.detail)
                                .font(.callout)
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
        DCCard("Configuration\(scopeSuffix)", systemImage: "slider.horizontal.3") {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(appState.configurationRows
                    .prefix(configurationExpanded ? appState.configurationRows.count : 4)
                    .enumerated()), id: \.element.id) { index, row in
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
            if appState.configurationRows.count > 4 {
                Button {
                    withAnimation(.snappy) { configurationExpanded.toggle() }
                } label: {
                    Label(
                        configurationExpanded
                            ? "Show Less"
                            : "Show \(appState.configurationRows.count - 4) More Settings",
                        systemImage: configurationExpanded ? "chevron.up" : "chevron.down"
                    )
                }
                .buttonStyle(.link)
            }
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
            Table(appState.health.connectors, selection: connectorRowSelection) {
                TableColumn("Connector") { c in
                    HStack {
                        Circle().fill(Cisco.stateColor(raw: c.state)).frame(width: 7, height: 7)
                        Text("\(friendlyConnectorName(c.name)) (\(c.name))")
                            .fontWeight(isScoped(c.name) ? .semibold : .regular)
                            .foregroundStyle(isScoped(c.name) ? Cisco.blue : .primary)
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
            if appState.activeConnectorNames.count > 1 {
                HStack {
                    Text(scopeConnector.isEmpty
                         ? "Select a row to scope the Overview to that connector."
                         : "Overview scoped to \(friendlyConnectorName(scopeConnector)).")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if !scopeConnector.isEmpty {
                        Button("Open \(friendlyConnectorName(scopeConnector)) Alerts →") {
                            appState.openAlerts(filter: .all)
                        }
                        .controlSize(.small)
                        .buttonStyle(.link)
                    }
                }
            }
        }
    }

    private func isScoped(_ name: String) -> Bool {
        scopeConnector.lowercased() == name.lowercased()
    }

    /// Row selection ↔ shared connector filter (TUI: selecting a CONNECTORS
    /// row scopes every view; re-selecting All via the chip clears it). The
    /// setter is a no-op on single-connector installs — the TUI's
    /// normalize_filter keeps those permanently at All, and every clear
    /// affordance (chip, ⌃M, caption) is hidden there.
    private var connectorRowSelection: Binding<String?> {
        Binding(
            get: { appState.connectorFilter.isEmpty ? nil : appState.connectorFilter },
            set: { newValue in
                guard appState.activeConnectorNames.count > 1 else { return }
                appState.connectorFilter = newValue ?? ""
            }
        )
    }

    /// Hero right half: the TUI's four tiles as a 2×2 grid. When a connector
    /// is selected the tiles narrow to that connector (title "(name)", fleet
    /// caption) and per-connector aibom coverage rows appear (TUI §ENFORCEMENT).
    private var enforcementTilesCard: some View {
        let scoped = appState.scopedEnforcementMetrics
        let fleet = appState.overviewEnforcementMetrics
        let filtered = !scopeConnector.isEmpty
        return DCCard("Enforcement\(scopeSuffix)", systemImage: "checkmark.shield", fillHeight: true) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                Button {
                    appState.openLogs(.init(stream: .otel, preset: .hooks))
                } label: {
                    StatCard(
                        title: filtered
                            ? "Hook Calls (\(scopeConnector))"
                            : "Hook Calls (\(max(appState.health.connectors.count, 1)) connectors)",
                        value: "\(scoped.hookCalls)", tint: Cisco.blue
                    ) {
                        metricDetail(filtered ? "fleet \(fleet.hookCalls)" : "Latest 500 audit events")
                    }
                }
                .buttonStyle(InteractiveCardButtonStyle())
                .help("Open hook logs")
                .accessibilityHint("Opens Logs filtered to hook calls")

                Button {
                    appState.openAudit(preset: "blocks")
                } label: {
                    StatCard(title: filtered ? "Blocks (\(scopeConnector))" : "Blocks",
                             value: "\(scoped.blocks)",
                             tint: scoped.blocks > 0 ? Cisco.red : .secondary) {
                        metricDetail(filtered ? "fleet \(fleet.blocks)" : "Latest 500 decisions")
                    }
                }
                .buttonStyle(InteractiveCardButtonStyle())
                .help("Open blocked audit events")
                .accessibilityHint("Opens Audit filtered to blocked decisions")

                Button {
                    appState.openAlerts(filter: .all)
                } label: {
                    StatCard(title: filtered ? "Findings (\(scopeConnector))" : "Findings",
                             value: "\(scoped.findings)", tint: Cisco.orange) {
                        metricDetail(filtered ? "fleet \(fleet.findings)" : "Unacknowledged")
                    }
                }
                .buttonStyle(InteractiveCardButtonStyle())
                .help("Open all alerts")
                .accessibilityHint("Opens all unacknowledged alerts")

                Button {
                    appState.openLogs(.init(preset: .guardrail))
                } label: {
                    StatCard(
                        title: guardrailTileTitle,
                        value: appState.config.guardrailEnabled ? "ON" : "OFF",
                        tint: appState.config.guardrailEnabled ? Cisco.green : .secondary
                    ) {
                        metricDetail("Current configuration")
                    }
                }
                .buttonStyle(InteractiveCardButtonStyle())
                .help("Open guardrail logs")
                .accessibilityHint("Opens Logs filtered to guardrail events")
            }
            if filtered { connectorCoverageRows }
            if appState.overviewEnforcementMetrics.updatedAt != .distantPast {
                Text("Updated \(DCDates.relative(appState.overviewEnforcementMetrics.updatedAt))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// Per-connector aibom coverage (filtered ENFORCEMENT rows): Skills with
    /// blocked/allowed split, MCPs configured, Scanned x/y assets — or the
    /// TUI's "scan pending" line until the one-shot inventory load lands.
    @ViewBuilder
    private var connectorCoverageRows: some View {
        Divider()
        if let metrics = appState.enforcementInventory[scopeConnector] {
            VStack(alignment: .leading, spacing: 3) {
                coverageRow("Skills", "\(metrics.skills)   \(metrics.skillsBlocked) blocked   \(metrics.skillsAllowed) allowed")
                coverageRow("MCPs", "\(metrics.mcps) configured")
                coverageRow("Scanned", "\(metrics.scanned)/\(metrics.scannable) assets",
                            tint: metrics.scanned >= metrics.scannable && metrics.scannable > 0 ? Cisco.green : Cisco.orange)
            }
        } else {
            Text("Skills  scan pending — loading inventory…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func coverageRow(_ label: String, _ value: String, tint: Color = .primary) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.caption.monospacedDigit())
                .foregroundStyle(tint)
            Spacer(minLength: 0)
        }
    }

    private func metricDetail(_ scope: String) -> some View {
        HStack(spacing: 4) {
            Text(scope)
                .lineLimit(1)
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private var guardrailTileTitle: String {
        if let mode = appState.config.guardrailMode, !mode.isEmpty {
            return "Guardrail - \(mode)"
        }
        return "Guardrail"
    }

    /// Hero card: scanner/guardrail/keys status, mirroring the TUI's SCANNERS box.
    /// When a connector is selected, two context rows are prepended: the
    /// connector's policy ("mode · rule pack") and its scan coverage.
    private var scannersCard: some View {
        DCCard("Scanners\(scopeSuffix)", systemImage: "magnifyingglass.circle", fillHeight: true) {
            VStack(alignment: .leading, spacing: 6) {
                if !scopeConnector.isEmpty {
                    if !appState.connectorPolicyLabel.isEmpty {
                        scannerContextRow("policy", appState.connectorPolicyLabel, tint: Cisco.blue, filled: true)
                    }
                    if let metrics = appState.enforcementInventory[scopeConnector] {
                        scannerContextRow(
                            "coverage", "\(metrics.scanned)/\(metrics.scannable) assets",
                            tint: metrics.scanned >= metrics.scannable && metrics.scannable > 0 ? Cisco.green : Cisco.orange,
                            filled: metrics.scanned >= metrics.scannable && metrics.scannable > 0
                        )
                    } else {
                        scannerContextRow("coverage", "scan pending", tint: .secondary, filled: false)
                    }
                }
                ForEach(appState.scanners) { s in
                    HStack(spacing: 6) {
                        Circle().fill(scannerColor(s.level)).frame(width: 7, height: 7)
                        Text(s.name)
                            .font(.callout.weight(.medium))
                        Spacer(minLength: 8)
                        Text(s.detail)
                            .font(.callout)
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

    /// TUI ●/○ context row prepended to the filtered SCANNERS box.
    private func scannerContextRow(_ name: String, _ detail: String, tint: Color, filled: Bool) -> some View {
        HStack(spacing: 6) {
            if filled {
                Circle().fill(tint).frame(width: 7, height: 7)
            } else {
                Circle().strokeBorder(tint, lineWidth: 1).frame(width: 7, height: 7)
            }
            Text(name)
                .font(.callout.weight(.medium))
            Spacer(minLength: 8)
            Text(detail)
                .font(.callout)
                .foregroundStyle(tint)
                .lineLimit(1)
                .truncationMode(.tail)
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

    /// Full-width OBSERVABILITY DESTINATIONS · RUNTIME box: every
    /// runtime-loaded OTel destination and audit sink from /health, with
    /// delivery/eligibility routing labels and redacted endpoints (TUI
    /// _overview_observability_panel).
    private var observabilityCard: some View {
        DCCard("Observability Destinations · Runtime", systemImage: "antenna.radiowaves.left.and.right") {
            if appState.health.observabilityRows.isEmpty {
                Text("No runtime-loaded destinations. Configure one in Setup → Observability / Galileo, then restart the gateway.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Table(appState.health.observabilityRows) {
                    TableColumn("Name") { row in
                        Text(row.name).fontWeight(.medium)
                    }
                    TableColumn("Target", value: \.target).width(78)
                    TableColumn("Scope") { row in
                        Text(row.scope).foregroundStyle(.secondary)
                    }
                    .width(70)
                    TableColumn("Kind/Preset") { row in
                        Text(row.kind).foregroundStyle(.secondary)
                    }
                    .width(90)
                    TableColumn("State") { row in
                        Text(row.state)
                            .foregroundStyle(row.state == "enabled" ? Cisco.green : Color.secondary)
                    }
                    .width(64)
                    TableColumn("Signals") { row in
                        Text(row.signals).foregroundStyle(.secondary)
                    }
                    .width(130)
                    TableColumn("Routing") { row in
                        Text(row.routing.nonEmpty ?? "—")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Cisco.sky)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(row.routing.nonEmpty ?? "No routing data yet")
                    }
                    TableColumn("Endpoint") { row in
                        Text(row.endpoint)
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                .frame(height: CGFloat(appState.health.observabilityRows.count) * 28 + 32)
                .scrollDisabled(true)
                Text("Names are identities: a new name adds a route; the same name updates it. Manage in Setup → Observability / Galileo.")
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.tertiary)
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
            let result = await appState.runCommand(
                title: "DefenseClaw Doctor",
                arguments: ["doctor"],
                category: "info",
                origin: "Overview",
                successEffects: ["Diagnostic results refreshed"]
            )
            doctorOutput = result.output
            doctorChecks = parseDoctorChecks(result.output)
            if doctorChecks.isEmpty {
                doctorChecks = [DoctorCheck(name: "doctor exited \(result.exitCode)",
                                            result: result.succeeded ? .pass : .fail,
                                            detail: result.output)]
            }
            doctorRunning = false
        }
    }

    private func runOverviewCommand(
        title: String,
        binary: String = "defenseclaw",
        arguments: [String],
        category: String,
        effects: [String] = []
    ) {
        appState.selectedPanel = .activity
        Task {
            _ = await appState.runCommand(
                title: title,
                binary: binary,
                arguments: arguments,
                category: category,
                origin: "Overview",
                successEffects: effects,
                refreshOnSuccess: true
            )
        }
    }

    private func parseDoctorChecks(_ output: String) -> [DoctorCheck] {
        output.split(separator: "\n").compactMap { raw in
            let line = String(raw)
            let lower = line.lowercased()
            let result: DoctorCheck.Result
            if lower.contains("pass") || lower.contains("✓") || lower.contains(" ok") {
                result = .pass
            } else if lower.contains("warn") || lower.contains("⚠") {
                result = .warn
            } else if lower.contains("fail") || lower.contains("✗") || lower.contains("error") {
                result = .fail
            } else {
                return nil
            }
            let name = line
                .replacingOccurrences(of: "✓", with: "")
                .replacingOccurrences(of: "⚠", with: "")
                .replacingOccurrences(of: "✗", with: "")
                .trimmingCharacters(in: .whitespaces)
            return DoctorCheck(name: String(name.prefix(80)), result: result, detail: line)
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
