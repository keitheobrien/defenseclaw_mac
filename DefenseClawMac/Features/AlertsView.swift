// Alerts panel (spec §9.2): unified findings with severity chips, multi-select,
// acknowledge (POST /enforce/allow) with consequence confirmation, export.

import SwiftUI
import Charts

struct AlertsView: View {
    @Environment(AppState.self) private var appState
    @State private var search = ""
    @State private var severityFilter: Severity? = nil
    @State private var kindFilter: String = "all"
    @State private var selection = Set<String>()
    @State private var confirmAck = false

    private var rows: [AlertRow] {
        appState.unackedAlerts.filter { row in
            if !appState.connectorFilterAllows(row.connectorName) { return false }
            if let severityFilter, row.severity != severityFilter { return false }
            if kindFilter == "blocks" {
                guard isBlock(row) else { return false }
            } else if kindFilter != "all", row.kind != kindFilter {
                return false
            }
            if !search.isEmpty {
                let hay = "\(row.action) \(row.target) \(row.details)".lowercased()
                if !hay.contains(search.lowercased()) { return false }
            }
            return true
        }
    }

    private var selectedRows: [AlertRow] {
        rows.filter { selection.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if rows.isEmpty {
                DCEmptyState(
                    title: "No alerts",
                    message: appState.unackedAlerts.isEmpty
                        ? "No unacknowledged security findings. New blocks, scan findings, and egress bypasses appear here live."
                        : "No alerts match the current filters.",
                    systemImage: "checkmark.shield"
                )
                .frame(maxHeight: .infinity)
            } else {
                Table(rows, selection: $selection) {
                    TableColumn("Time") { row in
                        Text(row.timestamp, format: .dateTime.hour().minute().second())
                            .font(.caption.monospacedDigit())
                    }
                    .width(76)
                    TableColumn("Severity") { row in SeverityBadge(severity: row.severity) }
                        .width(86)
                    TableColumn("Kind") { row in
                        Text(row.kind).font(.caption).foregroundStyle(.secondary)
                    }
                    .width(86)
                    TableColumn("Action") { row in Text(row.action).font(.caption) }
                        .width(min: 90, ideal: 130)
                    TableColumn("Target") { row in
                        Text(row.target).font(.caption).lineLimit(1)
                    }
                    .width(min: 110, ideal: 180)
                    TableColumn("Details") { row in
                        Text(row.details).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    TableColumn("Run") { row in
                        Text(row.runID).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
                    }
                    .width(80)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    Button("Copy Details") {
                        let texts = rows.filter { ids.contains($0.id) }
                            .map { "\($0.timestamp) [\($0.severity.rawValue)] \($0.action) \($0.target) — \($0.details)" }
                        copyToPasteboard(texts.joined(separator: "\n"))
                    }
                    Button("Acknowledge Selection…") {
                        selection = ids
                        confirmAck = true
                    }
                    Button("Hide Until Relaunch") {
                        appState.dismiss(rows.filter { ids.contains($0.id) })
                    }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search action, target, details")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    confirmAck = true
                } label: {
                    Label("Acknowledge Selection", systemImage: "checkmark.circle")
                }
                .disabled(selectedRows.isEmpty)
                Button {
                    Task { await appState.refreshAlerts() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in
            Task { await appState.refreshAlerts() }
        }
        .task { applyPendingPanelRequest() }
        .onChange(of: appState.alertPanelRequest) { _, _ in applyPendingPanelRequest() }
        // Audit rows clear the whole severity class via the CLI (stronger confirm
        // than the TUI, spec §15.5); scan/egress rows live in gateway.jsonl and
        // fall through to a local hide (same as Dismiss).
        .confirmationDialog(
            acknowledgmentTitle,
            isPresented: $confirmAck, titleVisibility: .visible
        ) {
            Button(acknowledgmentButtonTitle, role: selectedAuditSeverities.isEmpty ? nil : .destructive) {
                Task {
                    await appState.acknowledge(selectedRows)
                    selection = []
                }
            }
        } message: {
            Text(acknowledgmentMessage)
        }
    }

    @ViewBuilder
    private var header: some View {
        @Bindable var state = appState
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ForEach([Severity.critical, .high, .medium, .low], id: \.self) { sev in
                    let count = appState.unackedAlerts.filter { $0.severity == sev }.count
                    StatCard(title: sev.rawValue, value: "\(count)", tint: Cisco.severityColor(sev))
                }
            }
            ConnectorFilterChip(names: appState.activeConnectorNames, selection: $state.connectorFilter)
            HStack {
                FilterChipRow(
                    "Severity",
                    options: [("All", Optional<Severity>.none)] +
                        [Severity.critical, .high, .medium, .low].map { ($0.rawValue, Optional($0)) },
                    selection: $severityFilter
                )
                Spacer()
                Picker("Kind", selection: $kindFilter) {
                    Text("All kinds").tag("all")
                    Text("Blocks").tag("blocks")
                    Text("Audit").tag("audit")
                    Text("Scans").tag("scan")
                    Text("Egress").tag("egress")
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
        }
        .padding(12)
    }

    private func isBlock(_ row: AlertRow) -> Bool {
        let hay = "\(row.action) \(row.details)".lowercased()
        return hay.contains("block") || hay.contains("reject")
            || hay.contains("deny") || hay.contains("quarantine")
    }

    private var selectedAuditSeverities: [Severity] {
        Array(Set(selectedRows.compactMap { row in
            if case .audit = row { return row.severity }
            return nil
        })).sorted(by: >)
    }

    private var selectedLocalOnlyCount: Int {
        selectedRows.filter { row in
            if case .audit = row { return false }
            return true
        }.count
    }

    private var severityNames: String {
        selectedAuditSeverities.map(\.rawValue).joined(separator: ", ")
    }

    private var acknowledgmentTitle: String {
        if !selectedAuditSeverities.isEmpty {
            return "Acknowledge all \(severityNames) audit findings?"
        }
        return "Hide \(selectedLocalOnlyCount) finding(s) until relaunch?"
    }

    private var acknowledgmentButtonTitle: String {
        selectedAuditSeverities.isEmpty ? "Hide Until Relaunch" : "Acknowledge \(severityNames)"
    }

    private var acknowledgmentMessage: String {
        var parts: [String] = []
        if !selectedAuditSeverities.isEmpty {
            parts.append("DefenseClaw acknowledges entire severity classes in the audit database, not only the selected rows.")
        }
        if selectedLocalOnlyCount > 0 {
            parts.append("\(selectedLocalOnlyCount) scan or egress finding(s) will be hidden locally and can reappear after the app relaunches.")
        }
        return parts.joined(separator: " ")
    }

    private func applyPendingPanelRequest() {
        guard let request = appState.consumeAlertPanelRequest() else { return }
        selection = []
        search = ""
        severityFilter = nil
        switch request {
        case .all:
            kindFilter = "all"
        case .blocks:
            kindFilter = "blocks"
        }
    }
}
