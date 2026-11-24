// Copyright 2026 Cisco Systems, Inc. and its affiliates
// SPDX-License-Identifier: Apache-2.0

import Foundation
import CoreFoundation

/// The public 1.0.10 CLI contract. Values are always separate arguments, never shell text.
struct RuntimeFeatureField: Identifiable {
    let key: String
    let label: String
    var choices: [String] = []
    var required = false
    var initial = ""
    var hint = ""
    var positional = false
    var repeated = false
    var id: String { key }
}

struct RuntimeFeatureAction: Identifiable {
    let id: String
    let title: String
    let help: String
    let arguments: [String]
    var binary = "defenseclaw"
    var fields: [RuntimeFeatureField] = []
    var mutation = true
    var terminal = false
    var configuration = false

    func validation(_ values: [String: String]) -> String? {
        for field in fields {
            let value = values[field.key, default: field.initial].trimmingCharacters(in: .whitespacesAndNewlines)
            if field.required && value.isEmpty { return "Enter \(field.label.lowercased())." }
            if !value.isEmpty, !field.choices.isEmpty, !field.choices.contains(value) {
                return "Choose a supported value for \(field.label.lowercased())."
            }
            if value.contains("\0") { return "Remove the null character from \(field.label.lowercased())." }
            if field.key.hasSuffix("-env"), !value.isEmpty,
               value.range(of: #"^[A-Z_][A-Z0-9_]*$"#, options: .regularExpression) == nil {
                return "Enter an environment variable name, not a credential."
            }
            if (field.key == "limit-usd" || (id == "pricing-set" && ["input", "output", "cache-read", "cache-write", "reasoning"].contains(field.key))), !value.isEmpty {
                guard let number = Double(value), number.isFinite, number >= 0 else { return "\(field.label) must be a finite, nonnegative number." }
            }
            if ["at", "to", "last"].contains(field.key), !value.isEmpty {
                guard let number = Int(value), number >= (field.key == "last" ? 0 : 1) else { return "\(field.label) must be a whole number in range." }
            }
            if field.key == "base-url", !value.isEmpty {
                guard let url = URLComponents(string: value), ["https", "http"].contains(url.scheme),
                      url.host?.isEmpty == false, url.user == nil, url.password == nil else {
                    return "Enter an HTTP(S) address without embedded credentials."
                }
            }
        }
        if id == "routing-context" {
            for (key, upper) in [("recent_user_turns", 8), ("max_bytes", 65536), ("per_turn_bytes", 65536)] {
                guard let number = Int(values[key, default: ""]), (0...upper).contains(number) else { return "\(key) must be a whole number between 0 and \(upper)." }
            }
        }
        if id == "rule-add", values["profile", default: ""].isEmpty,
           ["groups", "users", "connectors", "agents", "categories", "severity-at-least"].allSatisfy({ values[$0, default: ""].isEmpty }) {
            return "Choose at least one rule selector, or name a profile overlay."
        }
        if configuration {
            guard let data = configurationValue(values).data(using: .utf8),
                  (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil else {
                return "Enter a valid JSON value. Quote text values; use true or false for switches."
            }
            for key in ["profile", "connector"] where !values[key, default: ""].isEmpty {
                guard values[key]!.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
                    return "Use letters, numbers, underscores, or hyphens for the \(key)."
                }
            }
        }
        return nil
    }

    func command(_ values: [String: String]) -> [String] {
        var options = arguments
        var positional: [String] = []
        for field in fields {
            let value = values[field.key, default: field.initial].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { continue }
            if field.positional { positional.append(value) }
            else if field.repeated {
                options += value.split(separator: "\n").map { "--\(field.key)=\($0.trimmingCharacters(in: .whitespaces))" }
            } else { options.append("--\(field.key)=\(value)") }
        }
        return options + (positional.isEmpty ? [] : ["--"] + positional)
    }

    func configurationValue(_ values: [String: String]) -> String {
        guard id == "routing-context" else { return values["value", default: ""] }
        let object: [String: Any] = [
            "recent_user_turns": Int(values["recent_user_turns", default: ""]) ?? -1,
            "include_first_user_turn": values["include_first_user_turn"] == "true",
            "include_tool_names": values["include_tool_names"] == "true",
            "max_bytes": Int(values["max_bytes", default: ""]) ?? -1,
            "per_turn_bytes": Int(values["per_turn_bytes", default: ""]) ?? -1
        ]
        return String(data: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data(), encoding: .utf8) ?? ""
    }

    func configKey(_ values: [String: String]) -> String {
        if id == "routing-context" { return "routing.context" }
        let setting = values["setting", default: ""]
        guard setting.hasPrefix("guardrail.cascade") else { return setting }
        var prefix = "guardrail"
        if let profile = values["profile"], !profile.isEmpty { prefix += ".profiles.\(profile)" }
        if let connector = values["connector"], !connector.isEmpty { prefix += ".connectors.\(connector)" }
        return prefix + String(setting.dropFirst("guardrail".count))
    }
}

enum Runtime1010Features {
    static func supported(_ version: String?) -> Bool {
        guard let version else { return false }
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        let parts = components.compactMap { Int($0) }
        guard components.count == 3, parts.count == 3, parts.allSatisfy({ $0 >= 0 }) else { return false }
        return parts.lexicographicallyPrecedes([1, 0, 10]) == false
    }

    private static func text(_ key: String, _ label: String, required: Bool = false, positional: Bool = false, hint: String = "", repeated: Bool = false) -> RuntimeFeatureField {
        .init(key: key, label: label, required: required, hint: hint, positional: positional, repeated: repeated)
    }
    private static func choice(_ key: String, _ label: String, _ choices: [String], initial: String = "") -> RuntimeFeatureField {
        .init(key: key, label: label, choices: choices, initial: initial)
    }
    static let connectorChoices = ["", "claudecode", "codex", "openclaw", "zeptoclaw", "hermes", "cursor", "devin", "copilot", "antigravity", "opencode", "amp", "kiro"]

    static let routing: [RuntimeFeatureAction] = [
        .init(id: "routing-setup", title: "Set up routing", help: "Choose a classifier, add models, and turn routing on. Setup tests routing after applying the change. Rules runs locally; the other classifiers need their own configuration.", arguments: ["routing", "setup", "--yes"], fields: [choice("classifier", "Classifier", ["rules", "systemone", "vllm_sr"], initial: "rules"), text("model", "Models", hint: "One ALIAS=PROVIDER/MODEL per line; leave blank to keep existing models.", repeated: true), text("route", "Starting routes", hint: "One CATEGORY=ALIAS per line (coding, reasoning, summarize).", repeated: true)]),
        .init(id: "model-add", title: "Add model", help: "Give a provider model a routing alias. Store credentials in Setup → Credentials and supply only their environment variable names here.", arguments: ["routing", "models", "add"], fields: [text("name", "Alias", required: true, positional: true), text("provider", "Provider", required: true), text("model", "Model ID", required: true), text("base-url", "Base URL"), text("api-key-env", "API key environment name"), text("api", "API families", hint: "One per line: chat, messages, responses, converse, invoke.", repeated: true), text("capability", "Capabilities", hint: "One per line: tools, vision, thinking, long_context.", repeated: true)]),
        .init(id: "model-default", title: "Set default model", help: "Choose the alias used when no other model is selected.", arguments: ["routing", "models", "set-default"], fields: [text("name", "Alias", required: true, positional: true)]),
        .init(id: "model-remove", title: "Remove model", help: "Remove this model alias. Rules and budgets that still refer to it may prevent removal.", arguments: ["routing", "models", "remove"], fields: [text("name", "Alias", required: true, positional: true)]),
        .init(id: "rule-add", title: "Add rule", help: "Rules are ordered. Match users, groups, connectors, agents, categories, or severity and choose allowed model aliases. Choose at least one selector, or name a profile overlay.", arguments: ["routing", "rules", "add"], fields: [text("id", "Rule ID", required: true, positional: true), text("groups", "Groups (comma separated)"), text("users", "Users (comma separated)"), text("connectors", "Connectors (comma separated)"), text("agents", "Agent identities (comma separated)"), text("categories", "Categories (comma separated)"), choice("severity-at-least", "Minimum severity", ["", "INFO", "LOW", "MEDIUM", "HIGH", "CRITICAL"]), text("allow", "Allowed aliases (comma separated)"), text("default", "Default alias"), text("at", "Position (1 is first)"), text("profile", "Guardrail profile", hint: "Profile overlays accept allow/default only.")]),
        .init(id: "rule-move", title: "Move rule", help: "Change the order in which routing rules are evaluated.", arguments: ["routing", "rules", "move"], fields: [text("id", "Rule ID", required: true, positional: true), text("to", "New position", required: true)]),
        .init(id: "rule-remove", title: "Remove rule", help: "Remove this rule or the named profile's routing overlay.", arguments: ["routing", "rules", "remove"], fields: [text("id", "Rule ID", required: true, positional: true), text("profile", "Guardrail profile")]),
        .init(id: "budget-add", title: "Add budget", help: "Budget windows use UTC (weeks start Monday). Usage recording must be enabled. Deny is enforced only on managed devices; 1.0.10 can undercount interrupted streams.", arguments: ["routing", "budgets", "add"], fields: [text("id", "Budget ID", required: true, positional: true), choice("scope", "Scope", ["user", "group", "connector"], initial: "user"), text("subject", "Subject", required: true, hint: "User, group, connector, or * for each user/connector."), choice("period", "Period", ["day", "week", "month"], initial: "month"), text("limit-usd", "Limit (USD)", required: true), text("on-exceed", "When exceeded", required: true, hint: "warn, deny, or downgrade:alias[,alias]")]),
        .init(id: "budget-remove", title: "Remove budget", help: "Remove this spending limit. Runtime 1.0.10 may need a gateway restart after all budgets are removed to stop its sync loop.", arguments: ["routing", "budgets", "remove"], fields: [text("id", "Budget ID", required: true, positional: true)]),
        .init(id: "routing-enable", title: "Enable routing", help: "Enable model routing globally, or route only Claude Code or Codex model calls. Connector changes may rewrite the connector's provider settings.", arguments: ["routing", "enable"], fields: [choice("connector", "Connector (blank means global)", ["", "claudecode", "codex"])]),
        .init(id: "routing-disable", title: "Disable routing", help: "Stop routing globally, or restore one connector's own model settings.", arguments: ["routing", "disable"], fields: [choice("connector", "Connector (blank means global)", ["", "claudecode", "codex"])]),
        .init(id: "routing-test", title: "Test routing", help: "Simulate routing for a prompt without calling the selected model. The configured classifier may use its own service. Use nonsensitive sample text; the command is recorded in Activity.", arguments: ["routing", "test"], fields: [text("prompt", "Sample prompt", required: true, positional: true), choice("connector", "Connector", connectorChoices), text("as-profile", "Profile"), text("as-user", "User (administrator only)")], mutation: false),
        .init(id: "routing-explain", title: "Explain decision", help: "Inspect the routing decision for a recorded request.", arguments: ["routing", "explain"], fields: [text("request", "Request ID", required: true, positional: true)], mutation: false),
    ]

    static let pricing: [RuntimeFeatureAction] = [
        .init(id: "tokenomics-status", title: "Usage recording status", help: "Read whether model-call recording and local storage are enabled, their retention, and the price table version.", arguments: ["setup", "tokenomics", "--status"], mutation: false),
        .init(id: "tokenomics-enable", title: "Enable usage recording", help: "Record model-call tokens and costs locally. The runtime seeds prices when none exist; review them before relying on cost or budgets.", arguments: ["setup", "tokenomics", "--enable"]),
        .init(id: "tokenomics-disable", title: "Disable usage recording", help: "Stop new model usage records and disable the local store. Existing records and the price table remain.", arguments: ["setup", "tokenomics", "--disable"]),
        .init(id: "pricing-set", title: "Set model prices", help: "Prices are USD per million tokens. Unknown prices must remain unknown, not zero.", arguments: ["routing", "pricing", "set"], fields: [text("target", "Provider/model", required: true, positional: true), text("input", "Input", required: true), text("output", "Output", required: true), text("cache-read", "Cache read"), text("cache-write", "Cache write"), text("reasoning", "Reasoning")]),
        .init(id: "pricing-import", title: "Import prices", help: "Import a JSON or YAML price table through runtime validation.", arguments: ["routing", "pricing", "import"], fields: [text("path", "Price table path", required: true, positional: true)]),
    ]

    static let configuration = RuntimeFeatureAction(
        id: "runtime-config", title: "Advanced runtime settings", help: "Read the current value before editing. Save replaces only the selected setting through the runtime's validated writer. Use a JSON object for structured settings. Connector and profile scope apply to cascade settings only; blank means global. Managed settings remain read only.", arguments: [], fields: [
            choice("setting", "Setting", ["guardrail.cascade", "guardrail.cascade.lanes.alignment", "guardrail.secret_flow", "routing.context", "routing.admin", "routing.classifier", "routing.categories", "routing.sensitive", "routing.systemone", "routing.remote", "routing.route_only", "routing.signals", "routing.decisions", "routing.on_classifier_error", "routing.min_confidence", "routing.allow_user_override", "observability.tokenomics", "observability.pricing", "decision_model.protocol", "connectors.openclaw", "claw.home_dir", "claw.config_file", "substrate"], initial: "guardrail.cascade.lanes.alignment"),
            text("profile", "Cascade profile"), choice("connector", "Cascade connector", connectorChoices),
            text("value", "JSON value", required: true, hint: "Alignment: \"off\", \"shadow\", \"alert\", or \"block\". Decision protocol: \"system-one\" or \"gemini-decisions\". Read the selected setting first; secrets are masked and must not be saved back.")
        ], configuration: true)

    static let context = RuntimeFeatureAction(
        id: "routing-context", title: "Conversation context", help: "Let routing consider earlier user turns and tool names. It never reads tool arguments, tool results, assistant text, or file contents. Requires the rules or System One classifier. Read the current setting before replacing it.", arguments: [], fields: [
            text("recent_user_turns", "Earlier user turns (0–8)", required: true),
            choice("include_first_user_turn", "Include the original task", ["false", "true"], initial: "false"),
            choice("include_tool_names", "Include tool names", ["false", "true"], initial: "false"),
            text("max_bytes", "Total text limit (0 uses 8192 bytes)", required: true),
            text("per_turn_bytes", "Per-turn limit (0 uses 2048 bytes)", required: true)
        ], configuration: true)

    static let alignment = RuntimeFeatureAction(
        id: "alignment", title: "Alignment checks", help: "Check whether a tool call serves the user's task. Off disables this lane; shadow records it, alert reports drift, and block can stop it. Other findings are preserved. Read the current value before replacing it.", arguments: [], fields: [
            choice("setting", "Setting", ["guardrail.cascade.lanes.alignment"], initial: "guardrail.cascade.lanes.alignment"),
            text("profile", "Profile (blank means global)"), choice("connector", "Connector", connectorChoices),
            choice("value", "Mode", ["", "\"off\"", "\"shadow\"", "\"alert\"", "\"block\""])
        ], configuration: true)

    static let guardrail: [RuntimeFeatureAction] = [
        .init(id: "cascade-explain", title: "Explain guardrail cascade", help: "Show effective layers, alignment checks, policy, locks, and the source of each setting. Replay either a saved JSON input or a recent decision.", arguments: ["guardrail", "cascade", "explain"], fields: [choice("connector", "Connector", connectorChoices), text("profile", "Profile"), text("input", "Decision JSON file"), text("last", "Recent decision number")], mutation: false),
        .init(id: "openclaw-preflight", title: "Check OpenClaw hooks", help: "Inspect the OpenClaw integration before applying hook or plugin changes.", arguments: ["connector", "openclaw", "preflight"], binary: "defenseclaw-gateway", mutation: false),
        .init(id: "acp-refresh", title: "Refresh ACP agent", help: "Re-pin an enrolled ACP agent after it updates itself.", arguments: ["acp", "refresh"], fields: [text("agent", "Agent", required: true)]),
        .init(id: "cowork", title: "Set up Cowork", help: "Build the Cowork plugin ZIP, setting up Claude Code hooks if needed. Upload the resulting ZIP in Claude to finish; the runtime cannot install account plugins for you.", arguments: ["setup", "cowork", "--yes", "--no-open-claude", "--no-wait"]),
        alignment,
        configuration,
    ]

    static let substrate: [RuntimeFeatureAction] = [
        .init(id: "substrate-list", title: "List agents", help: "Read the agents visible to your signed-in Substrate account.", arguments: ["substrate", "list"], mutation: false),
        .init(id: "substrate-doctor", title: "Check cluster", help: "Check launcher and cluster connectivity.", arguments: ["substrate", "doctor"], mutation: false),
        .init(id: "substrate-usage", title: "Cluster usage", help: "Read your agents' model calls, tokens, and cost.", arguments: ["substrate", "usage"], mutation: false),
        .init(id: "substrate-approvals", title: "Approvals", help: "Read pending requests from your agents.", arguments: ["substrate", "approvals"], mutation: false),
        .init(id: "substrate-login", title: "Sign in", help: "Sign in through the runtime's interactive terminal workflow. Copy the command and run it in Terminal.", arguments: ["substrate", "login"], terminal: true),
        .init(id: "substrate-run", title: "Run Claude in Substrate", help: "Launch an agent in an existing Substrate cluster. This interactive session runs in Terminal.", arguments: ["substrate", "run", "claude"], terminal: true),
        .init(id: "substrate-connect", title: "Connect to agent", help: "Open the agent's interactive session in Terminal.", arguments: ["substrate", "connect"], fields: [text("name", "Agent name", required: true, positional: true)], terminal: true),
        .init(id: "substrate-pull", title: "Pull agent work", help: "Review and apply agent changes using the runtime's interactive terminal workflow.", arguments: ["substrate", "pull"], fields: [text("name", "Agent name", required: true, positional: true)], terminal: true),
        configuration,
    ]

    /// Invoke the runtime's own CLI in its interpreter so configuration values
    /// travel through stdin, never process arguments or Activity. Only fixed,
    /// explicitly supported paths are accepted by the native form.
    static let configScript = """
    import hashlib, json, sys
    from pathlib import Path
    from defenseclaw.config import config_path
    from click.testing import CliRunner
    from defenseclaw.main import cli
    request = json.load(sys.stdin)
    key = request['key']
    args = ['config', 'get', key, '--format', 'json'] if request['operation'] == 'read' else ['config', 'set', key, request['value'], '--json']
    before = Path(config_path()).read_bytes()
    if request['operation'] == 'write':
        args += ['--expect-sha256', request['sha256']]
    result = CliRunner().invoke(cli, args)
    code = result.exit_code
    if request['operation'] == 'read':
        if code == 1 and 'is not set' in result.output:
            code = 0
        print(result.output, end='')
        if code == 0 and before == Path(config_path()).read_bytes():
            print('DCRUNTIME_CONFIG_SHA:' + hashlib.sha256(before).hexdigest())
    else:
        print('Configuration saved through the runtime. Check routing status or restart the gateway if the change is not yet applied.' if result.exit_code == 0 else 'The runtime refused this value or the configuration changed. Read it again, then check the value type, supported options, and administrator policy. No successful save was reported.')
    sys.exit(code)
    """
}

struct RuntimeFeatureRow: Identifiable {
    let id: String
    let kind: String
    let name: String
    let detail: String
}

enum RuntimeFeatureJSON {
    static func object(_ output: String) -> [String: Any]? {
        guard let start = output.firstIndex(of: "{"),
              let data = String(output[start...]).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
    static func records(_ value: Any?) -> [[String: Any]] { (value as? [Any] ?? []).compactMap { $0 as? [String: Any] } }
    static func render(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "unknown" }
        if let value = value as? String { return value }
        if JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]), let text = String(data: data, encoding: .utf8) { return text }
        return String(describing: value)
    }
    static func routingRows(_ status: [String: Any]) -> [RuntimeFeatureRow] {
        let effective = status["effective"] as? [String: Any] ?? [:]
        var rows: [RuntimeFeatureRow] = []
        let rules = records(status["rule_list"])
        let budgets = records(effective["budgets"])
        for (kind, records) in [("Model", records(status["models"])), ("Rule", rules.isEmpty ? records(effective["rules"]) : rules), ("Budget", budgets.isEmpty ? records(status["budget_list"]) : budgets)] {
            for (index, record) in records.enumerated() {
                rows.append(.init(id: "\(kind)-\(index)", kind: kind, name: render(record["alias"] ?? record["id"]), detail: rowDescription(kind: kind, record: record)))
            }
        }
        return rows
    }
    static func rowDescription(kind: String, record: [String: Any]) -> String {
        if kind == "Model" {
            return "\(render(record["provider"]))/\(render(record["model"]))"
                + (record["default"] as? Bool == true ? " · default" : "")
                + (record["locked"] as? Bool == true ? " · locked" : "")
        }
        if kind == "Budget" {
            return "\(render(record["scope"])): \(render(record["subject"])) · \(cost(record["spent_usd"])) used / \(cost(record["limit_usd"])) per \(render(record["period"])) · \(render(record["on_exceed"]))"
                + (record["exceeded"] as? Bool == true ? " · exceeded" : "")
        }
        let match = record["match"] as? [String: Any] ?? [:]
        return match.keys.sorted().map { "\($0): \(render(match[$0]))" }.joined(separator: " · ")
            + " → \(render(record["action"] ?? record["allow"]))"
            + (record["default"] == nil ? "" : " · default \(render(record["default"]))")
    }
    static func cost(_ value: Any?) -> String {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else { return "unknown" }
        return String(format: "$%.4f", number.doubleValue)
    }
}
