// Reads ~/.defenseclaw/config.yaml — the same source of truth the TUI uses.
// Minimal YAML subset parser (nested block mappings, scalars, simple lists),
// sufficient for the keys the app consumes. Writes never go through this
// store; they go via the gateway (/config/patch) or the defenseclaw CLI.

import Foundation

struct DefenseClawConfig: Sendable {
    var gatewayHost: String = "127.0.0.1"
    var gatewayPort: Int = 18970
    var gatewayToken: String?
    var connectorName: String?
    var connectorMode: String?
    var connectors: [String] = []
    var guardrailEnabled = false
    var guardrailMode: String?
    var registrySources: [RegistrySourceConfig] = []
    var raw: YAMLNode = .mapping([:])

    struct RegistrySourceConfig: Sendable {
        var url: String
        var kind: String
        var enabled: Bool
    }

    var baseURL: URL {
        URL(string: "http://\(gatewayHost):\(gatewayPort)")!
    }
}

/// Very small YAML representation: enough for config.yaml's block style.
indirect enum YAMLNode: Sendable {
    case scalar(String)
    case mapping([String: YAMLNode])
    case sequence([YAMLNode])

    subscript(path: String) -> YAMLNode? {
        var node: YAMLNode = self
        for key in path.split(separator: ".").map(String.init) {
            guard case .mapping(let m) = node, let next = m[key] else { return nil }
            node = next
        }
        return node
    }

    var string: String? {
        if case .scalar(let s) = self { return s.isEmpty ? nil : s }
        return nil
    }
    var int: Int? { string.flatMap(Int.init) }
    var bool: Bool? {
        guard let s = string?.lowercased() else { return nil }
        if ["true", "yes", "on"].contains(s) { return true }
        if ["false", "no", "off"].contains(s) { return false }
        return nil
    }
    var mapping: [String: YAMLNode]? {
        if case .mapping(let m) = self { return m }
        return nil
    }
    var sequence: [YAMLNode]? {
        if case .sequence(let s) = self { return s }
        return nil
    }
}

enum MiniYAML {
    /// Parses block-style YAML mappings/sequences with plain or quoted scalars.
    /// Ignores comments, documents markers, anchors, and flow collections —
    /// adequate for defenseclaw's generated config.yaml.
    static func parse(_ text: String) -> YAMLNode {
        var lines: [(indent: Int, content: String)] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty || stripped.hasPrefix("#") || stripped == "---" { continue }
            let indent = line.prefix { $0 == " " }.count
            lines.append((indent, stripped))
        }
        var index = 0
        return parseBlock(lines: lines, index: &index, indent: 0)
    }

    private static func parseBlock(lines: [(indent: Int, content: String)], index: inout Int, indent: Int) -> YAMLNode {
        var map: [String: YAMLNode] = [:]
        var seq: [YAMLNode] = []
        var isSequence: Bool?

        while index < lines.count {
            let (lineIndent, content) = lines[index]
            if lineIndent < indent { break }
            if lineIndent > indent { // shouldn't happen at well-formed entry point; skip
                index += 1
                continue
            }
            if content.hasPrefix("- ") || content == "-" {
                if isSequence == false { break }
                isSequence = true
                let inline = String(content.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                index += 1
                if inline.isEmpty {
                    seq.append(parseBlock(lines: lines, index: &index, indent: nextIndent(lines, index, greaterThan: indent)))
                } else if let colon = findColon(inline) {
                    // "- key: value" — sequence of mappings; gather subsequent deeper keys
                    var item: [String: YAMLNode] = [:]
                    let key = unquote(String(inline[..<colon]))
                    let value = String(inline[inline.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    item[key] = value.isEmpty
                        ? parseBlock(lines: lines, index: &index, indent: nextIndent(lines, index, greaterThan: indent))
                        : .scalar(unquote(value))
                    while index < lines.count, lines[index].indent > indent, !lines[index].content.hasPrefix("- ") {
                        let sub = lines[index]
                        if let c = findColon(sub.content) {
                            let k = unquote(String(sub.content[..<c]))
                            let v = String(sub.content[sub.content.index(after: c)...]).trimmingCharacters(in: .whitespaces)
                            index += 1
                            item[k] = v.isEmpty
                                ? parseBlock(lines: lines, index: &index, indent: nextIndent(lines, index, greaterThan: sub.indent))
                                : .scalar(unquote(v))
                        } else { index += 1 }
                    }
                    seq.append(.mapping(item))
                } else {
                    seq.append(.scalar(unquote(inline)))
                }
            } else if let colon = findColon(content) {
                if isSequence == true { break }
                isSequence = false
                let key = unquote(String(content[..<colon]))
                let value = String(content[content.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                index += 1
                if value.isEmpty {
                    map[key] = parseBlock(lines: lines, index: &index, indent: nextIndent(lines, index, greaterThan: indent))
                } else {
                    map[key] = .scalar(unquote(value))
                }
            } else {
                index += 1 // unrecognized line — skip
            }
        }
        if isSequence == true { return .sequence(seq) }
        return .mapping(map)
    }

    private static func nextIndent(_ lines: [(indent: Int, content: String)], _ index: Int, greaterThan indent: Int) -> Int {
        guard index < lines.count, lines[index].indent > indent else { return indent + 2 }
        return lines[index].indent
    }

    /// First colon that terminates a key (colon followed by space or EOL), outside quotes.
    private static func findColon(_ s: String) -> String.Index? {
        var inSingle = false, inDouble = false
        var i = s.startIndex
        while i < s.endIndex {
            let ch = s[i]
            if ch == "'" && !inDouble { inSingle.toggle() }
            if ch == "\"" && !inSingle { inDouble.toggle() }
            if ch == ":" && !inSingle && !inDouble {
                let next = s.index(after: i)
                if next == s.endIndex || s[next] == " " { return i }
            }
            i = s.index(after: i)
        }
        return nil
    }

    private static func unquote(_ s: String) -> String {
        var t = s
        if let hash = t.range(of: " #") { t = String(t[..<hash.lowerBound]) } // trailing comment
        t = t.trimmingCharacters(in: .whitespaces)
        if t.count >= 2, (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
        }
        return t
    }
}

actor ConfigStore {
    static let dataDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".defenseclaw")
    static let configURL = dataDirectory.appendingPathComponent("config.yaml")
    static let auditDBURL = dataDirectory.appendingPathComponent("audit.db")
    static let gatewayJSONLURL = dataDirectory.appendingPathComponent("gateway.jsonl")

    private(set) var config = DefenseClawConfig()

    var installPresent: Bool {
        FileManager.default.fileExists(atPath: Self.configURL.path)
    }

    /// KEY=VALUE pairs from ~/.defenseclaw/.env — written by the Go gateway on
    /// first boot (firstboot.go::EnsureGatewayToken). The Python CLI loads this
    /// into os.environ before resolving the token; a GUI app inherits no shell
    /// environment, so we read the file directly. Process env still wins.
    private func loadDotEnv() -> [String: String] {
        let url = Self.dataDirectory.appendingPathComponent(".env")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var out: [String: String] = [:]
        for rawLine in text.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            out[key] = value
        }
        return out
    }

    /// Upstream precedence ladder (config.py::resolved_token):
    /// 1. env var named by gateway.token_env  2. DEFENSECLAW_GATEWAY_TOKEN
    /// 3. OPENCLAW_GATEWAY_TOKEN              4. literal gateway.token
    private func resolveToken(root: YAMLNode, dotenv: [String: String]) -> String? {
        func env(_ key: String) -> String? {
            if let v = ProcessInfo.processInfo.environment[key], !v.isEmpty { return v }
            if let v = dotenv[key], !v.isEmpty { return v }
            return nil
        }
        if let name = root["gateway.token_env"]?.string, let v = env(name) { return v }
        if let v = env("DEFENSECLAW_GATEWAY_TOKEN") { return v }
        if let v = env("OPENCLAW_GATEWAY_TOKEN") { return v }
        return root["gateway.token"]?.string
    }

    @discardableResult
    func reload() -> DefenseClawConfig {
        guard let text = try? String(contentsOf: Self.configURL, encoding: .utf8) else {
            config = DefenseClawConfig()
            return config
        }
        let root = MiniYAML.parse(text)
        var c = DefenseClawConfig()
        c.raw = root
        c.gatewayHost = root["gateway.host"]?.string ?? "127.0.0.1"
        c.gatewayPort = root["gateway.api_port"]?.int ?? root["gateway.port"]?.int ?? 18970
        c.gatewayToken = resolveToken(root: root, dotenv: loadDotEnv())
        c.connectorName = root["connector.name"]?.string ?? root["guardrail.connector"]?.string ?? root["connector"]?.string
        c.connectorMode = root["connector.mode"]?.string ?? root["claw.mode"]?.string ?? root["mode"]?.string
        c.guardrailEnabled = root["guardrail.enabled"]?.bool ?? false
        c.guardrailMode = root["guardrail.mode"]?.string
        // Multi-connector roster (guardrail.connectors: {codex: {...}, ...}).
        if let roster = root["guardrail.connectors"]?.mapping {
            c.connectors = roster.keys.sorted()
        }
        if let sources = root["registries.sources"]?.sequence ?? root["registries"]?.sequence {
            c.registrySources = sources.compactMap { node in
                guard let m = node.mapping else {
                    if let url = node.string {
                        return .init(url: url, kind: "http", enabled: true)
                    }
                    return nil
                }
                guard let url = m["url"]?.string ?? m["source"]?.string else { return nil }
                return .init(
                    url: url,
                    kind: m["kind"]?.string ?? m["type"]?.string ?? "http",
                    enabled: m["enabled"]?.bool ?? true
                )
            }
        }
        // Loopback only — refuse non-local gateway hosts (spec §11).
        if !["127.0.0.1", "localhost", "::1"].contains(c.gatewayHost) {
            c.gatewayHost = "127.0.0.1"
        }
        config = c
        return c
    }
}
