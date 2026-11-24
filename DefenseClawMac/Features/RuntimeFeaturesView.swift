// Copyright 2026 Cisco Systems, Inc. and its affiliates
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

struct RuntimeFeaturesView: View {
    enum Area { case routing, substrate, controls }
    let area: Area
    var initialTab = "Routing"
    @Environment(AppState.self) private var appState
    @State private var action: RuntimeFeatureAction?
    @State private var tab = "Routing"
    @State private var period = "7d"
    @State private var grouping = "model"
    @State private var refreshID = UUID()
    @State private var status: [String: Any] = [:]
    @State private var detail: [String: Any] = [:]
    @State private var error = ""
    @State private var loading = false
    @State private var unappliedReads = 0

    private var available: Bool { Runtime1010Features.supported(appState.installedRuntimeVersion) }
    private var managed: Bool { (area == .routing && status["managed"] as? Bool != false) || !appState.installationMutationsAllowed }
    private var actions: [RuntimeFeatureAction] {
        switch area {
        case .routing: Runtime1010Features.routing + Runtime1010Features.pricing + [Runtime1010Features.context, Runtime1010Features.configuration]
        case .substrate: Runtime1010Features.substrate
        case .controls: Runtime1010Features.guardrail
        }
    }
    private var readKey: String { "\(appState.installationGeneration)|\(tab)|\(period)|\(grouping)|\(refreshID)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(area == .routing ? "Model Routing" : area == .substrate ? "Agent Substrate" : "Runtime Controls")
                    .font(.title2.weight(.semibold))
                Spacer()
                if loading { ProgressView().controlSize(.small) }
                if area != .controls {
                    Button("Refresh", systemImage: "arrow.clockwise") { refreshID = UUID() }.disabled(!available)
                }
            }
            if !available {
                Text("These features require DefenseClaw runtime 1.0.10 or later. Check the selected runtime in Settings → Connection.")
                    .foregroundStyle(.secondary)
            } else {
                if let reason = appState.installationReadOnlyReason {
                    Label(reason, systemImage: "lock.shield").foregroundStyle(.secondary)
                } else if status["managed"] as? Bool == true {
                    Label("Routing is managed by your administrator. Your permitted view is shown below.", systemImage: "lock.shield")
                }
                actionBar
                if area == .routing {
                    Picker("View", selection: $tab) {
                        ForEach(["Routing", "Usage", "Prices"], id: \.self) { Text($0) }
                    }.pickerStyle(.segmented)
                    if tab == "Usage" {
                        HStack {
                            Picker("Period", selection: $period) {
                                Text("Day").tag("24h"); Text("Week").tag("7d"); Text("Month").tag("30d")
                            }
                            Picker("Group by", selection: $grouping) {
                                ForEach(["model", "connector", "route", "user", "group", "profile"], id: \.self) { Text($0.capitalized) }
                            }
                        }
                    }
                }
                if !error.isEmpty { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Cisco.orange).textSelection(.enabled) }
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if area == .routing { routingContent }
                        else if area == .substrate { substrateContent }
                        else { controlsContent }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .onAppear { tab = initialTab }
        .task(id: readKey) { await load() }
        .onReceive(NotificationCenter.default.publisher(for: .dcRefreshPanel)) { _ in refreshID = UUID() }
        .sheet(item: $action) { item in
            RuntimeFeatureActionSheet(action: item).environment(appState)
        }
    }

    private var actionBar: some View {
        HStack {
            Menu("Actions") {
                ForEach(actions) { item in
                    Button(item.title) { action = item }
                        .disabled(item.mutation && managed)
                }
            }
            if area == .routing {
                Button("Set Up Routing…") { action = Runtime1010Features.routing[0] }.disabled(managed)
                Button("Add Model…") { action = Runtime1010Features.routing[1] }.disabled(managed)
            }
            if area == .controls {
                Button("Explain Cascade…") { action = Runtime1010Features.guardrail[0] }
                Button("Edit Runtime Settings…") { action = Runtime1010Features.configuration }.disabled(managed)
            }
            Spacer()
            Button("Activity") { appState.selectedPanel = .activity }
        }
    }

    @ViewBuilder private var routingContent: some View {
        if tab == "Routing" {
            if !status.isEmpty {
                let health = status["health"] as? [String: Any] ?? [:]
                let enabled = status["enabled"] as? Bool == true
                let applying = enabled && health["state"] as? String == "disabled"
                Text("Routing \(enabled ? "on" : "off") · classifier \(RuntimeFeatureJSON.render(status["classifier"]))")
                    .font(.headline)
                Text(applying ? (unappliedReads < 6 ? "Applying: waiting for the gateway to load this change." : "Not applied: the gateway still has routing disabled. Review Activity and restart the gateway if needed.") : "Gateway: \(RuntimeFeatureJSON.render(health["state"]))")
                    .foregroundStyle(applying ? Cisco.orange : .secondary)
                ForEach((status["warnings"] as? [String] ?? []).indices, id: \.self) { index in
                    Text((status["warnings"] as? [String] ?? [])[index]).foregroundStyle(Cisco.orange)
                }
                let rows = RuntimeFeatureJSON.routingRows(status)
                if rows.isEmpty {
                    Text(managed ? "No routing entries are shared with this account." : "No models, rules, or budgets yet. Add a model to get started.").foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    GroupBox("\(row.kind): \(row.name)") {
                        Text(row.detail).font(.caption.monospaced()).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let effective = status["effective"] as? [String: Any] {
                    DisclosureGroup("Effective routing and recent decisions") {
                        Text(RuntimeFeatureJSON.render(effective)).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Text("Advanced settings include conversation context, classifier behavior, administrator policy, and fleet budget configuration.").font(.caption).foregroundStyle(.secondary)
            }
        } else if tab == "Usage" {
            if !detail.isEmpty {
                Text("Usage · \(detail["scope"] as? String == "all" ? "everyone" : "your account")").font(.headline)
                if let hint = detail["hint"] as? String { Text(hint).foregroundStyle(.secondary) }
                let rows = RuntimeFeatureJSON.records(detail["rows"])
                if rows.isEmpty { Text("No recorded model calls for this period. Enable usage recording to collect new calls.").foregroundStyle(.secondary) }
                ForEach(rows.indices, id: \.self) { index in
                    let row = rows[index]
                    GroupBox(RuntimeFeatureJSON.render(row["key"])) {
                        LabeledContent("Calls", value: RuntimeFeatureJSON.render(row["calls"]))
                        LabeledContent("Input tokens", value: RuntimeFeatureJSON.render(row["input_tokens"]))
                        LabeledContent("Output tokens", value: RuntimeFeatureJSON.render(row["output_tokens"]))
                        LabeledContent("Cost", value: RuntimeFeatureJSON.cost(row["cost_usd"]))
                        if let basis = row["cost_basis"] as? String { Text(basis).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
        } else if error.isEmpty && !loading {
            Text("Prices are USD per million tokens. Review the table against your provider agreement; the runtime's default prices are not verified current prices.").font(.callout)
            let prices = RuntimeFeatureJSON.records(detail["models"])
            if prices.isEmpty { Text("No price table configured. Use Actions → Set model prices or Import prices.").foregroundStyle(.secondary) }
            Text("Price table: \(RuntimeFeatureJSON.render(detail["version"]))").font(.headline)
            ForEach(prices.indices, id: \.self) { index in
                let price = prices[index]
                GroupBox("\(RuntimeFeatureJSON.render(price["provider"]))/\(RuntimeFeatureJSON.render(price["model"]))") {
                    LabeledContent("Input", value: RuntimeFeatureJSON.cost(price["input_per_mtok"]))
                    LabeledContent("Output", value: RuntimeFeatureJSON.cost(price["output_per_mtok"]))
                    LabeledContent("Cache read", value: RuntimeFeatureJSON.cost(price["cache_read_per_mtok"]))
                    LabeledContent("Cache write", value: RuntimeFeatureJSON.cost(price["cache_write_per_mtok"]))
                    LabeledContent("Reasoning", value: RuntimeFeatureJSON.cost(price["reasoning_per_mtok"]))
                }
            }
        }
    }

    @ViewBuilder private var substrateContent: some View {
        Text("Manage agents in an existing Agent Substrate cluster. Sign-in, interactive sessions, and pulling work use Terminal; cluster deployment uses the runtime's Helm chart.").foregroundStyle(.secondary)
        if !detail.isEmpty {
            let actors = RuntimeFeatureJSON.records(detail["actors"]).filter { $0["deleted"] as? Bool != true }
            if actors.isEmpty { Text("No active agents are visible to this account.") }
            if actors.count > 50 { Text("Showing 50 of \(actors.count) agents. Use Actions → List agents for the complete list.").foregroundStyle(.secondary) }
            ForEach(actors.prefix(50).indices, id: \.self) { index in
                let row = actors[index]
                GroupBox(RuntimeFeatureJSON.render(row["name"])) {
                    LabeledContent("State", value: RuntimeFeatureJSON.render(row["state"]))
                    LabeledContent("Connector", value: RuntimeFeatureJSON.render(row["connector"]))
                    LabeledContent("Profile", value: RuntimeFeatureJSON.render(row["profile"]))
                    LabeledContent("Namespace", value: RuntimeFeatureJSON.render(row["atespace"]))
                    LabeledContent("Template", value: RuntimeFeatureJSON.render(row["template"]))
                }
            }
        }
    }

    private var controlsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Runtime1010Features.guardrail) { item in
                GroupBox(item.title) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(item.help).foregroundStyle(.secondary)
                        Button("Open…") { action = item }.disabled(item.mutation && managed)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Text("Cascade settings include alignment and per-profile or per-connector overrides. OpenClaw settings include native hooks, the prompt gate, installation policy, and externally managed plugin layouts. Gemini Decisions protocol is also available in Setup → Config Editor → Decision Model.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @MainActor private func load() async {
        let generation = appState.installationGeneration
        let key = readKey
        status = [:]; detail = [:]; error = ""; unappliedReads = 0
        guard available, area != .controls else { return }
        loading = true
        defer { if readKey == key { loading = false } }
        if area == .routing && tab != "Routing" {
            let scope = await appState.runCommand(title: "Read routing permissions", arguments: ["routing", "status", "--json"], mutation: false, category: "info", origin: "Runtime features")
            guard !Task.isCancelled, generation == appState.installationGeneration, key == readKey else { return }
            if scope.succeeded, !scope.outputTruncated { status = RuntimeFeatureJSON.object(scope.output) ?? [:] }
        }
        for attempt in 0..<6 {
            guard !Task.isCancelled, generation == appState.installationGeneration, key == readKey else { return }
            let arguments: [String]
            if area == .substrate { arguments = ["substrate", "list", "--json"] }
            else if tab == "Usage" { arguments = ["routing", "usage", "--json", "--since", period, "--by", grouping] }
            else if tab == "Prices" { arguments = ["routing", "pricing", "show", "--json"] }
            else { arguments = ["routing", "status", "--json"] }
            let result = await appState.runCommand(title: area == .substrate ? "Read Substrate agents" : "Read routing \(tab.lowercased())", arguments: arguments, mutation: false, category: "info", origin: "Runtime features")
            guard !Task.isCancelled, generation == appState.installationGeneration, key == readKey else { return }
            guard result.succeeded, !result.outputTruncated, let object = RuntimeFeatureJSON.object(result.output) else {
                error = area == .substrate && result.exitCode == 4 ? "Not signed in to Agent Substrate. Use Actions → Sign in." : "The runtime could not load this view. Check the recorded result in Activity."
                return
            }
            if area == .routing && tab == "Routing" {
                status = object
                let health = object["health"] as? [String: Any] ?? [:]
                guard object["enabled"] as? Bool == true, health["state"] as? String == "disabled" else { return }
                unappliedReads = attempt + 1
                if attempt < 5 { try? await Task.sleep(for: .seconds(2)) }
            } else { detail = object; return }
        }
    }
}

struct RuntimeFeatureActionSheet: View {
    let action: RuntimeFeatureAction
    var initialValues: [String: String] = [:]
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]
    @State private var generation: Int?
    @State private var reviewing = false
    @State private var running = false
    @State private var output = ""
    @State private var runID: UUID?
    @State private var cancelled = false
    @State private var configRead: (key: String, sha256: String)?

    private var selectionCurrent: Bool { generation == appState.installationGeneration }
    private var allowed: Bool { selectionCurrent && Runtime1010Features.supported(appState.installedRuntimeVersion) && (!action.mutation || appState.installationMutationsAllowed) }
    private var validation: String? {
        if let problem = action.validation(values) { return problem }
        if action.configuration && configRead?.key != action.configKey(values) { return "Read the current setting before saving a replacement." }
        return nil
    }
    private var preview: String {
        action.configuration ? "Update \(action.configKey(values)) using the value reviewed below."
            : ([action.binary] + action.command(values)).map(ShellQuoting.quote).joined(separator: " ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(action.title).font(.title2.weight(.semibold))
            Text(action.help).font(.callout).foregroundStyle(.secondary)
            if !selectionCurrent { Text("The selected installation changed. Close and reopen this form.").foregroundStyle(Cisco.orange) }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if reviewing {
                        Text(preview).font(.caption.monospaced()).textSelection(.enabled)
                        if action.configuration {
                            Text(action.configurationValue(values)).font(.caption.monospaced()).textSelection(.enabled)
                            Text("This replaces the selected setting. Do not save masked values from a read-back as credentials.").foregroundStyle(Cisco.orange)
                        }
                    } else {
                        ForEach(action.fields) { field in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label).font(.callout.weight(.medium))
                                if !field.choices.isEmpty {
                                    Picker(field.label, selection: binding(field)) {
                                        ForEach(field.choices, id: \.self) { Text($0.isEmpty ? "Default / none" : $0.trimmingCharacters(in: CharacterSet(charactersIn: "\""))).tag($0) }
                                    }.labelsHidden()
                                } else if field.repeated || field.key == "value" {
                                    TextEditor(text: binding(field)).font(.caption.monospaced()).frame(minHeight: field.key == "value" ? 140 : 60).border(.quaternary)
                                } else {
                                    TextField(field.label, text: binding(field)).textFieldStyle(.roundedBorder)
                                }
                                if !field.hint.isEmpty { Text(field.hint).font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    if !output.isEmpty { Text(output).font(.caption.monospaced()).textSelection(.enabled) }
                }
            }
            if let validation, !reviewing { Text(validation).font(.caption).foregroundStyle(Cisco.orange) }
            HStack {
                Button(running ? "Cancel Operation" : "Close") {
                    if let runID, running { cancelled = true; appState.activity.cancel(runID) } else { dismiss() }
                }
                if action.configuration && !reviewing {
                    Button("Read Current Value") { execute(read: true) }.disabled(running || !selectionCurrent)
                }
                Spacer()
                if running { ProgressView().controlSize(.small) }
                else if reviewing {
                    Button("Back") { reviewing = false }
                    if action.terminal {
                        Button("Copy for Terminal") { copyCommand() }.disabled(!allowed)
                    } else {
                        Button(action.mutation ? "Apply Change" : "Run") { execute() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!allowed || validation != nil)
                    }
                } else {
                    Button("Review") { reviewing = true; output = "" }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent).disabled(!allowed || validation != nil)
                }
            }
        }
        .padding(20).frame(width: 700, height: 660)
        .onAppear {
            generation = appState.installationGeneration
            values = Dictionary(uniqueKeysWithValues: action.fields.map { ($0.key, $0.initial) }).merging(initialValues) { _, new in new }
        }
    }

    private func binding(_ field: RuntimeFeatureField) -> Binding<String> {
        Binding(get: { values[field.key, default: field.initial] }, set: { values[field.key] = $0 })
    }

    private func copyCommand() {
        guard allowed else { return }
        let context = appState.installationContext
        let capturedGeneration = appState.installationGeneration
        let arguments = action.command(values)
        let cli = appState.cli
        Task { @MainActor in
            guard let binary = await cli.locateBinary(named: action.binary),
                  capturedGeneration == appState.installationGeneration, allowed else {
                output = "The selected runtime is unavailable, or the installation changed."
                return
            }
            let command = ["env", "DEFENSECLAW_HOME=\(context.homeRoot.path)", "DEFENSECLAW_CONFIG=\(context.configURL.path)", binary] + arguments
            copyToPasteboard(command.map(ShellQuoting.quote).joined(separator: " "))
            output = "Copied for the selected installation. Run the command in Terminal."
        }
    }

    private func execute(read: Bool = false) {
        guard selectionCurrent, !running, read || (allowed && validation == nil) else { return }
        let capturedGeneration = appState.installationGeneration
        let capturedValues = values
        let cli = appState.cli
        let id = UUID()
        runID = id; running = true; cancelled = false; output = ""
        Task { @MainActor in
            defer { running = false; runID = nil }
            var binary = action.binary
            var arguments = action.command(capturedValues)
            var input: String?
            if action.configuration {
                guard let python = await cli.locateRuntimePython(), capturedGeneration == appState.installationGeneration else {
                    output = "The selected runtime's interpreter is unavailable, or the installation changed."
                    return
                }
                binary = python
                arguments = ["-c", Runtime1010Features.configScript]
                let request = ["operation": read ? "read" : "write", "key": action.configKey(capturedValues), "value": action.configurationValue(capturedValues), "sha256": configRead?.sha256 ?? ""]
                guard let data = try? JSONSerialization.data(withJSONObject: request), let encoded = String(data: data, encoding: .utf8) else { return }
                input = encoded
            }
            guard !cancelled, capturedGeneration == appState.installationGeneration else { return }
            let result = await appState.runCommand(runID: id, title: read ? "Read runtime setting" : action.title, binary: binary, arguments: arguments, standardInput: input, mutation: !read && action.mutation, category: action.mutation && !read ? "setup" : "info", origin: "Runtime features", refreshOnSuccess: !read && action.mutation)
            guard capturedGeneration == appState.installationGeneration else { output = "The installation changed; this result belongs to the previous selection. Review Activity."; return }
            output = appState.activity.entries.first(where: { $0.id == id })?.output ?? (result.succeeded ? "Completed." : "Failed. Review Activity.")
            if read && action.configuration {
                let prefix = "DCRUNTIME_CONFIG_SHA:"
                if let line = result.output.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) {
                    let hash = String(line.dropFirst(prefix.count))
                    if hash.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil {
                        configRead = (action.configKey(capturedValues), hash)
                    }
                }
                output = output.components(separatedBy: .newlines).filter { !$0.hasPrefix(prefix) }.joined(separator: "\n")
            }
            if result.succeeded && !read { reviewing = false; configRead = nil }
        }
    }
}
