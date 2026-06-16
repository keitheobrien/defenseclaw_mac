// Overview SCANNERS card — port of the TUI's scanner box (app.py ~5120).
// Six rows: external scanners probed on PATH (skill-scanner, mcp-scanner),
// built-ins that ship in the CLI (aibom, codeguard), the guardrail (state +
// mode/port/rule-pack), and required credentials (keys). All reads are
// filesystem/env only — cheap enough to run on the pulse, no subprocess.

import Foundation

struct ScannerStatus: Identifiable, Sendable, Equatable {
    enum Level: Sendable { case active, builtin, warn, missing }
    var name: String
    var detail: String
    var level: Level
    var id: String { name }
}

enum ScannerProbe {
    /// Standard install locations, mirroring the CLI's own search order.
    private static let binDirs: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
    }()

    static func binaryInstalled(_ name: String) -> Bool {
        binDirs.contains { FileManager.default.isExecutableFile(atPath: "\($0)/\(name)") }
    }

    /// Gateway-required credential names the CLI doctor checks. The legacy
    /// OPENCLAW_GATEWAY_TOKEN is the one `defenseclaw doctor` reports as
    /// "required by gateway", independent of the connector's own token_env.
    private static let requiredKeys = ["OPENCLAW_GATEWAY_TOKEN"]

    private static func dotEnvNames() -> Set<String> {
        let url = ConfigStore.dataDirectory.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var names = Set<String>()
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let name = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            // A name with an empty value doesn't count as set.
            if !String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces).isEmpty {
                names.insert(name)
            }
        }
        return names
    }

    /// Missing required gateway credentials (env or ~/.defenseclaw/.env).
    static func missingKeys() -> [String] {
        let env = ProcessInfo.processInfo.environment
        let dotenv = dotEnvNames()
        return requiredKeys.filter { name in
            let inEnv = !(env[name] ?? "").isEmpty
            return !inEnv && !dotenv.contains(name)
        }
    }

    /// Assemble all six scanner rows. `guardrailState` comes from /health
    /// (e.g. "running"); the mode/port/rule-pack detail comes from config.
    static func statuses(config: DefenseClawConfig, guardrailState: String?) -> [ScannerStatus] {
        var rows: [ScannerStatus] = []

        let skill = binaryInstalled("skill-scanner")
        rows.append(.init(name: "skill-scanner",
                          detail: skill ? "installed" : "missing",
                          level: skill ? .active : .missing))
        let mcp = binaryInstalled("mcp-scanner")
        rows.append(.init(name: "mcp-scanner",
                          detail: mcp ? "installed" : "missing",
                          level: mcp ? .active : .missing))

        rows.append(.init(name: "aibom", detail: "built-in", level: .builtin))
        rows.append(.init(name: "codeguard", detail: "built-in", level: .builtin))

        // guardrail: "<mode>, port <n>, <rulepack>" + running/state.
        let mode = config.guardrailMode ?? "observe"
        let port = config.guardrailPort.map { ", port \($0)" } ?? ""
        let guardrailDetail = "\(mode)\(port), \(config.guardrailRulePack)"
        let running = (guardrailState ?? "").lowercased() == "running"
        rows.append(.init(name: "guardrail", detail: guardrailDetail,
                          level: running ? .active : .warn))

        // keys: required gateway credentials.
        let missing = missingKeys()
        if missing.isEmpty {
            rows.append(.init(name: "keys", detail: "all required set", level: .active))
        } else {
            let preview = missing.prefix(2).joined(separator: ", ")
            let suffix = missing.count > 2 ? " +\(missing.count - 2)" : ""
            rows.append(.init(name: "keys", detail: "\(missing.count) missing: \(preview)\(suffix)",
                              level: .warn))
        }
        return rows
    }
}
