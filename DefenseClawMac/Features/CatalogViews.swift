// Govern panels (spec §9.3–§9.6): Skills, MCPs, Plugins, Tools.
// Toggles are optimistic with rollback + error surfacing.

import SwiftUI

// MARK: - Skills

struct SkillsView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [SkillItem] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var filesystemMode = false
    @State private var checkedDirs: [String] = []

    private var filtered: [SkillItem] {
        search.isEmpty ? items : items.filter {
            "\($0.name) \($0.skillDescription) \($0.connector)".lowercased().contains(search.lowercased())
        }
    }

    private var emptyMessage: String {
        if filesystemMode {
            let dirs = checkedDirs.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
            return "No skills found in the connector skill directories:\n\(dirs.joined(separator: "\n"))\n\nNote: plugin/marketplace-provided Claude Code skills live outside these directories and are not scanned by DefenseClaw."
        }
        return "No skills reported by the gateway (GET /skills)."
    }

    var body: some View {
        VStack(spacing: 0) {
            if filesystemMode {
                Label("Hook-mode install: listing skills from the connector skill directories (the gateway /skills catalog needs an OpenClaw agent). Rows are read-only — ✓ marks a ready skill (has SKILL.md / skill.json / README.md).",
                      systemImage: "folder.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.bar)
            }
            CatalogContainer(error: $error, isEmpty: loaded && filtered.isEmpty, emptyMessage: emptyMessage, gatewayDown: !appState.gatewayReachable) {
                Table(filtered) {
                    TableColumn(filesystemMode ? "Ready" : "Enabled") { item in
                        if item.fromFilesystem {
                            Image(systemName: item.enabled ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(item.enabled ? Cisco.green : Color.secondary)
                        } else {
                            Toggle("", isOn: Binding(
                                get: { item.enabled },
                                set: { newValue in toggle(item, to: newValue) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .disabled(!appState.gatewayReachable)
                        }
                    }
                    .width(60)
                    TableColumn("Name", value: \.name)
                    TableColumn("Description") { item in
                        Text(item.skillDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    TableColumn("Connector") { item in
                        Text(item.connector.isEmpty ? "—" : item.connector)
                            .font(.caption)
                            .foregroundStyle(Cisco.blue)
                    }
                    .width(90)
                    TableColumn("Source") { item in
                        Text(item.source.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 180)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search skills")
        .toolbar { RefreshButton { await load() } }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in Task { await load() } }
    }

    /// Gateway catalog first; on failure or an empty answer, fall back to the
    /// filesystem walk the CLI's `skill list` uses (skill_list.py).
    private func load() async {
        var gatewayItems: [SkillItem] = []
        var gatewayError: String?
        do {
            gatewayItems = try await appState.gateway.skills()
        } catch {
            gatewayError = error.localizedDescription
        }

        if !gatewayItems.isEmpty {
            items = gatewayItems
            filesystemMode = false
            error = nil
        } else {
            let result = SkillScanner.scan(connectors: appState.configuredConnectors())
            items = result.items
            checkedDirs = result.checkedDirs
            filesystemMode = true
            // The 502 is expected in hook mode once the fallback kicks in.
            error = result.items.isEmpty ? gatewayError : nil
        }
        loaded = true
    }

    private func toggle(_ item: SkillItem, to enabled: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].enabled = enabled
        Task {
            do {
                try await appState.gateway.setSkill(key: item.key, enabled: enabled)
                error = nil
            } catch {
                items[idx].enabled = !enabled // rollback
                self.error = "Failed to \(enabled ? "enable" : "disable") \(item.name): \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - MCPs

struct MCPsView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [MCPItem] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var editing: MCPItem?
    @State private var filesystemMode = false
    @State private var checkedFiles: [String] = []

    private var filtered: [MCPItem] {
        search.isEmpty ? items : items.filter {
            "\($0.name) \($0.endpoint) \($0.connector)".lowercased().contains(search.lowercased())
        }
    }

    private var emptyMessage: String {
        if filesystemMode {
            let files = checkedFiles.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
            return "No MCP servers registered in the connector config files:\n\(files.joined(separator: "\n"))"
        }
        return "No MCP servers reported by the gateway (GET /mcps)."
    }

    var body: some View {
        VStack(spacing: 0) {
            if filesystemMode {
                Label("Listing MCP registrations from each connector's own config files (Claude Code settings.json, Codex config.toml, …) — the same sources `defenseclaw mcp list` reads. Rows are read-only.",
                      systemImage: "folder.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.bar)
            }
            CatalogContainer(error: $error, isEmpty: loaded && filtered.isEmpty, emptyMessage: emptyMessage, gatewayDown: !appState.gatewayReachable) {
                Table(filtered) {
                    TableColumn("Enabled") { item in
                        if item.fromFilesystem {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Cisco.green)
                                .help("Registered in the connector's config")
                        } else {
                            Toggle("", isOn: Binding(
                                get: { item.enabled },
                                set: { newValue in toggle(item, to: newValue) }
                            ))
                            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            .disabled(!appState.gatewayReachable)
                        }
                    }
                    .width(60)
                    TableColumn("Name", value: \.name)
                    TableColumn("Transport", value: \.transport).width(80)
                    TableColumn("Command / URL") { item in
                        Text(item.endpoint).font(.caption.monospaced()).lineLimit(1)
                    }
                    TableColumn("Connector") { item in
                        Text(item.connector.isEmpty ? "—" : item.connector)
                            .font(.caption)
                            .foregroundStyle(Cisco.blue)
                    }
                    .width(90)
                    TableColumn("Source") { item in
                        Text(item.source.isEmpty ? "—" : item.source.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 180)
                    TableColumn("") { item in
                        if !item.fromFilesystem {
                            Button("Edit…") { editing = item }
                                .controlSize(.small)
                                .disabled(!appState.gatewayReachable)
                        }
                    }
                    .width(60)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search MCPs")
        .toolbar { RefreshButton { await load() } }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in Task { await load() } }
        .sheet(item: $editing) { item in
            MCPEditSheet(item: item) { field, value in
                Task {
                    do {
                        try await appState.gateway.patchConfig(path: "mcps.\(item.name).\(field)", value: value)
                        await load()
                    } catch { self.error = error.localizedDescription }
                }
            }
        }
    }

    /// Gateway catalog first; on failure or an empty answer, read each
    /// connector's own MCP registry files (connector_paths.mcp_servers).
    private func load() async {
        var gatewayItems: [MCPItem] = []
        var gatewayError: String?
        do {
            gatewayItems = try await appState.gateway.mcps()
        } catch {
            gatewayError = error.localizedDescription
        }

        if !gatewayItems.isEmpty {
            items = gatewayItems
            filesystemMode = false
            error = nil
        } else {
            let result = MCPScanner.scan(connectors: appState.configuredConnectors())
            items = result.items
            checkedFiles = result.checkedFiles
            filesystemMode = true
            error = result.items.isEmpty ? gatewayError : nil
        }
        loaded = true
    }

    private func toggle(_ item: MCPItem, to enabled: Bool) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].enabled = enabled
        Task {
            do {
                try await appState.gateway.setMCP(name: item.name, enabled: enabled)
                error = nil
            } catch {
                items[idx].enabled = !enabled
                self.error = "Failed to toggle \(item.name): \(error.localizedDescription)"
            }
        }
    }
}

/// Port of MCPSetFormScreen: PATCH /config/patch per edited field.
private struct MCPEditSheet: View {
    let item: MCPItem
    let onSave: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var endpoint: String
    @State private var transport: String

    init(item: MCPItem, onSave: @escaping (String, String) -> Void) {
        self.item = item
        self.onSave = onSave
        _endpoint = State(initialValue: item.endpoint)
        _transport = State(initialValue: item.transport)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit MCP: \(item.name)").font(.headline)
            Form {
                Picker("Transport", selection: $transport) {
                    Text("stdio").tag("stdio")
                    Text("http").tag("http")
                }
                TextField("Endpoint / command", text: $endpoint)
                    .font(.body.monospaced())
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    if transport != item.transport { onSave("transport", transport) }
                    if endpoint != item.endpoint { onSave("endpoint", endpoint) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}

// MARK: - Plugins

struct PluginsView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [PluginItem] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var pendingToggle: (item: PluginItem, to: Bool)?
    @State private var busy: Set<String> = []
    @State private var filesystemMode = false
    @State private var checkedDirs: [String] = []

    private var filtered: [PluginItem] {
        search.isEmpty ? items : items.filter {
            "\($0.name) \($0.connector)".lowercased().contains(search.lowercased())
        }
    }

    private var emptyMessage: String {
        if filesystemMode {
            let dirs = checkedDirs.map { $0.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
            return "No plugins found in the connector plugin directories:\n\(dirs.joined(separator: "\n"))"
        }
        return "No plugins reported by the gateway (GET /status)."
    }

    var body: some View {
        VStack(spacing: 0) {
            if filesystemMode {
                Label("Listing plugins from each connector's plugin directories (~/.claude/plugins, ~/.codex/plugins, …) — the same walk `defenseclaw plugin list` uses. Rows are read-only — ✓ marks a recognized manifest.",
                      systemImage: "folder.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.bar)
            }
            CatalogContainer(error: $error, isEmpty: loaded && filtered.isEmpty, emptyMessage: emptyMessage, gatewayDown: !appState.gatewayReachable) {
                Table(filtered) {
                    TableColumn(filesystemMode ? "Manifest" : "Enabled") { item in
                        if item.fromFilesystem {
                            Image(systemName: item.hasManifest ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundStyle(item.hasManifest ? Cisco.green : Color.secondary)
                                .help(item.hasManifest ? "Recognized plugin manifest" : "No recognized manifest")
                        } else if busy.contains(item.name) {
                            ProgressView().controlSize(.small)
                        } else {
                            Toggle("", isOn: Binding(
                                get: { item.enabled },
                                set: { newValue in pendingToggle = (item, newValue) } // confirm first (parity)
                            ))
                            .labelsHidden().toggleStyle(.switch).controlSize(.mini)
                            .disabled(!appState.gatewayReachable)
                        }
                    }
                    .width(60)
                    TableColumn("Name", value: \.name)
                    TableColumn("Version", value: \.version).width(90)
                    TableColumn(filesystemMode ? "Manifest file" : "Category", value: \.category).width(150)
                    TableColumn("Connector") { item in
                        Text(item.connector.isEmpty ? "—" : item.connector)
                            .font(.caption)
                            .foregroundStyle(Cisco.blue)
                    }
                    .width(90)
                    TableColumn("Source") { item in
                        Text(item.source.isEmpty ? "—" : item.source.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 100, ideal: 180)
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search plugins")
        .toolbar { RefreshButton { await load() } }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in Task { await load() } }
        .confirmationDialog(
            "\(pendingToggle?.to == true ? "Enable" : "Disable") plugin “\(pendingToggle?.item.name ?? "")”?",
            isPresented: .constant(pendingToggle != nil), titleVisibility: .visible
        ) {
            Button(pendingToggle?.to == true ? "Enable" : "Disable") {
                if let pending = pendingToggle { apply(pending.item, to: pending.to) }
                pendingToggle = nil
            }
            Button("Cancel", role: .cancel) { pendingToggle = nil }
        } message: {
            Text("Plugin changes restart hooks in the connector and can take up to 90 seconds.")
        }
    }

    /// Gateway plugin roster first; on failure or an empty answer, walk each
    /// connector's plugin directories (claw_inventory._enumerate_plugins_filesystem).
    private func load() async {
        var gatewayItems: [PluginItem] = []
        var gatewayError: String?
        do {
            gatewayItems = try await appState.gateway.plugins()
        } catch {
            gatewayError = error.localizedDescription
        }

        if !gatewayItems.isEmpty {
            items = gatewayItems
            filesystemMode = false
            error = nil
        } else {
            let result = PluginScanner.scan(connectors: appState.configuredConnectors())
            items = result.items
            checkedDirs = result.checkedDirs
            filesystemMode = true
            error = result.items.isEmpty ? gatewayError : nil
        }
        loaded = true
    }

    private func apply(_ item: PluginItem, to enabled: Bool) {
        busy.insert(item.name)
        Task {
            do {
                try await appState.gateway.setPlugin(name: item.name, enabled: enabled)
                if let idx = items.firstIndex(where: { $0.id == item.id }) {
                    items[idx].enabled = enabled
                }
                error = nil
            } catch {
                self.error = "Plugin \(item.name): \(error.localizedDescription)"
            }
            busy.remove(item.name)
        }
    }
}

// MARK: - Tools

struct ToolsView: View {
    @Environment(AppState.self) private var appState
    @State private var items: [ToolItem] = []
    @State private var search = ""
    @State private var error: String?
    @State private var loaded = false
    @State private var selected: ToolItem?
    @State private var overridesOnly = false

    private var filtered: [ToolItem] {
        search.isEmpty ? items : items.filter {
            $0.name.lowercased().contains(search.lowercased()) || $0.summary.lowercased().contains(search.lowercased())
        }
    }

    private var emptyMessage: String {
        overridesOnly
            ? "No tool overrides yet. The full tool catalog needs an OpenClaw agent behind the gateway; on hook-based installs this panel shows the block/allow overrides recorded in the audit DB's actions table — and there are none so far. Block a tool from the Alerts or Audit context, or via `defenseclaw enforce`, and it will appear here."
            : "No tools in the catalog (GET /tools/catalog)."
    }

    var body: some View {
        VStack(spacing: 0) {
            if overridesOnly, !filtered.isEmpty {
                Label("Hook-mode install: showing the tool block/allow overrides from the audit DB (the full catalog needs an OpenClaw agent). State changes still apply — overrides enforce on the next hook evaluation.",
                      systemImage: "folder.badge.questionmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.bar)
            }
            toolsContainer
        }
    }

    private var toolsContainer: some View {
        CatalogContainer(error: $error, isEmpty: loaded && filtered.isEmpty, emptyMessage: emptyMessage, gatewayDown: !appState.gatewayReachable) {
            Table(filtered, selection: Binding(
                get: { selected?.id },
                set: { id in selected = filtered.first { $0.id == id } }
            )) {
                TableColumn("Tool", value: \.name)
                TableColumn("Description") { t in
                    Text(t.summary).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                TableColumn("State") { t in
                    Picker("", selection: Binding(
                        get: { t.state },
                        set: { newState in setState(t, to: newState) }
                    )) {
                        ForEach(ToolState.allCases) { s in Text(s.rawValue).tag(s) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 190)
                    .disabled(!appState.gatewayReachable)
                }
                .width(200)
                TableColumn("Usage") { t in
                    Text("\(t.usageCount)").font(.caption.monospacedDigit())
                }
                .width(50)
            }
        }
        .inspector(isPresented: .constant(selected != nil)) {
            if let t = selected {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(t.name).font(.headline)
                        Spacer()
                        Button { selected = nil } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless)
                    }
                    Text(t.summary).font(.callout)
                    if !t.signature.isEmpty {
                        Text("Signature").font(.caption).foregroundStyle(.secondary)
                        ScrollView {
                            Text(t.signature)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 240)
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search tools")
        .toolbar { RefreshButton { await load() } }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in Task { await load() } }
    }

    /// Tool catalog from the gateway when an OpenClaw agent serves it; in
    /// hook mode fall back to the actions-table overrides — the catalog
    /// endpoint 502s there, but block/allow overrides still exist and
    /// enforce, so show (and let the user edit) exactly those.
    private func load() async {
        var catalog: [ToolItem] = []
        var gatewayError: String?
        do {
            catalog = try await appState.gateway.toolsCatalog()
        } catch {
            gatewayError = error.localizedDescription
        }

        let overrides = await appState.audit.toolOverrides()
        if !catalog.isEmpty {
            for i in catalog.indices {
                if let state = overrides[catalog[i].name] { catalog[i].state = state }
            }
            items = catalog
            overridesOnly = false
            error = nil
        } else {
            items = await appState.audit.toolOverrideRows()
            overridesOnly = true
            // Overrides displayed (or none exist) — the 502 is expected in hook mode.
            error = items.isEmpty && gatewayError != nil && !appState.gatewayReachable ? gatewayError : nil
        }
        loaded = true
    }

    private func setState(_ tool: ToolItem, to state: ToolState) {
        guard let idx = items.firstIndex(where: { $0.id == tool.id }) else { return }
        let previous = items[idx].state
        items[idx].state = state
        Task {
            do {
                switch state {
                case .block:
                    try await appState.gateway.enforceBlock(targetType: "tool", targetName: tool.name,
                                                            reason: "Blocked from DefenseClaw for macOS")
                case .allow, .observe:
                    try await appState.gateway.enforceAllow(targetType: "tool", targetName: tool.name,
                                                            reason: "Allowed from DefenseClaw for macOS")
                }
                error = nil
            } catch {
                items[idx].state = previous
                self.error = "Tool \(tool.name): \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Shared chrome

struct CatalogContainer<Content: View>: View {
    @Binding var error: String?
    let isEmpty: Bool
    let emptyMessage: String
    let gatewayDown: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            if let error {
                HStack {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Cisco.red)
                    Spacer()
                    Button { self.error = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                }
                .padding(8)
                .background(Cisco.red.opacity(0.08))
            }
            if gatewayDown {
                Label("Gateway offline — toggles disabled until it returns.", systemImage: "bolt.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(6)
                    .background(.bar)
            }
            if isEmpty {
                DCEmptyState(title: "Nothing here", message: emptyMessage, systemImage: "tray")
                    .frame(maxHeight: .infinity)
            } else {
                content
            }
        }
    }
}

struct RefreshButton: ToolbarContent {
    let action: () async -> Void
    var body: some ToolbarContent {
        ToolbarItem {
            Button {
                Task { await action() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
    }
}
