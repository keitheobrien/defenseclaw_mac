// Audit panel (spec §9.9): immutable trail with preset filters
// (all/risk/blocks/scans/credentials), paging, detail inspector, JSON export.

import SwiftUI
import UniformTypeIdentifiers

struct AuditView: View {
    @Environment(AppState.self) private var appState
    @State private var events: [AuditEvent] = []
    @State private var preset = "all"
    @State private var search = ""
    @State private var selection = Set<String>()
    @State private var page = 0
    @State private var exporterPresented = false
    @State private var exportDocument: AuditExportDocument?

    private static let pageSize = 200
    private static let presets: [(String, String)] = [
        ("All", "all"), ("Risk", "risk"), ("Blocks", "blocks"),
        ("Scans", "scans"), ("Credentials", "credentials"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                FilterChipRow(options: Self.presets, selection: $preset)
                Spacer()
                Text("\(events.count) events loaded")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            Divider()
            if events.isEmpty {
                DCEmptyState(
                    title: "No audit events",
                    message: "Nothing in \(ConfigStore.auditDBURL.path) matches. The gateway writes audit events as it enforces policy.",
                    systemImage: "checklist"
                )
                .frame(maxHeight: .infinity)
            } else {
                table
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search action, target, details")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    prepareExport()
                } label: {
                    Label("Export JSON", systemImage: "square.and.arrow.up")
                }
                .keyboardShortcut("e", modifiers: .command)
                Button {
                    load(reset: true)
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task {
            if !applyPendingPanelRequest() {
                load(reset: true)
            }
        }
        .onChange(of: preset) { _, _ in load(reset: true) }
        .onChange(of: search) { _, _ in load(reset: true) }
        .onChange(of: appState.auditPresetRequest) { _, _ in
            _ = applyPendingPanelRequest()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in load(reset: true) }
        .fileExporter(
            isPresented: $exporterPresented,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "defenseclaw-audit-\(Int(Date().timeIntervalSince1970))"
        ) { _ in }
    }

    private var table: some View {
        Table(events, selection: $selection) {
            TableColumn("Time") { e in
                Text(e.timestamp, format: .dateTime.month().day().hour().minute().second())
                    .font(.caption.monospacedDigit())
            }
            .width(130)
            TableColumn("Action") { e in Text(e.action).font(.caption) }
                .width(min: 100, ideal: 140)
            TableColumn("Type") { e in
                Text(e.eventType).font(.caption).foregroundStyle(.secondary)
            }
            .width(70)
            TableColumn("Target") { e in Text(e.target).font(.caption).lineLimit(1) }
                .width(min: 110, ideal: 170)
            TableColumn("Severity") { e in SeverityBadge(severity: e.severity) }
                .width(86)
            TableColumn("Run") { e in
                Text(e.runID).font(.caption2.monospaced()).foregroundStyle(.tertiary).lineLimit(1)
            }
            .width(76)
            TableColumn("Details") { e in
                Text(e.details).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            Button("Copy Details") {
                let texts = events.filter { ids.contains($0.id) }
                    .map { "\($0.timestamp) \($0.action) \($0.target) [\($0.severity.rawValue)] \($0.details)" }
                copyToPasteboard(texts.joined(separator: "\n"))
            }
            Button("Copy Structured JSON") {
                let texts = events.filter { ids.contains($0.id) }.map(\.structuredJSON)
                copyToPasteboard(texts.joined(separator: "\n"))
            }
        } primaryAction: { _ in }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Load older events") {
                    page += 1
                    load(reset: false)
                }
                .controlSize(.small)
                Spacer()
            }
            .padding(6)
            .background(.bar)
        }
    }

    private func load(reset: Bool) {
        if reset { page = 0 }
        Task {
            var severities: [Severity]? = nil
            var actions: [String]? = nil
            switch preset {
            case "risk": severities = [.high, .critical]
            case "blocks": actions = ["block", "reject", "enforce", "quarantine"]
            case "scans": actions = ["scan"]
            case "credentials": actions = ["key", "token", "credential", "auth", "rotat"]
            default: break
            }
            let fresh = await appState.audit.recentEvents(
                limit: Self.pageSize * (page + 1),
                search: search.isEmpty ? nil : search,
                severities: severities,
                actionLike: actions
            )
            events = fresh
        }
    }

    private func prepareExport() {
        // Schema identical to the TUI's export (spec §9.9).
        let source = selection.isEmpty ? events : events.filter { selection.contains($0.id) }
        let payload: [[String: String]] = source.map { e in
            [
                "id": e.id,
                "timestamp": DCDates.iso.string(from: e.timestamp),
                "action": e.action,
                "target": e.target,
                "actor": e.actor,
                "details": e.details,
                "severity": e.severity.rawValue,
                "run_id": e.runID,
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            exportDocument = AuditExportDocument(data: data)
            exporterPresented = true
        }
    }

    @discardableResult
    private func applyPendingPanelRequest() -> Bool {
        guard let requested = appState.consumeAuditPresetRequest() else { return false }
        selection = []
        search = ""
        if preset == requested {
            load(reset: true)
        } else {
            preset = requested
        }
        return true
    }
}

struct AuditExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
