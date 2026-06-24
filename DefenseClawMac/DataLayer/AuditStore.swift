// Read-only access to ~/.defenseclaw/audit.db via the SDK's SQLite3 module.
// The gateway owns all writes; this store never opens the DB writable.
// Schema-tolerant: missing tables/columns degrade features, never crash.

import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

actor AuditStore {
    private var db: OpaquePointer?
    private let path: String

    init(url: URL = ConfigStore.auditDBURL) {
        self.path = url.path
    }

    var isAvailable: Bool {
        ensureOpen()
        return db != nil
    }

    private func ensureOpen() {
        guard db == nil else { return }
        guard FileManager.default.fileExists(atPath: path) else { return }
        var handle: OpaquePointer?
        // Read-only; gateway writes via WAL so allow shared access.
        if sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK {
            db = handle
            sqlite3_busy_timeout(db, 500)
        } else {
            sqlite3_close(handle)
        }
    }

    private func tableExists(_ name: String) -> Bool {
        ensureOpen()
        guard db != nil else { return false }
        let rows = query("SELECT name FROM sqlite_master WHERE type='table' AND name=?", binds: [name])
        return !rows.isEmpty
    }

    /// Runs a query, returning rows as [column: value] dictionaries.
    private func query(_ sql: String, binds: [Any] = []) -> [[String: Any]] {
        ensureOpen()
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for (i, bind) in binds.enumerated() {
            let idx = Int32(i + 1)
            switch bind {
            case let v as String: sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case let v as Int: sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Double: sqlite3_bind_double(stmt, idx, v)
            default: sqlite3_bind_null(stmt, idx)
            }
        }

        var rows: [[String: Any]] = []
        var attempts = 0
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_ROW {
                var row: [String: Any] = [:]
                for col in 0..<sqlite3_column_count(stmt) {
                    let name = String(cString: sqlite3_column_name(stmt, col))
                    switch sqlite3_column_type(stmt, col) {
                    case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(stmt, col))
                    case SQLITE_FLOAT: row[name] = sqlite3_column_double(stmt, col)
                    case SQLITE_TEXT:
                        if let text = sqlite3_column_text(stmt, col) { row[name] = String(cString: text) }
                    default: break
                    }
                }
                rows.append(row)
            } else if rc == SQLITE_BUSY && attempts < 5 {
                attempts += 1
                usleep(50_000)
                continue
            } else {
                break
            }
        }
        return rows
    }

    private func decodeAuditEvent(_ r: [String: Any]) -> AuditEvent {
        let details = (r["details"] as? String) ?? ""
        // Connector attribution comes from the `connector=` kv in details
        // (the TUI's parse_kv_details), not the actor (which is the hook name).
        let connector = ConnectorAttribution.fromDetails(details)
        return AuditEvent(
            id: (r["id"] as? String) ?? String(describing: r["id"] ?? UUID().uuidString),
            timestamp: DCDates.parse(r["timestamp"]) ?? Date(timeIntervalSince1970: 0),
            action: (r["action"] as? String) ?? "",
            eventType: (r["event_type"] as? String) ?? (r["type"] as? String) ?? "audit",
            connector: connector.isEmpty ? ((r["connector"] as? String) ?? "") : connector,
            target: (r["target"] as? String) ?? "",
            actor: (r["actor"] as? String) ?? "",
            details: details,
            structuredJSON: (r["structured_json"] as? String) ?? "",
            severity: Severity.parse(r["severity"] as? String),
            runID: (r["run_id"] as? String) ?? ""
        )
    }

    // MARK: - Queries used by panels

    func recentEvents(limit: Int, offset: Int = 0, search: String? = nil,
                      severities: [Severity]? = nil, actionLike: [String]? = nil) -> [AuditEvent] {
        guard tableExists("audit_events") else { return [] }
        var sql = "SELECT * FROM audit_events"
        var conds: [String] = []
        var binds: [Any] = []
        if let search, !search.isEmpty {
            conds.append("(action LIKE ? OR target LIKE ? OR details LIKE ?)")
            let like = "%\(search)%"
            binds.append(contentsOf: [like, like, like])
        }
        if let severities, !severities.isEmpty {
            conds.append("UPPER(severity) IN (\(severities.map { _ in "?" }.joined(separator: ",")))")
            binds.append(contentsOf: severities.map(\.rawValue))
        }
        if let actionLike, !actionLike.isEmpty {
            conds.append("(" + actionLike.map { _ in "action LIKE ?" }.joined(separator: " OR ") + ")")
            binds.append(contentsOf: actionLike.map { "%\($0)%" })
        }
        if !conds.isEmpty { sql += " WHERE " + conds.joined(separator: " AND ") }
        sql += " ORDER BY timestamp DESC LIMIT ? OFFSET ?"
        binds.append(contentsOf: [limit, offset])
        return query(sql, binds: binds).map(decodeAuditEvent)
    }

    func blockClassEvents(limit: Int) -> [AuditEvent] {
        recentEvents(limit: limit, actionLike: ["block", "reject", "quarantine", "enforce"])
    }

    /// The TUI's alert queue: db.py::list_alerts(500) loads the last 500
    /// non-ACK rows of ANY listed severity, and the panel then counts only
    /// the CRITICAL/HIGH/MEDIUM/LOW buckets in memory. Older severity-bearing
    /// rows that scrolled out of the 500-row window do NOT count — replicate
    /// that exactly: window first, filter second.
    func alertQueueEvents(limit: Int = 500) -> [AuditEvent] {
        guard tableExists("audit_events") else { return [] }
        let rows = query("""
            SELECT * FROM audit_events
            WHERE UPPER(severity) IN ('CRITICAL','HIGH','MEDIUM','LOW','WARNING','ERROR','INFO')
              AND action NOT LIKE 'dismiss%'
            ORDER BY timestamp DESC LIMIT ?
            """, binds: [limit])
        return rows.map(decodeAuditEvent)
            .filter { $0.severity != .info } // bucket filter: C/H/M/L only (WARNING→MEDIUM)
    }

    /// Overview tile sources (app.py::_hook_event_timestamps & friends).
    /// The TUI counts within its loaded windows: hook calls and blocks among
    /// the most recent 500 audit events (list_events(500)); findings among
    /// the severity-bearing alert queue (list_alerts(500)).
    func overviewTileCounts() -> (hookCalls: Int, blocks: Int, findings: Int) {
        guard tableExists("audit_events") else { return (0, 0, 0) }
        func countInWindow(_ where_: String) -> Int {
            let sql = """
                SELECT COUNT(*) AS n FROM (
                    SELECT action, details, severity FROM audit_events
                    ORDER BY timestamp DESC LIMIT 500
                ) WHERE \(where_)
                """
            return (query(sql).first?["n"] as? Int) ?? 0
        }
        let hookCalls = countInWindow("action = 'connector-hook'")
        let blocks = countInWindow("""
            LOWER(action) IN ('block','guardrail-block','deny','quarantine')
            OR details LIKE '%action=block%' OR details LIKE '%action=deny%'
            """)
        let findings = alertQueueEvents(limit: 500).count
        return (hookCalls, blocks, findings)
    }

    /// db.py::get_counts — Overview ENFORCEMENT summary.
    func enforcementSummary() -> (blockedSkills: Int, allowedSkills: Int, blockedMCPs: Int, allowedMCPs: Int, totalScans: Int, activeAlerts: Int) {
        func count(_ sql: String) -> Int {
            (query(sql).first?["n"] as? Int) ?? 0
        }
        let qSkill = "SELECT COUNT(*) AS n FROM actions WHERE target_type='skill' AND json_extract(actions_json,'$.install')="
        let qMCP = "SELECT COUNT(*) AS n FROM actions WHERE target_type='mcp' AND json_extract(actions_json,'$.install')="
        let hasActions = tableExists("actions")
        let hasScans = tableExists("scan_results")
        let hasAudit = tableExists("audit_events")
        return (
            blockedSkills: hasActions ? count(qSkill + "'block'") : 0,
            allowedSkills: hasActions ? count(qSkill + "'allow'") : 0,
            blockedMCPs: hasActions ? count(qMCP + "'block'") : 0,
            allowedMCPs: hasActions ? count(qMCP + "'allow'") : 0,
            totalScans: hasScans ? count("SELECT COUNT(*) AS n FROM scan_results") : 0,
            activeAlerts: hasAudit ? count("SELECT COUNT(*) AS n FROM audit_events WHERE UPPER(severity) IN ('CRITICAL','HIGH','MEDIUM','LOW')") : 0
        )
    }

    /// 24h enforcement counts for the Overview bars: (allowed, blocked, scanned).
    func enforcementCounts24h() -> (allowed: Int, blocked: Int, scanned: Int) {
        guard tableExists("audit_events") else { return (0, 0, 0) }
        let since = DCDates.iso.string(from: Date().addingTimeInterval(-24 * 3600))
        func count(_ patterns: [String]) -> Int {
            let cond = patterns.map { _ in "action LIKE ?" }.joined(separator: " OR ")
            let rows = query("SELECT COUNT(*) AS n FROM audit_events WHERE timestamp >= ? AND (\(cond))",
                             binds: [since] + patterns.map { "%\($0)%" })
            return (rows.first?["n"] as? Int) ?? 0
        }
        return (count(["allow"]), count(["block", "reject"]), count(["scan"]))
    }

    /// Hourly allowed/blocked histogram for the last 24h (Overview enhancement).
    func hourlyEnforcement24h() -> [(hour: Date, action: String, count: Int)] {
        guard tableExists("audit_events") else { return [] }
        let since = DCDates.iso.string(from: Date().addingTimeInterval(-24 * 3600))
        let rows = query("""
            SELECT substr(timestamp, 1, 13) AS hour_bucket,
                   CASE WHEN action LIKE '%block%' OR action LIKE '%reject%' THEN 'blocked' ELSE 'allowed' END AS klass,
                   COUNT(*) AS n
            FROM audit_events WHERE timestamp >= ?
            GROUP BY hour_bucket, klass ORDER BY hour_bucket
            """, binds: [since])
        let hourFormat = DateFormatter()
        hourFormat.dateFormat = "yyyy-MM-dd'T'HH"
        hourFormat.timeZone = TimeZone(identifier: "UTC")
        return rows.compactMap { r in
            guard let bucket = r["hour_bucket"] as? String,
                  let date = hourFormat.date(from: bucket),
                  let klass = r["klass"] as? String,
                  let n = r["n"] as? Int else { return nil }
            return (date, klass, n)
        }
    }

    func countBySeverity(blockClassOnly: Bool) -> [Severity: Int] {
        guard tableExists("audit_events") else { return [:] }
        var sql = "SELECT UPPER(severity) AS sev, COUNT(*) AS n FROM audit_events"
        if blockClassOnly {
            sql += " WHERE action LIKE '%block%' OR action LIKE '%reject%' OR action LIKE '%quarantine%'"
        }
        sql += " GROUP BY sev"
        var out: [Severity: Int] = [:]
        for r in query(sql) {
            if let sev = r["sev"] as? String, let n = r["n"] as? Int {
                out[Severity.parse(sev)] = n
            }
        }
        return out
    }

    /// Full tool override rows (actions table) — the data the Tools panel
    /// governs. In hook mode this is the only tool surface: the catalog
    /// endpoint needs an OpenClaw agent, but overrides still enforce.
    func toolOverrideRows() -> [ToolItem] {
        guard tableExists("actions") else { return [] }
        let rows = query("""
            SELECT target_name, actions_json, reason, updated_at
            FROM actions WHERE target_type = 'tool' ORDER BY target_name
            """)
        return rows.compactMap { r in
            guard let name = r["target_name"] as? String else { return nil }
            let json = (r["actions_json"] as? String ?? "").lowercased()
            let state: ToolState = json.contains("block") ? .block
                : json.contains("observe") ? .observe : .allow
            let reason = (r["reason"] as? String) ?? ""
            let updated = (r["updated_at"] as? String) ?? ""
            return ToolItem(
                name: name,
                summary: reason.isEmpty ? "override" : reason,
                signature: updated.isEmpty ? "" : "updated \(updated)",
                state: state,
                usageCount: 0
            )
        }
    }

    /// Tool allow/block overrides from the actions table.
    func toolOverrides() -> [String: ToolState] {
        guard tableExists("actions") else { return [:] }
        let rows = query("SELECT target_name, actions_json FROM actions WHERE target_type = 'tool'")
        var out: [String: ToolState] = [:]
        for r in rows {
            guard let name = r["target_name"] as? String else { continue }
            let json = (r["actions_json"] as? String ?? "").lowercased()
            if json.contains("block") { out[name] = .block }
            else if json.contains("observe") { out[name] = .observe }
            else { out[name] = .allow }
        }
        return out
    }

    func activityEvents(limit: Int) -> [ActivityMutation] {
        guard tableExists("activity_events") else { return [] }
        return query("SELECT * FROM activity_events ORDER BY timestamp DESC LIMIT ?", binds: [limit]).map { r in
            ActivityMutation(
                id: (r["id"] as? String) ?? String(describing: r["id"] ?? UUID().uuidString),
                timestamp: DCDates.parse(r["timestamp"]) ?? Date(timeIntervalSince1970: 0),
                actor: (r["actor"] as? String) ?? "",
                action: (r["action"] as? String) ?? "",
                targetType: (r["target_type"] as? String) ?? "",
                targetID: (r["target_id"] as? String) ?? "",
                reason: (r["reason"] as? String) ?? "",
                versionFrom: (r["version_from"] as? String) ?? "",
                versionTo: (r["version_to"] as? String) ?? "",
                beforeJSON: (r["before_json"] as? String) ?? "",
                afterJSON: (r["after_json"] as? String) ?? "",
                connector: (r["connector"] as? String) ?? ConnectorAttribution.fromDetails((r["reason"] as? String) ?? "")
            )
        }
    }

    func egressEvents(limit: Int) -> [EgressEvent] {
        guard tableExists("network_egress_events") else { return [] }
        return query("SELECT * FROM network_egress_events ORDER BY timestamp DESC LIMIT ?", binds: [limit]).map { r in
            let blocked = ((r["blocked"] as? Int) ?? 0) == 1
            return EgressEvent(
                id: (r["id"] as? String) ?? String(describing: r["id"] ?? UUID().uuidString),
                timestamp: DCDates.parse(r["timestamp"]) ?? Date(timeIntervalSince1970: 0),
                target: (r["hostname"] as? String) ?? (r["url"] as? String) ?? "",
                decision: blocked ? "blocked" : ((r["policy_outcome"] as? String) ?? "allowed"),
                reason: (r["details"] as? String) ?? (r["decision_code"] as? String) ?? "",
                looksLikeLLM: false,
                branch: (r["protocol"] as? String) ?? "",
                severity: Severity.parse(r["severity"] as? String)
            )
        }
    }

    struct ConnectorStats {
        var hookCalls = 0
        var blocks = 0
        var alerts = 0
        var lastActivity: Date?
    }

    /// Per-connector activity derived from recent audit events — the TUI's
    /// fallback for hook connectors, whose calls arrive out-of-band of the
    /// gateway's request counters. Connector attribution comes from the
    /// `connector=<name>` kv token in each event's details.
    func connectorStats(window: Int = 1000) -> [String: ConnectorStats] {
        guard tableExists("audit_events") else { return [:] }
        let rows = query("""
            SELECT action, severity, timestamp, details FROM audit_events
            ORDER BY timestamp DESC LIMIT ?
            """, binds: [window])
        var stats: [String: ConnectorStats] = [:]
        for r in rows {
            let details = (r["details"] as? String) ?? ""
            guard let range = details.range(of: "connector=") else { continue }
            let connector = details[range.upperBound...]
                .prefix { !$0.isWhitespace && $0 != "," }
            guard !connector.isEmpty else { continue }
            let name = String(connector)
            var s = stats[name] ?? ConnectorStats()
            let action = ((r["action"] as? String) ?? "").lowercased()
            if action == "connector-hook" { s.hookCalls += 1 }
            if ["block", "guardrail-block", "deny", "quarantine"].contains(action)
                || details.contains("action=block") || details.contains("action=deny") {
                s.blocks += 1
            }
            let severity = Severity.parse(r["severity"] as? String)
            if severity > .info { s.alerts += 1 }
            if let ts = DCDates.parse(r["timestamp"]), ts > (s.lastActivity ?? .distantPast) {
                s.lastActivity = ts
            }
            stats[name] = s
        }
        return stats
    }

    /// Newest block-class event timestamp — used for new-alert detection.
    func latestBlockTimestamp() -> Date? {
        guard tableExists("audit_events") else { return nil }
        let rows = query("""
            SELECT timestamp FROM audit_events
            WHERE action LIKE '%block%' OR action LIKE '%reject%'
            ORDER BY timestamp DESC LIMIT 1
            """)
        return DCDates.parse(rows.first?["timestamp"])
    }
}
