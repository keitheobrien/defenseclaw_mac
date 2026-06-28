// Setup panel (spec §9.13): the 7 TUI wizards as data-driven native forms,
// each ending in a review step that shows the exact `defenseclaw setup …`
// command before applying via CLIRunner. Plus a config editor for direct
// PATCH /config/patch edits.

import SwiftUI

// MARK: - Wizard model (data-driven; one table per wizard)

struct WizardField: Identifiable {
    enum Kind {
        case text(placeholder: String)
        case secure(placeholder: String)
        case choice(options: [String])
        case bool       // click-style paired flag: --key / --no-key
        case flagOnly   // bare flag: emit --key when on, nothing when off
    }

    let key: String          // CLI flag name, e.g. "provider" → --provider=
    let label: String
    let kind: Kind
    var defaultValue: String = ""
    /// Only shown when (other field key, required value) matches — ports _SETUP_DRIVER_FLAGS.
    var visibleWhen: (key: String, equals: [String])? = nil
    var help: String = ""

    var id: String { key }
}

struct WizardDefinition: Identifiable {
    let id: String
    let title: String
    let icon: String
    let blurb: String
    /// Verb prefix, e.g. ["setup", "llm"] or ["setup"] (+ commandField) or ["agent", "discovery"].
    let baseArgs: [String]
    /// Field whose VALUE becomes the next positional argument (the subcommand),
    /// optionally renamed via commandMap — e.g. connector "claudecode" → "claude-code".
    var commandField: String? = nil
    var commandMap: [String: String] = [:]
    /// Append --yes (only where the CLI supports -y/--yes).
    var appendYes: Bool = false
    /// Append --non-interactive (setup llm / guardrail style commands, which
    /// otherwise treat flags as prompt pre-fills and still prompt — aborting
    /// without a TTY).
    var appendNonInteractive: Bool = false
    /// True for subcommands with no flags — they only run as interactive
    /// terminal wizards, so the sheet offers Copy Command instead of Apply.
    var interactiveOnly: Bool = false
    /// When set, this wizard applies via the gateway instead of the CLI:
    /// each non-empty field becomes PATCH /config/patch on
    /// "<prefix>.<field key>" — mirroring the TUI's config-editor sections.
    var configPatchPrefix: String? = nil
    /// Optional exact argv builder for setup areas whose command shape is
    /// conditional or emits follow-up commands. The Bool requests masked
    /// secret values for review display.
    var commandBuilder: (([String: String], Bool) -> [[String]])? = nil
    /// Field delivered through stdin instead of argv (currently `keys set`).
    var secretInputField: String? = nil
    let fields: [WizardField]
}

// MARK: - Setup panel

struct SetupView: View {
    @Environment(AppState.self) private var appState
    @State private var activeWizard: WizardDefinition?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Setup Areas").font(.title3.weight(.semibold))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                    ForEach(TUIWizards.all) { wizard in
                        Button {
                            activeWizard = wizard
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: wizard.icon)
                                        .font(.title3)
                                        .foregroundStyle(Cisco.blue)
                                    Text(wizard.title).font(.headline)
                                    Spacer()
                                }
                                Text(wizard.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(12)
                            .frame(height: 92)
                            .background(Cisco.surfacePanel, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().padding(.vertical, 4)

                Text("Config Editor").font(.title3.weight(.semibold))
                Text("Edit individual config.yaml values directly. Changes apply through the gateway (PATCH /config/patch).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ConfigEditorView()
            }
            .padding(16)
        }
        .sheet(item: $activeWizard) { wizard in
            WizardSheet(wizard: wizard)
                .environment(appState)
        }
    }
}

// MARK: - Wizard sheet

struct WizardSheet: View {
    let wizard: WizardDefinition
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var values: [String: String] = [:]
    @State private var revealedSecrets: Set<String> = []
    @State private var phase: Phase = .form
    @State private var output = ""
    @State private var exitCode: Int32?

    enum Phase { case form, review, running, done }

    private var visibleFields: [WizardField] {
        wizard.fields.filter { field in
            guard let condition = field.visibleWhen else { return true }
            let current = values[condition.key] ?? ""
            if condition.equals == ["*nonempty*"] { return !current.isEmpty }
            return condition.equals.contains(current)
        }
    }

    /// The exact CLI invocation, shown verbatim in review (parity requirement).
    /// Booleans render click-style (--flag / --no-flag); the commandField value
    /// becomes a positional subcommand (mapped, e.g. claudecode → claude-code).
    private func buildArguments(maskSecrets: Bool) -> [String] {
        var args = wizard.baseArgs
        if let commandField = wizard.commandField {
            let value = values[commandField] ?? ""
            if !value.isEmpty { args.append(wizard.commandMap[value] ?? value) }
        }
        for field in visibleFields where field.key != wizard.commandField {
            let value = values[field.key] ?? ""
            switch field.kind {
            case .bool:
                args.append(value == "yes" ? "--\(field.key)" : "--no-\(field.key)")
            case .flagOnly:
                if value == "yes" { args.append("--\(field.key)") }
            case .secure:
                guard !value.isEmpty else { continue }
                args.append("--\(field.key)=\(maskSecrets ? "••••••" : value)")
            default:
                guard !value.isEmpty else { continue }
                args.append("--\(field.key)=\(value)")
            }
        }
        if wizard.appendYes { args.append("--yes") }
        if wizard.appendNonInteractive { args.append("--non-interactive") }
        return args
    }

    private func buildCommands(maskSecrets: Bool) -> [[String]] {
        if let commandBuilder = wizard.commandBuilder {
            return commandBuilder(values, maskSecrets)
        }
        return [buildArguments(maskSecrets: maskSecrets)]
    }

    private var cliCommands: [[String]] { buildCommands(maskSecrets: false) }

    /// Gateway-applied wizards: one PATCH /config/patch per non-empty field.
    private var patchOperations: [(path: String, value: String, secure: Bool)] {
        guard let prefix = wizard.configPatchPrefix else { return [] }
        return visibleFields.compactMap { field in
            let value = values[field.key] ?? ""
            guard !value.isEmpty else { return nil }
            if case .secure = field.kind {
                return ("\(prefix).\(field.key)", value, true)
            }
            return ("\(prefix).\(field.key)", value, false)
        }
    }

    private var displayCommand: String {
        if wizard.configPatchPrefix != nil {
            guard !patchOperations.isEmpty else { return "(no fields set — nothing to apply)" }
            return patchOperations
                .map { "PATCH /config/patch  \($0.path) = \($0.secure ? "••••••" : $0.value)" }
                .joined(separator: "\n")
        }
        let commands = buildCommands(maskSecrets: true)
        guard !commands.isEmpty else { return "(no changes selected — nothing to apply)" }
        return commands
            .map { (["defenseclaw"] + $0).joined(separator: " ") }
            .joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: wizard.icon).foregroundStyle(Cisco.blue)
                Text("Setup: \(wizard.title)").font(.headline)
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
            }
            Text(wizard.blurb).font(.caption).foregroundStyle(.secondary)

            switch phase {
            case .form: formBody
            case .review: reviewBody
            case .running, .done: runBody
            }
        }
        .padding(18)
        .frame(width: 560, height: 480)
        .onAppear {
            for field in wizard.fields where values[field.key] == nil {
                values[field.key] = field.defaultValue
            }
            if wizard.interactiveOnly { phase = .review } // nothing to fill in
        }
    }

    private var formBody: some View {
        VStack(alignment: .leading) {
            Form {
                ForEach(visibleFields) { field in
                    fieldRow(field)
                    if !field.help.isEmpty {
                        Text(field.help).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            Spacer()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Review →") { phase = .review }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Cisco.blue)
            }
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: WizardField) -> some View {
        let binding = Binding(
            get: { values[field.key] ?? "" },
            set: { values[field.key] = $0 }
        )
        switch field.kind {
        case .text(let placeholder):
            TextField(field.label, text: binding, prompt: Text(placeholder))
        case .secure(let placeholder):
            HStack {
                if revealedSecrets.contains(field.key) {
                    TextField(field.label, text: binding, prompt: Text(placeholder))
                } else {
                    SecureField(field.label, text: binding, prompt: Text(placeholder))
                }
                Button {
                    if revealedSecrets.contains(field.key) { revealedSecrets.remove(field.key) }
                    else { revealedSecrets.insert(field.key) }
                } label: {
                    Image(systemName: revealedSecrets.contains(field.key) ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help("Toggle secret visibility")
            }
        case .choice(let options):
            Picker(field.label, selection: binding) {
                ForEach(options, id: \.self) { Text($0).tag($0) }
            }
        case .bool, .flagOnly:
            Toggle(field.label, isOn: Binding(
                get: { (values[field.key] ?? "") == "yes" },
                set: { values[field.key] = $0 ? "yes" : "no" }
            ))
        }
    }

    private var reviewBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Review").font(.subheadline.weight(.semibold))
            Text(wizard.configPatchPrefix != nil
                 ? "These values apply through the gateway (PATCH /config/patch), exactly like the TUI's config-editor section:"
                 : wizard.interactiveOnly
                 ? "This subcommand is an interactive terminal wizard (it takes no flags). Copy it and run it in your terminal:"
                 : "This exact command will run (matching the terminal TUI’s behavior):")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(displayCommand)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Cisco.surfacePanel, in: RoundedRectangle(cornerRadius: 8))
            KeyValueGrid(pairs: visibleFields.compactMap { field in
                let value = values[field.key] ?? ""
                guard !value.isEmpty else { return nil }
                if case .secure = field.kind { return (field.label, "••••••") }
                return (field.label, value)
            })
            Spacer()
            HStack {
                if !wizard.interactiveOnly {
                    Button("← Back") { phase = .form }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                if wizard.interactiveOnly {
                    Button("Copy Command") {
                        let command = buildCommands(maskSecrets: false).first ?? wizard.baseArgs
                        copyToPasteboard((["defenseclaw"] + command).joined(separator: " "))
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(Cisco.blue)
                } else {
                    Button("Apply") { apply() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .tint(Cisco.blue)
                        .disabled(wizard.configPatchPrefix != nil && !appState.gatewayReachable)
                        .help(wizard.configPatchPrefix != nil && !appState.gatewayReachable
                              ? "Gateway offline — config patches need the gateway running."
                              : "")
                }
            }
        }
    }

    private var runBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if phase == .running {
                    ProgressView().controlSize(.small)
                    Text("Applying…").font(.subheadline)
                } else if exitCode == 0 {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Cisco.green)
                    Text("Applied successfully").font(.subheadline.weight(.semibold))
                } else {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Cisco.red)
                    Text("Failed (exit \(exitCode ?? -1))").font(.subheadline.weight(.semibold))
                }
            }
            ScrollView {
                Text(output.isEmpty ? "…" : output)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Cisco.surfacePanel, in: RoundedRectangle(cornerRadius: 8))
            Spacer()
            HStack {
                Spacer()
                Button(phase == .done ? "Close" : "Dismiss") {
                    dismiss()
                    if exitCode == 0 { appState.reloadConfig() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func apply() {
        phase = .running
        output = ""
        if wizard.configPatchPrefix != nil {
            applyPatches()
            return
        }
        Task {
            let commands = cliCommands
            guard !commands.isEmpty else {
                output = "Nothing to apply."
                exitCode = 0
                phase = .done
                return
            }
            var finalCode: Int32 = 0
            for (index, arguments) in commands.enumerated() {
                if commands.count > 1 {
                    output += "$ defenseclaw \(arguments.joined(separator: " "))\n"
                }
                let secret = index == 0 ? wizard.secretInputField.flatMap { values[$0] } : nil
                let result = await appState.runCommand(
                    title: wizard.title,
                    binary: "defenseclaw",
                    arguments: arguments,
                    standardInput: secret,
                    category: "setup",
                    origin: "Setup",
                    refreshOnSuccess: true
                )
                if let entry = appState.activity.entries.first(where: { $0.id == appState.activity.selectedID }) {
                    output += entry.output
                }
                if output.isEmpty { output = result.output }
                finalCode = result.exitCode
                if !result.succeeded { break }
            }
            exitCode = finalCode
            phase = .done
        }
    }

    private func applyPatches() {
        let operations = patchOperations
        guard !operations.isEmpty else {
            output = "Nothing to apply — all fields are empty."
            exitCode = 1
            phase = .done
            return
        }
        Task {
            var failures = 0
            for op in operations {
                do {
                    let value = dcCoerceConfigValue(op.value, forPath: op.path)
                    try await appState.gateway.patchConfig(path: op.path, value: value)
                    output += "✓ \(op.path)\n"
                } catch {
                    failures += 1
                    output += "✗ \(op.path): \(error.localizedDescription)\n"
                }
            }
            exitCode = failures == 0 ? 0 : Int32(failures)
            phase = .done
            if failures == 0 { appState.reloadConfig() }
        }
    }
}

// MARK: - Config editor

struct ConfigEditorView: View {
    @Environment(AppState.self) private var appState
    @State private var path = ""
    @State private var value = ""
    @State private var status: String?
    @State private var statusOK = true
    @State private var configDump: [(String, String)] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Config path (e.g. guardrail.mode)", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                TextField("Value", text: $value)
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                Button("Apply") { applyPatch() }
                    .disabled(path.isEmpty || !appState.gatewayReachable)
                    .buttonStyle(.borderedProminent)
                    .tint(Cisco.blue)
            }
            if let status {
                Label(status, systemImage: statusOK ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(statusOK ? Cisco.green : Cisco.red)
            }
            DCCard("Current configuration (read-only)", systemImage: "doc.text") {
                if configDump.isEmpty {
                    Text("config.yaml not found or empty.").font(.caption).foregroundStyle(.secondary)
                } else {
                    KeyValueGrid(pairs: configDump)
                }
                Button("Reload") { loadDump() }
                    .controlSize(.small)
            }
        }
        .task { loadDump() }
    }

    private func applyPatch() {
        Task {
            do {
                try await appState.gateway.patchConfig(path: path, value: dcCoerceConfigValue(value, forPath: path))
                status = "Applied \(path) — gateway accepted the change."
                statusOK = true
                appState.reloadConfig()
                loadDump()
            } catch {
                status = error.localizedDescription
                statusOK = false
            }
        }
    }

    private func loadDump() {
        Task {
            let cfg = await appState.configStore.reload()
            var pairs: [(String, String)] = []
            func walk(_ node: YAMLNode, prefix: String) {
                switch node {
                case .scalar(let s):
                    let lower = prefix.lowercased()
                    let masked = lower.contains("token") || lower.contains("key") || lower.contains("secret")
                    pairs.append((prefix, masked ? "••••••" : s))
                case .mapping(let m):
                    for key in m.keys.sorted() {
                        walk(m[key]!, prefix: prefix.isEmpty ? key : "\(prefix).\(key)")
                    }
                case .sequence(let s):
                    pairs.append((prefix, "[\(s.count) items]"))
                }
            }
            walk(cfg.raw, prefix: "")
            configDump = Array(pairs.prefix(60))
        }
    }
}
// MARK: - Shared helpers

/// Coerce a string value typed into a wizard or config-editor field to the
/// YAML scalar the gateway expects — int for *_ms / *_seconds keys, bool for
/// "true"/"false". Wizard apply and direct config editor share this so the
/// two write paths never drift on type-handling.
fileprivate func dcCoerceConfigValue(_ raw: String, forPath path: String) -> Any {
    let pathLower = path.lowercased()
    if (pathLower.hasSuffix("_ms") || pathLower.hasSuffix("_seconds")),
       let intValue = Int(raw) {
        return intValue
    }
    switch raw.lowercased() {
    case "true": return true
    case "false": return false
    default: return raw
    }
}
