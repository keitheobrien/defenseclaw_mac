// DefenseClaw for macOS — data models mirroring the TUI's service-layer dataclasses.
// Apache-2.0; companion to cisco-ai-defense/defenseclaw.

import Foundation

// MARK: - Severity / state

enum Severity: String, CaseIterable, Codable, Comparable, Identifiable {
    case critical = "CRITICAL"
    case high = "HIGH"
    case medium = "MEDIUM"
    case low = "LOW"
    case info = "INFO"

    var id: String { rawValue }

    private var rank: Int {
        switch self {
        case .critical: 4
        case .high: 3
        case .medium: 2
        case .low: 1
        case .info: 0
        }
    }

    static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rank < rhs.rank }

    /// Mirrors the TUI's _severity_bucket: WARNING folds into MEDIUM;
    /// anything unrecognized (ERROR, ACK, …) is INFO and never alert-counted.
    static func parse(_ raw: String?) -> Severity {
        guard let raw else { return .info }
        let upper = raw.uppercased()
        if upper == "WARNING" { return .medium }
        return Severity(rawValue: upper) ?? .info
    }
}

/// Runtime state buckets matching the TUI's STATE_STYLES groups.
enum EntityState: String {
    case active, blocked, warn, quarantined, disabled

    static func classify(_ raw: String) -> EntityState {
        switch raw.lowercased() {
        case "active", "running", "enabled", "clean", "pass", "ok", "healthy", "allow", "allowed", "connected":
            return .active
        case "blocked", "error", "rejected", "stopped", "fail", "failed", "block", "offline":
            return .blocked
        case "warn", "warning", "reconnecting", "starting", "stale", "degraded", "observe":
            return .warn
        case "quarantined":
            return .quarantined
        default:
            return .disabled
        }
    }
}

// MARK: - Gateway /health

struct HealthSnapshot: Sendable {
    var state: String = "offline"
    var uptimeMs: Int = 0
    var lastError: String?
    var subsystems: [Subsystem] = []
    var connectors: [ConnectorHealth] = []
    var version: String?
    var fetchedAt: Date = .distantPast

    struct Subsystem: Identifiable, Sendable {
        var name: String
        var state: String
        var detail: String?
        /// Stringified scalar values from the /health subsystem's nested
        /// "details" object (e.g. skill_dirs, active_signals, addr, summary).
        var details: [String: String] = [:]
        var id: String { name }
    }

    /// Look up a parsed subsystem by its /health key.
    func subsystem(_ key: String) -> Subsystem? {
        subsystems.first { $0.name == key }
    }
}

/// One row of the Overview SERVICES card — mirrors the TUI's ServiceCard
/// (gateway, agent, watchdog, guardrail, api, sinks, telemetry, ai_discovery,
/// sandbox), each with a runtime state and a one-line detail.
struct ServiceStatus: Identifiable, Sendable {
    var key: String
    var name: String
    var state: String
    var detail: String
    var id: String { key }
}

struct ConnectorHealth: Identifiable, Sendable {
    var name: String
    var mode: String          // from config guardrail.connectors.<name>.mode
    var rulePack: String      // from config …rule_pack_dir (basename)
    var lastActivity: Date?   // derived from audit events (connector= kv)
    var calls: Int            // /health requests, audit fallback for hook connectors
    var blocks: Int           // tool_blocks + subprocess_blocks, audit fallback
    var alerts: Int           // severity-bearing audit rows for this connector
    var inspections: Int = 0  // /health tool_inspections
    var errors: Int = 0
    var state: String
    var id: String { name }
}

struct OverviewEnforcementMetrics: Sendable, Equatable {
    var hookCalls: Int = 0
    var blocks: Int = 0
    var findings: Int = 0
}

/// One label/value row of the Overview CONFIGURATION box (parity with the
/// TUI's global configuration lines).
struct ConfigurationRow: Identifiable, Sendable {
    var label: String
    var value: String
    var id: String { label }
}

extension String {
    /// self when non-empty, otherwise nil — for `?? fallback` chains.
    var nonEmpty: String? { isEmpty ? nil : self }
}

// MARK: - Catalog items (skills / MCPs / plugins / tools)

struct SkillItem: Identifiable, Sendable {
    var key: String
    var name: String
    var version: String
    var source: String
    var enabled: Bool                 // gateway rows: enabled; filesystem rows: eligible/ready
    var skillDescription: String = ""
    var connector: String = ""
    var fromFilesystem: Bool = false  // listed by SkillScanner, read-only
    var id: String { key }
}

struct MCPItem: Identifiable, Sendable {
    var name: String
    var transport: String
    var endpoint: String
    var version: String
    var enabled: Bool
    var source: String = ""           // registry file the entry came from (filesystem rows)
    var connector: String = ""
    var fromFilesystem: Bool = false  // discovered by MCPScanner, read-only
    var id: String { fromFilesystem ? "\(connector)/\(name)" : name }
}

struct PluginItem: Identifiable, Sendable {
    var name: String
    var version: String
    var category: String              // gateway rows: kind; filesystem rows: manifest file or "no manifest"
    var enabled: Bool
    var source: String = ""           // plugin dir the entry came from (filesystem rows)
    var connector: String = ""
    var fromFilesystem: Bool = false  // discovered by PluginScanner, read-only
    var hasManifest: Bool = true
    var id: String { fromFilesystem ? "\(connector)/\(name)" : name }
}

enum ToolState: String, CaseIterable, Identifiable {
    case allow, observe, block
    var id: String { rawValue }
}

struct ToolItem: Identifiable, Sendable {
    var name: String
    var summary: String
    var signature: String
    var state: ToolState
    var usageCount: Int
    var id: String { name }
}

// MARK: - Audit / alerts

struct AuditEvent: Identifiable, Sendable, Hashable {
    var id: String
    var timestamp: Date
    var action: String
    var eventType: String
    var connector: String
    var target: String
    var actor: String
    var details: String
    var structuredJSON: String
    var severity: Severity
    var runID: String

    var isBlockClass: Bool {
        let a = action.lowercased()
        return a.contains("block") || a.contains("reject") || a.contains("enforce") || a.contains("quarantine")
    }
}

struct ScanFindingEvent: Identifiable, Sendable, Hashable {
    var id: String
    var timestamp: Date
    var scanner: String
    var target: String
    var title: String
    var detail: String
    var location: String
    var remediation: String
    var severity: Severity
    var runID: String
    var connector: String = ""
}

struct EgressEvent: Identifiable, Sendable, Hashable {
    var id: String
    var timestamp: Date
    var target: String
    var decision: String
    var reason: String
    var looksLikeLLM: Bool
    var branch: String
    var severity: Severity
    var connector: String = ""
}

/// A scan summary block grouped by scan_id from gateway.jsonl — the unit the
/// TUI's Alerts panel counts (one row per scan; nested findings expand).
struct ScanBlockEvent: Identifiable, Sendable, Hashable {
    var scanID: String
    var timestamp: Date
    var scanner: String
    var target: String
    var severity: Severity   // scan.severity_max
    var verdict: String
    var findingCount: Int
    var findingTitles: [String]
    var connector: String = ""
    var id: String { "scan-\(scanID)" }
}

/// Unified alert row (audit ∪ scan blocks ∪ findings ∪ egress) — parity with AlertRowKind.
enum AlertRow: Identifiable, Hashable {
    case audit(AuditEvent)
    case scan(ScanBlockEvent)
    case finding(ScanFindingEvent)
    case egress(EgressEvent)

    var id: String {
        switch self {
        case .audit(let e): "audit-\(e.id)"
        case .scan(let e): e.id
        case .finding(let e): "finding-\(e.id)"
        case .egress(let e): "egress-\(e.id)"
        }
    }
    var kind: String {
        switch self {
        case .audit: "audit"
        case .scan: "scan"
        case .finding: "scan finding"
        case .egress: "egress"
        }
    }
    /// Attributed connector for the connector filter ("" = unattributed).
    var connectorName: String {
        switch self {
        case .audit(let e): e.connector
        case .scan(let e): e.connector
        case .finding(let e): e.connector
        case .egress(let e): e.connector
        }
    }
    var timestamp: Date {
        switch self {
        case .audit(let e): e.timestamp
        case .scan(let e): e.timestamp
        case .finding(let e): e.timestamp
        case .egress(let e): e.timestamp
        }
    }
    var severity: Severity {
        switch self {
        case .audit(let e): e.severity
        case .scan(let e): e.severity
        case .finding(let e): e.severity
        case .egress(let e): e.severity
        }
    }
    var action: String {
        switch self {
        case .audit(let e): e.action
        case .scan(let e): e.verdict.isEmpty ? "scan" : e.verdict
        case .finding: "finding"
        case .egress(let e): e.decision
        }
    }
    var target: String {
        switch self {
        case .audit(let e): e.target
        case .scan(let e): e.target
        case .finding(let e): e.target
        case .egress(let e): e.target
        }
    }
    var details: String {
        switch self {
        case .audit(let e): e.details
        case .scan(let e):
            ([e.scanner, "\(e.findingCount) finding(s)"] + e.findingTitles.prefix(2))
                .filter { !$0.isEmpty }.joined(separator: " · ")
        case .finding(let e): [e.title, e.detail].filter { !$0.isEmpty }.joined(separator: " — ")
        case .egress(let e): e.reason
        }
    }
    var runID: String {
        switch self {
        case .audit(let e): e.runID
        case .scan: ""
        case .finding(let e): e.runID
        case .egress: ""
        }
    }
}

// MARK: - Activity (config mutations)

struct ActivityMutation: Identifiable, Sendable, Hashable {
    var id: String
    var timestamp: Date
    var actor: String
    var action: String
    var targetType: String
    var targetID: String
    var reason: String
    var versionFrom: String
    var versionTo: String
    var beforeJSON: String
    var afterJSON: String
    var connector: String = ""
}

// MARK: - Logs

enum LogStream: String, CaseIterable, Identifiable {
    case gateway, verdicts, otel, watchdog
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct LogRow: Identifiable, Sendable {
    var id: String
    var timestamp: Date
    var stream: LogStream
    var severity: Severity
    var action: String
    var eventType: String
    var message: String
    var rawJSON: String
    var connector: String = ""
}

/// Filter presets ported from the TUI's FILTER_PRESETS.
enum LogPreset: String, CaseIterable, Identifiable {
    case all, noNoise = "no-noise", important, errors, warningsPlus = "warnings+",
         scan, drift, guardrail, hooks
    var id: String { rawValue }

    private static let noisePatterns = [
        "event tick seq=", "event health seq=", "payload_len=20",
        "mallocstacklogging", "event sessions.changed", "content-length=0",
    ]
    private static let importantKeywords = [
        "error", "fatal", "panic", "warn", "block", "allow", "reject", "quarantine",
        "scan", "drift", "verdict", "guardrail", "connected", "disconnected",
        "started", "stopped",
    ]

    func matches(_ row: LogRow) -> Bool {
        let msg = row.message.lowercased()
        switch self {
        case .all: return true
        case .noNoise: return !Self.noisePatterns.contains { msg.contains($0) }
        case .important: return Self.importantKeywords.contains { msg.contains($0) }
        case .errors: return row.severity >= .high
        case .warningsPlus: return row.severity >= .medium
        case .scan: return row.eventType == "scan" || msg.contains("scan")
        case .drift: return msg.contains("drift")
        case .guardrail: return msg.contains("guardrail") || msg.contains("verdict") || msg.contains("judge")
        case .hooks: return row.eventType == "hook" || msg.contains("hook")
        }
    }
}

// MARK: - AI discovery

struct AIUsageSnapshot: Sendable {
    var totalDetected: Int = 0
    var activeSignals: Int = 0
    var filesScanned: Int = 0
    var averageConfidence: Double = 0
    var lastScan: Date?
    var components: [AIComponent] = []
    var signals: [AISignal] = []

    /// Grouped one-row-per-product view, exactly as the TUI presents it.
    var rows: [AIDiscoveryRow] { AIDiscoveryGrouping.rows(from: signals) }
}

struct AIComponent: Identifiable, Sendable, Hashable {
    var ecosystem: String
    var name: String
    var version: String
    var confidence: Double // 0...1
    var state: String      // detected / uncertain / trusted
    var lastSeen: Date?
    var locations: [String]
    var id: String { "\(ecosystem)/\(name)@\(version)" }
}

struct ConfidencePoint: Identifiable, Sendable {
    var timestamp: Date
    var confidence: Double
    var id: Date { timestamp }
}

/// One raw detection signal from /api/v1/ai-usage (ai_discovery_state.AIUsageSignal).
struct AISignal: Sendable, Hashable {
    var state: String
    var product: String
    var vendor: String
    var category: String
    var detector: String
    var version: String
    var ecosystem: String       // component.ecosystem when present
    var componentName: String   // component.name when present
    var source: String
    var confidence: Double
    var identityScore: Double
    var identityBand: String
    var presenceScore: Double
    var presenceBand: String
    var firstSeen: Date?
    var lastSeen: Date?
    var lastActive: Date?
}

/// Grouped product row — exact port of the TUI's AIDiscoveryRow (_rebuild()).
struct AIDiscoveryRow: Identifiable, Sendable, Hashable {
    var state: String
    var product: String
    var vendor: String
    var ecosystem: String
    var component: String
    var version: String
    var categories: [String]
    var detectors: [String]
    var count: Int
    var identityScore: Double
    var identityBand: String
    var presenceScore: Double
    var presenceBand: String
    var lastActive: Date?
    var signals: [AISignal]

    var id: String { "\(state)|\(product)|\(vendor)|\(ecosystem)|\(component)|\(version)" }

    var maxConfidence: Double { signals.map(\.confidence).max() ?? 0 }
}

enum AIDiscoveryGrouping {
    /// TUI state_weight(): new < changed < active < seen < gone < other.
    static func stateWeight(_ state: String) -> Int {
        switch state.trimmingCharacters(in: .whitespaces).lowercased() {
        case "new": 0
        case "changed": 1
        case "active": 2
        case "seen": 3
        case "gone": 4
        default: 9
        }
    }

    /// TUI format_csv_truncated(items, 2) → "a, b (+3)".
    static func csvTruncated(_ items: [String], limit: Int = 2) -> String {
        guard !items.isEmpty else { return "" }
        guard limit > 0, limit < items.count else { return items.joined(separator: ", ") }
        return items.prefix(limit).joined(separator: ", ") + " (+\(items.count - limit))"
    }

    /// TUI format_confidence(): "band (NN%)".
    static func formatConfidence(score: Double, band: String) -> String {
        let band = band.trimmingCharacters(in: .whitespaces)
        if band.isEmpty && score == 0 { return "" }
        let pct = Int(score * 100 + 0.5)
        return band.isEmpty ? "\(pct)%" : "\(band) (\(pct)%)"
    }

    /// Port of AIDiscoveryPanelModel._rebuild(): group by
    /// (state, product, vendor, ecosystem, component, version); aggregate
    /// unique categories/detectors in first-seen order; sort by state
    /// weight, then count desc, then product.
    static func rows(from signals: [AISignal]) -> [AIDiscoveryRow] {
        var groups: [String: AIDiscoveryRow] = [:]
        var order: [String] = []
        for signal in signals {
            let key = [signal.state, signal.product, signal.vendor,
                       signal.ecosystem.lowercased(), signal.componentName.lowercased(),
                       signal.version].joined(separator: "|")
            var row = groups[key] ?? AIDiscoveryRow(
                state: signal.state, product: signal.product, vendor: signal.vendor,
                ecosystem: signal.ecosystem, component: signal.componentName,
                version: signal.version, categories: [], detectors: [], count: 0,
                identityScore: 0, identityBand: "", presenceScore: 0, presenceBand: "",
                lastActive: nil, signals: []
            )
            if groups[key] == nil { order.append(key) }
            row.count += 1
            row.signals.append(signal)
            if !signal.category.isEmpty, !row.categories.contains(signal.category) {
                row.categories.append(signal.category)
            }
            if !signal.detector.isEmpty, !row.detectors.contains(signal.detector) {
                row.detectors.append(signal.detector)
            }
            if row.identityBand.isEmpty, !signal.identityBand.isEmpty {
                row.identityBand = signal.identityBand
                row.identityScore = signal.identityScore
            }
            if row.presenceBand.isEmpty, !signal.presenceBand.isEmpty {
                row.presenceBand = signal.presenceBand
                row.presenceScore = signal.presenceScore
            }
            if let active = signal.lastActive, row.lastActive.map({ active > $0 }) ?? true {
                row.lastActive = active
            }
            groups[key] = row
        }
        return order.compactMap { groups[$0] }.sorted {
            (stateWeight($0.state), -$0.count, $0.product) < (stateWeight($1.state), -$1.count, $1.product)
        }
    }
}

// MARK: - Inventory

enum InventoryCategory: String, CaseIterable, Identifiable {
    case agents = "Agents", mcps = "MCPs", plugins = "Plugins",
         skills = "Skills", memories = "Memories", providers = "Model Providers"
    var id: String { rawValue }
}

struct InventoryItem: Identifiable, Sendable {
    var category: InventoryCategory
    var name: String
    var version: String
    var path: String
    var detail: String
    var connector: String = ""
    var verdict: String = ""   // aibom policy_verdict (rejected/approved/unscanned/…)
    var id: String { "\(category.rawValue)/\(connector)/\(name)/\(path)" }
}

// MARK: - Registries

struct RegistrySource: Identifiable, Sendable {
    var url: String
    var kind: String
    var enabled: Bool
    var lastSync: Date?
    var modelCount: Int
    var error: String?
    var id: String { url }
}

struct RegistryModel: Identifiable, Sendable {
    var name: String
    var provider: String
    var type: String
    var capabilities: [String]
    var id: String { "\(provider)/\(name)" }
}

// MARK: - Doctor

struct DoctorCheck: Identifiable, Sendable {
    enum Result: String { case pass, warn, fail }
    var name: String
    var result: Result
    var detail: String
    var id: String { name }
}

// MARK: - Gateway errors

enum GatewayError: LocalizedError {
    case offline
    case unauthorized
    case degraded(status: Int, body: String)
    case timeout
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .offline: "Gateway unreachable — is the DefenseClaw gateway running?"
        case .unauthorized: "Gateway token rejected. The token in config.yaml may have been rotated."
        case .degraded(let status, _):
            status == 502
                ? "The gateway could not reach the connector agent (HTTP 502). Skill and tool catalogs need a running OpenClaw agent."
                : "Gateway error (HTTP \(status))."
        case .timeout: "Gateway request timed out."
        case .badResponse(let why): "Unexpected gateway response: \(why)"
        }
    }
}

// MARK: - Shared helpers

enum ConnectorAttribution {
    /// Extract the `connector=<name>` value from an audit event's kv details
    /// (matches the TUI's parse_kv_details(...).get("connector")).
    static func fromDetails(_ details: String) -> String {
        guard let range = details.range(of: "connector=") else { return "" }
        return String(details[range.upperBound...].prefix { !$0.isWhitespace && $0 != "," })
    }

    /// Hook scan targets are "<connector>:<event>" (e.g. "claudecode:PostToolUse"),
    /// so the connector is the prefix before the first colon. Filesystem-path
    /// targets ("/Users/…") and URLs are connector-agnostic and return "".
    static func fromTarget(_ target: String) -> String {
        guard !target.contains("/"), let colon = target.firstIndex(of: ":") else { return "" }
        let prefix = String(target[..<colon])
        // A bare connector token: letters/digits/_/- only (rules out schemes
        // and hosts, which carry dots or aren't followed by an event name).
        guard !prefix.isEmpty,
              prefix.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" })
        else { return "" }
        return prefix
    }
}

enum DCDates {
    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parse(_ raw: Any?) -> Date? {
        if let s = raw as? String {
            return iso.date(from: s) ?? isoNoFrac.date(from: s)
        }
        if let n = raw as? Double {
            // Heuristic: epoch seconds vs milliseconds.
            return Date(timeIntervalSince1970: n > 1e12 ? n / 1000 : n)
        }
        if let n = raw as? Int {
            return parse(Double(n))
        }
        return nil
    }

    static func relative(_ date: Date?) -> String {
        guard let date else { return "never" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

extension Date {
    /// TUI STALENESS_WINDOW = 15 minutes.
    var isStale: Bool { Date().timeIntervalSince(self) > 15 * 60 }
}
