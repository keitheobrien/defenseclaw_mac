// Discover panels (spec §9.7, §9.11, §9.12): Inventory, AI Discovery, Registries.

import SwiftUI
import Charts

// MARK: - Inventory

struct InventoryView: View {
    @Environment(AppState.self) private var appState
    @State private var category: InventoryCategory = .skills
    @State private var items: [InventoryItem] = []
    @State private var search = ""
    @State private var scanning = false
    @State private var error: String?
    @State private var lastScan: Date?

    private var filtered: [InventoryItem] {
        let inCategory = items.filter { $0.category == category }
        guard !search.isEmpty else { return inCategory }
        return inCategory.filter { $0.name.lowercased().contains(search.lowercased()) }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Picker("Category", selection: $category) {
                    ForEach(InventoryCategory.allCases) { c in
                        Text("\(c.rawValue) (\(items.filter { $0.category == c }.count))").tag(c)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    if let lastScan {
                        Text("Last scan: \(DCDates.relative(lastScan))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        StaleBadge(date: lastScan)
                    }
                    Spacer()
                    if scanning { ProgressView().controlSize(.small) }
                }
            }
            .padding(10)
            Divider()
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(Cisco.red)
                    .padding(6)
            }
            if filtered.isEmpty {
                DCEmptyState(
                    title: scanning ? "Scanning…" : "No \(category.rawValue.lowercased()) inventoried",
                    message: scanning
                        ? "Running `defenseclaw aibom scan` across every active connector."
                        : "Inventory comes from `defenseclaw aibom scan --json` — the same per-connector bill of materials the TUI shows. Use Rescan to run it.",
                    systemImage: "shippingbox"
                )
                .frame(maxHeight: .infinity)
            } else {
                Table(filtered) {
                    TableColumn("Name", value: \.name)
                    TableColumn("Version", value: \.version).width(70)
                    TableColumn("Connector") { item in
                        Text(item.connector.isEmpty ? "—" : item.connector)
                            .font(.caption)
                            .foregroundStyle(Cisco.blue)
                    }
                    .width(90)
                    TableColumn("Verdict") { item in
                        if item.verdict.isEmpty || item.verdict == "unscanned" {
                            Text(item.verdict.isEmpty ? "—" : item.verdict)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        } else {
                            StatePill(raw: item.verdict)
                        }
                    }
                    .width(100)
                    TableColumn("Path / Source") { item in
                        Text(item.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    }
                    TableColumn("Detail") { item in
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search inventory")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    scan()
                } label: {
                    Label("Rescan All", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(scanning)
            }
        }
        .task { if items.isEmpty { scan() } }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in scan() }
    }

    /// The TUI's Inventory data source: `defenseclaw aibom scan --json` emits
    /// one document per active connector with skills / plugins / mcp / agents /
    /// model_providers / memory arrays (each row carrying scan verdicts).
    private func scan() {
        guard !scanning else { return }
        scanning = true
        appState.scanInFlight = true
        error = nil
        Task {
            let result = await appState.cli.run(arguments: ["aibom", "scan", "--json"])
            defer {
                scanning = false
                appState.scanInFlight = false
            }
            guard result.succeeded,
                  let jsonStart = result.output.firstIndex(of: "["),
                  let data = String(result.output[jsonStart...]).data(using: .utf8),
                  let docs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
            else {
                error = result.succeeded
                    ? "Could not parse `aibom scan --json` output."
                    : "aibom scan failed (exit \(result.exitCode)). \(String(result.output.suffix(200)))"
                return
            }
            items = docs.flatMap(Self.rows(from:))
            lastScan = Date()
        }
    }

    /// Map one per-connector aibom document into inventory rows.
    private static func rows(from doc: [String: Any]) -> [InventoryItem] {
        let connector = (doc["connector"] as? String) ?? ""

        func str(_ r: [String: Any], _ keys: String...) -> String {
            for key in keys {
                if let v = r[key] as? String, !v.isEmpty { return v }
            }
            return ""
        }
        func verdict(_ r: [String: Any]) -> (verdict: String, detail: String) {
            (str(r, "policy_verdict"), str(r, "policy_detail"))
        }
        func rows(_ key: String, _ category: InventoryCategory,
                  _ map: ([String: Any]) -> InventoryItem) -> [InventoryItem] {
            ((doc[key] as? [[String: Any]]) ?? []).map(map)
        }

        return rows("skills", .skills) { r in
            let v = verdict(r)
            let flags = [(r["eligible"] as? Bool) == true ? "eligible" : "not ready",
                         (r["bundled"] as? Bool) == true ? "bundled" : ""]
            return InventoryItem(
                category: .skills, name: str(r, "id", "name"), version: str(r, "version"),
                path: str(r, "path", "source"),
                detail: (flags.filter { !$0.isEmpty } + [v.detail]).filter { !$0.isEmpty }.joined(separator: " · "),
                connector: connector, verdict: v.verdict
            )
        }
        + rows("plugins", .plugins) { r in
            let v = verdict(r)
            return InventoryItem(
                category: .plugins, name: str(r, "name", "id"), version: str(r, "version"),
                path: str(r, "path", "origin"),
                detail: [str(r, "status"), v.detail].filter { !$0.isEmpty }.joined(separator: " · "),
                connector: connector, verdict: v.verdict
            )
        }
        + rows("mcp", .mcps) { r in
            let v = verdict(r)
            return InventoryItem(
                category: .mcps, name: str(r, "id", "name"), version: "",
                path: str(r, "command", "url"),
                detail: [str(r, "source"), v.detail].filter { !$0.isEmpty }.joined(separator: " · "),
                connector: connector, verdict: v.verdict
            )
        }
        + rows("agents", .agents) { r in
            let v = verdict(r)
            return InventoryItem(
                category: .agents, name: str(r, "id", "name"), version: str(r, "version"),
                path: str(r, "path", "source"),
                detail: [str(r, "description"), v.detail].filter { !$0.isEmpty }.joined(separator: " · "),
                connector: connector, verdict: v.verdict
            )
        }
        + rows("model_providers", .providers) { r in
            InventoryItem(
                category: .providers, name: str(r, "name", "id"), version: "",
                path: str(r, "base_url"),
                detail: [str(r, "source"),
                         (r["api_key_present"] as? Bool) == true ? "key present" : "no key"]
                    .filter { !$0.isEmpty }.joined(separator: " · "),
                connector: connector
            )
        }
        + rows("memory", .memories) { r in
            InventoryItem(
                category: .memories, name: str(r, "id", "name"), version: "",
                path: str(r, "path", "source"),
                detail: str(r, "description", "detail", "kind"),
                connector: connector
            )
        }
    }
}

// MARK: - AI Discovery

struct AIDiscoveryView: View {
    @Environment(AppState.self) private var appState
    @State private var snapshot = AIUsageSnapshot()
    @State private var search = ""
    @State private var selected: AIDiscoveryRow?
    @State private var scanning = false
    @State private var error: String?

    /// Grouped rows (one per product), filtered like the TUI's _apply_filter:
    /// substring match across state/product/vendor/component/version/bands/categories/detectors.
    private var filtered: [AIDiscoveryRow] {
        let rows = snapshot.rows
        guard !search.isEmpty else { return rows }
        let query = search.lowercased()
        return rows.filter { row in
            let haystack = ([row.state, row.product, row.vendor, row.ecosystem, row.component,
                             row.version, row.identityBand, row.presenceBand]
                            + row.categories + row.detectors).joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header parity with the TUI: "active=56, files=0".
            HStack(spacing: 12) {
                StatCard(title: "Active Signals", value: "\(snapshot.activeSignals > 0 ? snapshot.activeSignals : snapshot.totalDetected)")
                StatCard(title: "Files Scanned", value: "\(snapshot.filesScanned)", tint: .secondary)
                StatCard(title: "Avg Confidence", value: "\(Int(snapshot.averageConfidence * 100))%",
                         tint: snapshot.averageConfidence > 0.8 ? Cisco.green : Cisco.orange)
                StatCard(title: "Last Scan", value: DCDates.relative(snapshot.lastScan), tint: .secondary)
            }
            .padding(12)
            Divider()
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(Cisco.red).padding(6)
            }
            if filtered.isEmpty {
                DCEmptyState(
                    title: "No AI components",
                    message: "Run a scan to detect AI SDKs and frameworks on this machine (POST /api/v1/ai-usage/scan).",
                    systemImage: "sparkle.magnifyingglass"
                )
                .frame(maxHeight: .infinity)
            } else {
                discoveryTable
            }
        }
        .inspector(isPresented: .constant(selected != nil)) {
            if let row = selected {
                rowInspector(row)
                    .inspectorColumnWidth(min: 320, ideal: 400)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Filter products")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    scan()
                } label: {
                    Label("Scan Now", systemImage: "wand.and.rays")
                }
                .disabled(scanning || !appState.gatewayReachable)
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in Task { await load() } }
    }

    private var rowSelection: Binding<String?> {
        Binding<String?>(
            get: { selected?.id },
            set: { (id: String?) in selected = filtered.first { $0.id == id } }
        )
    }

    /// Column set mirrors the TUI: State · Categories · Product · Component ·
    /// Version · Vendor · Detectors · Count · Identity · Presence.
    private var discoveryTable: some View {
        Table(filtered, selection: rowSelection) {
            TableColumn("State") { (r: AIDiscoveryRow) in
                StatePill(raw: r.state)
            }
            .width(80)
            TableColumn("Categories") { (r: AIDiscoveryRow) in
                Text(AIDiscoveryGrouping.csvTruncated(r.categories))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 130, ideal: 190)
            TableColumn("Product") { (r: AIDiscoveryRow) in
                Text(r.product).font(.callout.weight(.medium))
            }
            .width(min: 110, ideal: 150)
            TableColumn("Component") { (r: AIDiscoveryRow) in
                Text(r.component).font(.caption)
            }
            .width(90)
            TableColumn("Version") { (r: AIDiscoveryRow) in
                Text(r.version.isEmpty ? "—" : r.version).font(.caption)
            }
            .width(70)
            TableColumn("Vendor") { (r: AIDiscoveryRow) in
                Text(r.vendor).font(.caption)
            }
            .width(90)
            TableColumn("Detectors") { (r: AIDiscoveryRow) in
                Text(AIDiscoveryGrouping.csvTruncated(r.detectors))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 130, ideal: 190)
            TableColumn("Count") { (r: AIDiscoveryRow) in
                Text("\(r.count)").font(.caption.monospacedDigit())
            }
            .width(46)
            TableColumn("Identity") { (r: AIDiscoveryRow) in
                Text(AIDiscoveryGrouping.formatConfidence(score: r.identityScore, band: r.identityBand))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .width(90)
            TableColumn("Presence") { (r: AIDiscoveryRow) in
                Text(AIDiscoveryGrouping.formatConfidence(score: r.presenceScore, band: r.presenceBand))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .width(90)
        }
    }

    private func rowInspector(_ row: AIDiscoveryRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(row.vendor.isEmpty ? row.product : "\(row.vendor) / \(row.product)")
                    .font(.headline)
                Spacer()
                Button { selected = nil } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
            }
            KeyValueGrid(pairs: [
                ("State", row.state),
                ("Signals", "\(row.count)"),
                ("Version", row.version.isEmpty ? "—" : row.version),
                ("Categories", row.categories.joined(separator: ", ")),
                ("Detectors", row.detectors.joined(separator: ", ")),
                ("Identity", AIDiscoveryGrouping.formatConfidence(score: row.identityScore, band: row.identityBand)),
                ("Presence", AIDiscoveryGrouping.formatConfidence(score: row.presenceScore, band: row.presenceBand)),
                ("Last active", DCDates.relative(row.lastActive)),
            ].filter { !$0.1.isEmpty })
            Divider()
            Text("Signals").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(row.signals.enumerated()), id: \.offset) { _, signal in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text(signal.detector.isEmpty ? "detector?" : signal.detector)
                                    .font(.caption.weight(.medium))
                                Spacer()
                                ConfidenceGauge(value: signal.confidence)
                            }
                            Text([signal.category, signal.source,
                                  signal.lastSeen.map { "seen \(DCDates.relative($0))" } ?? ""]
                                .filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Cisco.surfacePanel, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            Spacer()
        }
        .padding(12)
    }

    private func load() async {
        guard appState.gatewayReachable else { return }
        do {
            snapshot = try await appState.gateway.aiUsage()
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    private func scan() {
        scanning = true
        appState.scanInFlight = true
        Task {
            do {
                try await appState.gateway.aiScan()
                await load()
                error = nil
            } catch { self.error = "Scan failed: \(error.localizedDescription)" }
            scanning = false
            appState.scanInFlight = false
        }
    }
}

// MARK: - Registries

struct RegistriesView: View {
    @Environment(AppState.self) private var appState
    @State private var sources: [RegistrySource] = []
    @State private var models: [RegistryModel] = []
    @State private var selectedSource: String?
    @State private var search = ""
    @State private var syncing = false
    @State private var error: String?

    private var filteredModels: [RegistryModel] {
        guard !search.isEmpty else { return models }
        return models.filter { $0.name.lowercased().contains(search.lowercased()) }
    }

    var body: some View {
        HSplitView {
            // Sources pane
            VStack(spacing: 0) {
                Text("Sources").font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(6)
                List(sources, selection: $selectedSource) { source in
                    RegistrySourceRow(source: source) { newValue in
                        toggleSource(source, to: newValue)
                    }
                    .tag(source.url)
                }
            }
            .frame(minWidth: 250, idealWidth: 300)

            // Models pane
            VStack(spacing: 0) {
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(Cisco.red).padding(6)
                }
                if filteredModels.isEmpty {
                    DCEmptyState(
                        title: "No models",
                        message: sources.isEmpty
                            ? "No registry sources configured. Add sources in config.yaml (registries:) or via Setup."
                            : "Select a source and sync it to list models.",
                        systemImage: "books.vertical"
                    )
                    .frame(maxHeight: .infinity)
                } else {
                    Table(filteredModels) {
                        TableColumn("Model", value: \.name)
                        TableColumn("Provider", value: \.provider).width(110)
                        TableColumn("Type", value: \.type).width(90)
                        TableColumn("Capabilities") { m in
                            Text(m.capabilities.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search models")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    sync(all: false)
                } label: {
                    Label("Sync Selected", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(syncing || selectedSource == nil)
                Button {
                    sync(all: true)
                } label: {
                    Label("Sync All", systemImage: "arrow.triangle.2.circlepath.circle")
                }
                .disabled(syncing)
                Button {
                    Task { await load() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
        .task { await load() }
        .onChange(of: selectedSource) { _, _ in loadCachedModels() }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in Task { await load() } }
    }

    private var cacheURL: URL { ConfigStore.dataDirectory.appendingPathComponent("registry-cache.json") }

    private struct RegistrySourceRow: View {
        let source: RegistrySource
        let onToggle: (Bool) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Toggle("", isOn: Binding(get: { source.enabled }, set: onToggle))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    Text(source.url).font(.caption).lineLimit(1)
                }
                HStack {
                    Text(source.kind).font(.caption2).foregroundStyle(Cisco.blue)
                    Text("\(source.modelCount) models").font(.caption2).foregroundStyle(.secondary)
                    Text(DCDates.relative(source.lastSync)).font(.caption2).foregroundStyle(.tertiary)
                }
                if let err = source.error {
                    Text(err).font(.caption2).foregroundStyle(Cisco.red).lineLimit(1)
                }
            }
        }
    }

    private func load() async {
        let cfg = await appState.configStore.reload()
        var fresh = cfg.registrySources.map {
            RegistrySource(url: $0.url, kind: $0.kind, enabled: $0.enabled, lastSync: nil, modelCount: 0, error: nil)
        }
        // Merge cache metadata (model counts, last sync).
        if let cache = readCache() {
            for i in fresh.indices {
                if let entry = cache[fresh[i].url] {
                    fresh[i].modelCount = entry.models.count
                    fresh[i].lastSync = entry.syncedAt
                }
            }
        }
        sources = fresh
        loadCachedModels()
    }

    private struct CacheEntry {
        var models: [RegistryModel]
        var syncedAt: Date?
    }

    private func readCache() -> [String: CacheEntry]? {
        guard let data = try? Data(contentsOf: cacheURL),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out: [String: CacheEntry] = [:]
        for (url, value) in obj {
            guard let dict = value as? [String: Any] else { continue }
            let models = ((dict["models"] as? [[String: Any]]) ?? []).map { m in
                RegistryModel(
                    name: (m["name"] as? String) ?? "?",
                    provider: (m["provider"] as? String) ?? "?",
                    type: (m["type"] as? String) ?? "chat",
                    capabilities: (m["capabilities"] as? [String]) ?? []
                )
            }
            out[url] = CacheEntry(models: models, syncedAt: DCDates.parse(dict["synced_at"]))
        }
        return out
    }

    private func loadCachedModels() {
        guard let selectedSource, let cache = readCache(), let entry = cache[selectedSource] else {
            models = []
            return
        }
        models = entry.models
    }

    private func toggleSource(_ source: RegistrySource, to enabled: Bool) {
        guard let idx = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[idx].enabled = enabled
        Task {
            do {
                try await appState.gateway.patchConfig(path: "registries.sources.\(source.url).enabled", value: enabled)
                error = nil
            } catch {
                sources[idx].enabled = !enabled
                self.error = error.localizedDescription
            }
        }
    }

    /// Registry sync runs through the CLI (the gateway does the SSRF-guarded fetch).
    private func sync(all: Bool) {
        syncing = true
        error = nil
        Task {
            var args = ["registry", "sync"]
            if !all, let selectedSource { args += ["--source", selectedSource] }
            let result = await appState.cli.run(arguments: args)
            if !result.succeeded {
                error = "Sync failed (exit \(result.exitCode)). \(String(result.output.suffix(200)))"
            }
            await load()
            syncing = false
        }
    }
}
