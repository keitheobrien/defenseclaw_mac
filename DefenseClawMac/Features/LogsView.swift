// Logs panel (spec §9.8): four source streams, filter chips (severity /
// action / event type / presets ported from FILTER_PRESETS), live tail.

import SwiftUI

struct LogsView: View {
    @Environment(AppState.self) private var appState
    @State private var stream: LogStream = .gateway
    @State private var preset: LogPreset = .noNoise
    @State private var severityFloor: Severity? = nil
    @State private var actionFilter = "all"
    @State private var eventTypeFilter = "all"
    @State private var search = ""
    @State private var rows: [LogRow] = []
    /// Cached filter output. Filtering up to 20k rows inside `body` stalls the
    /// main thread during trackpad scrolling — recompute only when inputs change.
    @State private var filtered: [LogRow] = []
    @State private var autoScroll = true
    /// True while the last row is on screen; auto-scroll only then, so live
    /// tail updates never yank the view away from what the user is reading.
    @State private var isAtBottom = true

    private static let actionOptions = ["all", "block", "allow", "reject", "scan", "verdict", "hook"]
    private static let eventTypeOptions = ["all", "audit", "scan", "hook", "skill", "mcp", "plugin"]

    private func applyFilter() {
        let query = search.lowercased()
        filtered = rows.filter { row in
            if !appState.connectorFilterAllows(row.connector) { return false }
            guard preset.matches(row) else { return false }
            if let severityFloor, row.severity < severityFloor { return false }
            if actionFilter != "all", !row.action.lowercased().contains(actionFilter) { return false }
            if eventTypeFilter != "all", !row.eventType.lowercased().contains(eventTypeFilter) { return false }
            if !query.isEmpty, !row.message.lowercased().contains(query),
               !row.rawJSON.lowercased().contains(query) { return false }
            return true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            if filtered.isEmpty {
                DCEmptyState(
                    title: "No log lines",
                    message: rows.isEmpty
                        ? "No data in \(ConfigStore.gatewayJSONLURL.lastPathComponent) for the \(stream.title) stream yet."
                        : "Nothing matches the current filters.",
                    systemImage: "text.alignleft"
                )
                .frame(maxHeight: .infinity)
            } else {
                logList
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search log lines")
        .toolbar {
            ToolbarItemGroup {
                Toggle(isOn: $autoScroll) {
                    Label("Auto-scroll", systemImage: "arrow.down.to.line")
                }
                .toggleStyle(.button)
                Button {
                    reload()
                } label: {
                    Label("Reload from disk", systemImage: "arrow.clockwise")
                }
            }
        }
        .task {
            if applyPendingPanelRequest() {
                await load(force: true)
            } else {
                await load()
            }
        }
        .task(id: appState.health.fetchedAt) { await load() } // pulse-fed
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in reload() }
        .onChange(of: preset) { _, _ in applyFilter() }
        .onChange(of: severityFloor) { _, _ in applyFilter() }
        .onChange(of: actionFilter) { _, _ in applyFilter() }
        .onChange(of: eventTypeFilter) { _, _ in applyFilter() }
        .onChange(of: search) { _, _ in applyFilter() }
        .onChange(of: appState.connectorFilter) { _, _ in applyFilter() }
        .onChange(of: appState.logPanelRequest) { _, _ in
            guard applyPendingPanelRequest() else { return }
            Task { await load(force: true) }
        }
    }

    private var filterBar: some View {
        @Bindable var state = appState
        return VStack(alignment: .leading, spacing: 6) {
            Picker("Stream", selection: $stream) {
                ForEach(LogStream.allCases) { s in Text(s.title).tag(s) }
            }
            .pickerStyle(.segmented)
            .onChange(of: stream) { _, _ in Task { await load(force: true) } }

            if appState.activeConnectorNames.count > 1 {
                ConnectorFilterChip(names: appState.activeConnectorNames, selection: $state.connectorFilter)
            }

            HStack(spacing: 10) {
                FilterChipRow(
                    options: [("Preset: all", LogPreset.all)] +
                        LogPreset.allCases.dropFirst().map { ($0.rawValue, $0) },
                    selection: $preset
                )
            }
            HStack(spacing: 10) {
                Picker("Severity ≥", selection: $severityFloor) {
                    Text("Any severity").tag(Optional<Severity>.none)
                    ForEach([Severity.critical, .high, .medium, .low], id: \.self) {
                        Text("≥ \($0.rawValue)").tag(Optional($0))
                    }
                }
                .frame(width: 150)
                Picker("Action", selection: $actionFilter) {
                    ForEach(Self.actionOptions, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 120)
                Picker("Event", selection: $eventTypeFilter) {
                    ForEach(Self.eventTypeOptions, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 120)
                Spacer()
                Text("\(filtered.count) / \(rows.count) lines")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List(filtered) { row in
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Cisco.severityColor(row.severity))
                        .frame(width: 3)
                    Text(row.timestamp, format: .dateTime.hour().minute().second())
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(row.stream.rawValue.uppercased())
                        .font(.system(.caption2, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Cisco.blue)
                    Text(row.message)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                .id(row.id)
                .listRowSeparator(.hidden)
                .onAppear { if row.id == filtered.last?.id { isAtBottom = true } }
                .onDisappear { if row.id == filtered.last?.id { isAtBottom = false } }
                .contextMenu {
                    Button("Copy Line") { copyToPasteboard(row.message) }
                    Button("Copy JSON") { copyToPasteboard(row.rawJSON) }
                }
            }
            .listStyle(.plain)
            .onChange(of: filtered.count) { _, _ in
                // Follow the tail only while the user is already at the bottom —
                // never steal the scroll position mid-read.
                if autoScroll, isAtBottom, let last = filtered.last {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    /// Refreshes from the stream buffer, but only publishes when the tail
    /// actually advanced — pulse ticks with no new lines are free.
    private func load(force: Bool = false) async {
        let fresh = await appState.stream.logBuffers[stream] ?? []
        guard force || fresh.count != rows.count || fresh.last?.id != rows.last?.id else { return }
        rows = fresh
        applyFilter()
    }

    private func reload() {
        Task {
            _ = await appState.stream.reload()
            await load(force: true)
        }
    }

    @discardableResult
    private func applyPendingPanelRequest() -> Bool {
        guard let request = appState.consumeLogPanelRequest() else { return false }
        preset = request.preset
        actionFilter = request.actionFilter
        eventTypeFilter = request.eventTypeFilter
        severityFloor = nil
        search = ""
        stream = .gateway
        autoScroll = true
        return true
    }
}
