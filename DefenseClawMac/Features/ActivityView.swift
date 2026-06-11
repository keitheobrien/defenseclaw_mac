// Activity panel (spec §9.10): config-mutation feed with red/green diff detail.

import SwiftUI

struct ActivityView: View {
    @Environment(AppState.self) private var appState
    @State private var mutations: [ActivityMutation] = []
    @State private var search = ""
    @State private var selected: ActivityMutation?

    private var filtered: [ActivityMutation] {
        guard !search.isEmpty else { return mutations }
        let q = search.lowercased()
        return mutations.filter {
            "\($0.actor) \($0.action) \($0.targetType) \($0.targetID) \($0.reason)".lowercased().contains(q)
        }
    }

    var body: some View {
        Group {
            if filtered.isEmpty {
                DCEmptyState(
                    title: "No activity",
                    message: "Config mutations (policy reloads, toggles, connector restarts) appear here from gateway.jsonl and the audit DB.",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                Table(filtered, selection: Binding(
                    get: { selected?.id },
                    set: { id in selected = filtered.first { $0.id == id } }
                )) {
                    TableColumn("Time") { m in
                        Text(m.timestamp, format: .dateTime.month().day().hour().minute())
                            .font(.caption.monospacedDigit())
                    }
                    .width(110)
                    TableColumn("Actor") { m in Text(m.actor).font(.caption) }
                        .width(90)
                    TableColumn("Action") { m in Text(m.action).font(.caption) }
                        .width(min: 100, ideal: 140)
                    TableColumn("Target") { m in
                        Text(m.targetType.isEmpty ? m.targetID : "\(m.targetType)/\(m.targetID)")
                            .font(.caption)
                            .lineLimit(1)
                    }
                    TableColumn("From → To") { m in
                        Text(m.versionFrom.isEmpty && m.versionTo.isEmpty ? "—" : "\(m.versionFrom) → \(m.versionTo)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(110)
                    TableColumn("Reason") { m in
                        Text(m.reason).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
        .inspector(isPresented: .constant(selected != nil)) {
            if let m = selected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(m.action).font(.headline)
                        Spacer()
                        Button { selected = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                    KeyValueGrid(pairs: [
                        ("Actor", m.actor),
                        ("Target", "\(m.targetType)/\(m.targetID)"),
                        ("When", m.timestamp.formatted()),
                        ("Reason", m.reason.isEmpty ? "—" : m.reason),
                    ])
                    DiffView(before: m.beforeJSON, after: m.afterJSON)
                    Spacer()
                }
                .padding(12)
                .inspectorColumnWidth(min: 320, ideal: 420)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search activity")
        .toolbar {
            Button {
                load()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .task { load() }
        .task(id: appState.health.fetchedAt) { load() }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in load() }
    }

    private func load() {
        Task {
            let fromDB = await appState.audit.activityEvents(limit: 500)
            let fromStream = await appState.stream.activity
            var seen = Set<String>()
            var merged: [ActivityMutation] = []
            for m in (fromDB + fromStream).sorted(by: { $0.timestamp > $1.timestamp }) {
                let key = "\(m.timestamp.timeIntervalSince1970)-\(m.action)-\(m.targetID)"
                if seen.insert(key).inserted { merged.append(m) }
            }
            // Publish only when content changed — pulse-driven reloads must not
            // re-diff the table (and disturb scrolling) for identical data.
            if merged.map(\.id) != mutations.map(\.id) {
                mutations = merged
            }
        }
    }
}
