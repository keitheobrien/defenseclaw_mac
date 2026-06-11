// Async REST client for the DefenseClaw Go gateway sidecar (localhost only).
// Endpoint set and timeouts mirror the Python TUI's OrchestratorClient.

import Foundation

actor GatewayClient {
    private var baseURL: URL
    private var token: String?
    private let session: URLSession

    static let defaultTimeout: TimeInterval = 5
    static let pluginTimeout: TimeInterval = 90
    static let scanTimeout: TimeInterval = 120

    init(config: DefenseClawConfig = DefenseClawConfig()) {
        self.baseURL = config.baseURL
        self.token = config.gatewayToken
        let conf = URLSessionConfiguration.ephemeral
        conf.timeoutIntervalForRequest = Self.defaultTimeout
        conf.waitsForConnectivity = false
        self.session = URLSession(configuration: conf)
    }

    func update(config: DefenseClawConfig) {
        baseURL = config.baseURL
        token = config.gatewayToken
    }

    // MARK: - Request plumbing

    private func request(
        _ method: String, _ path: String,
        body: [String: Any]? = nil,
        timeout: TimeInterval = GatewayClient.defaultTimeout
    ) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL) else {
            throw GatewayError.badResponse("bad path \(path)")
        }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("macos-app", forHTTPHeaderField: "X-DefenseClaw-Client")
        if method != "GET" {
            // Token + Content-Type double as CSRF protection on the gateway.
            if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body ?? [:])
        } else if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch let err as URLError {
            switch err.code {
            case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost:
                throw GatewayError.offline
            case .timedOut:
                throw GatewayError.timeout
            default:
                throw GatewayError.offline
            }
        }
        guard let http = response as? HTTPURLResponse else {
            throw GatewayError.badResponse("non-HTTP response")
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401, 403:
            throw GatewayError.unauthorized
        default:
            throw GatewayError.degraded(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func getJSON(_ path: String, timeout: TimeInterval = GatewayClient.defaultTimeout) async throws -> Any {
        let data = try await request("GET", path, timeout: timeout)
        return try JSONSerialization.jsonObject(with: data)
    }

    @discardableResult
    private func post(_ path: String, _ body: [String: Any] = [:], timeout: TimeInterval = GatewayClient.defaultTimeout) async throws -> Any? {
        let data = try await request("POST", path, body: body, timeout: timeout)
        return data.isEmpty ? nil : try? JSONSerialization.jsonObject(with: data)
    }

    // MARK: - Health & status

    func health() async throws -> HealthSnapshot {
        let json = try await getJSON("/health")
        guard let dict = json as? [String: Any] else { throw GatewayError.badResponse("/health not an object") }
        var snap = HealthSnapshot()
        snap.fetchedAt = Date()
        snap.state = (dict["state"] as? String) ?? (dict["status"] as? String) ?? "running"
        snap.uptimeMs = (dict["uptime_ms"] as? Int) ?? (dict["uptimeMs"] as? Int) ?? 0
        snap.lastError = dict["last_error"] as? String ?? dict["lastError"] as? String
        snap.version = dict["version"] as? String

        // Subsystems: any nested object with a state/status field becomes a row.
        let known = ["watcher", "api", "guardrail", "telemetry", "ai_discovery", "sinks", "sandbox", "gateway", "watchdog"]
        for key in known {
            if let sub = dict[key] as? [String: Any],
               let state = (sub["state"] as? String) ?? (sub["status"] as? String) {
                snap.subsystems.append(.init(name: key, state: state, detail: sub["detail"] as? String ?? sub["error"] as? String))
            } else if let state = dict[key] as? String {
                snap.subsystems.append(.init(name: key, state: state, detail: nil))
            }
        }

        let connectorList = (dict["connectors"] as? [[String: Any]])
            ?? (dict["connector_health"] as? [[String: Any]])
            ?? []
        snap.connectors = connectorList.map { c in
            ConnectorHealth(
                name: (c["name"] as? String) ?? (c["connector"] as? String) ?? "connector",
                mode: (c["mode"] as? String) ?? "observe",
                rulePack: (c["rule_pack"] as? String) ?? (c["rulePack"] as? String) ?? "default",
                lastActivity: DCDates.parse(c["last_activity"] ?? c["lastActivity"]),
                calls: (c["calls"] as? Int) ?? 0,
                blocks: (c["blocks"] as? Int) ?? 0,
                alerts: (c["alerts"] as? Int) ?? 0,
                state: (c["state"] as? String) ?? (c["status"] as? String) ?? "active"
            )
        }
        return snap
    }

    func status() async throws -> [String: Any] {
        (try await getJSON("/status") as? [String: Any]) ?? [:]
    }

    // MARK: - Catalogs

    func skills() async throws -> [SkillItem] {
        let json = try await getJSON("/skills")
        let rows = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["skills"] as? [[String: Any]]) ?? []
        return rows.map { r in
            SkillItem(
                key: (r["key"] as? String) ?? (r["skillKey"] as? String) ?? (r["name"] as? String) ?? "?",
                name: (r["name"] as? String) ?? (r["key"] as? String) ?? "?",
                version: (r["version"] as? String) ?? "—",
                source: (r["source"] as? String) ?? ((r["bundled"] as? Bool) == true ? "bundled" : "custom"),
                enabled: (r["enabled"] as? Bool) ?? true
            )
        }
    }

    func mcps() async throws -> [MCPItem] {
        let json = try await getJSON("/mcps")
        let rows = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["mcps"] as? [[String: Any]]) ?? []
        return rows.map { r in
            MCPItem(
                name: (r["name"] as? String) ?? "?",
                transport: (r["transport"] as? String) ?? (r["type"] as? String) ?? "stdio",
                endpoint: (r["endpoint"] as? String) ?? (r["url"] as? String) ?? (r["command"] as? String) ?? "—",
                version: (r["version"] as? String) ?? "—",
                enabled: (r["enabled"] as? Bool) ?? true
            )
        }
    }

    func plugins() async throws -> [PluginItem] {
        let dict = try await status()
        let rows = (dict["plugins"] as? [[String: Any]]) ?? []
        return rows.map { r in
            PluginItem(
                name: (r["name"] as? String) ?? "?",
                version: (r["version"] as? String) ?? "—",
                category: (r["category"] as? String) ?? (r["kind"] as? String) ?? "plugin",
                enabled: (r["enabled"] as? Bool) ?? true
            )
        }
    }

    func toolsCatalog() async throws -> [ToolItem] {
        let json = try await getJSON("/tools/catalog")
        let rows = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        return rows.map { r in
            ToolItem(
                name: (r["name"] as? String) ?? "?",
                summary: (r["description"] as? String) ?? "",
                signature: (r["signature"] as? String) ?? (r["schema"] as? String) ?? "",
                state: .allow,
                usageCount: (r["usage_count"] as? Int) ?? (r["usageCount"] as? Int) ?? 0
            )
        }
    }

    // MARK: - Mutations (parity with TUI write actions)

    func setSkill(key: String, enabled: Bool) async throws {
        try await post(enabled ? "/skill/enable" : "/skill/disable", ["skillKey": key])
    }

    func setMCP(name: String, enabled: Bool) async throws {
        try await post(enabled ? "/mcp/enable" : "/mcp/disable", ["name": name])
    }

    func setPlugin(name: String, enabled: Bool) async throws {
        try await post(enabled ? "/plugin/enable" : "/plugin/disable",
                       ["pluginName": name], timeout: Self.pluginTimeout)
    }

    func enforceBlock(targetType: String, targetName: String, reason: String) async throws {
        try await post("/enforce/block",
                       ["targetType": targetType, "targetName": targetName, "reason": reason])
    }

    func enforceAllow(targetType: String, targetName: String, reason: String) async throws {
        try await post("/enforce/allow",
                       ["targetType": targetType, "targetName": targetName, "reason": reason])
    }

    func patchConfig(path: String, value: Any) async throws {
        _ = try await request("PATCH", "/config/patch", body: ["path": path, "value": value])
    }

    func reloadPolicy() async throws {
        try await post("/policy/reload")
    }

    func scanSkills() async throws {
        try await post("/v1/skill/scan", timeout: Self.scanTimeout)
    }

    func scanMCPs() async throws {
        try await post("/v1/mcp/scan", timeout: Self.scanTimeout)
    }

    // MARK: - AI usage / discovery

    func aiUsage() async throws -> AIUsageSnapshot {
        let json = try await getJSON("/api/v1/ai-usage")
        guard let dict = json as? [String: Any] else { return AIUsageSnapshot() }
        var snap = AIUsageSnapshot()
        let summary = (dict["summary"] as? [String: Any]) ?? dict
        snap.totalDetected = (summary["total_signals"] as? Int)
            ?? (summary["active_signals"] as? Int)
            ?? (summary["total_detected"] as? Int) ?? 0
        snap.activeSignals = (summary["active_signals"] as? Int) ?? 0
        snap.filesScanned = (summary["files_scanned"] as? Int) ?? 0
        snap.lastScan = DCDates.parse(summary["scanned_at"] ?? summary["last_scan"] ?? summary["lastScan"])
        let signals = (dict["signals"] as? [[String: Any]]) ?? (dict["components"] as? [[String: Any]]) ?? []
        snap.signals = signals.map(decodeSignal)
        snap.components = signals.map(decodeComponent)
        if snap.totalDetected == 0 { snap.totalDetected = snap.signals.count }
        snap.averageConfidence = normalizeConfidence(summary["avg_confidence"] ?? summary["average_confidence"])
        if snap.averageConfidence == 0, !snap.signals.isEmpty {
            snap.averageConfidence = snap.signals.map(\.confidence).reduce(0, +) / Double(snap.signals.count)
        }
        return snap
    }

    private func decodeSignal(_ r: [String: Any]) -> AISignal {
        let component = r["component"] as? [String: Any]
        return AISignal(
            state: (r["state"] as? String) ?? "",
            product: (r["product"] as? String) ?? (r["name"] as? String) ?? "?",
            vendor: (r["vendor"] as? String) ?? "",
            category: (r["category"] as? String) ?? "",
            detector: (r["detector"] as? String) ?? "",
            version: (component?["version"] as? String) ?? (r["version"] as? String) ?? "",
            ecosystem: (component?["ecosystem"] as? String) ?? "",
            componentName: (component?["name"] as? String) ?? "",
            source: (r["source"] as? String) ?? "",
            confidence: normalizeConfidence(r["confidence"]),
            identityScore: normalizeConfidence(r["identity_score"]),
            identityBand: (r["identity_band"] as? String) ?? "",
            presenceScore: normalizeConfidence(r["presence_score"]),
            presenceBand: (r["presence_band"] as? String) ?? "",
            firstSeen: DCDates.parse(r["first_seen"]),
            lastSeen: DCDates.parse(r["last_seen"]),
            lastActive: DCDates.parse(r["last_active_at"])
        )
    }

    func aiComponents() async throws -> [AIComponent] {
        let json = try await getJSON("/api/v1/ai-usage/components")
        let rows = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["components"] as? [[String: Any]]) ?? []
        return rows.map(decodeComponent)
    }

    func aiComponentLocations(ecosystem: String, name: String) async throws -> [String] {
        let json = try await getJSON("/api/v1/ai-usage/components/\(ecosystem)/\(name)/locations")
        if let arr = json as? [String] { return arr }
        let rows = ((json as? [String: Any])?["locations"] as? [Any]) ?? (json as? [Any]) ?? []
        return rows.compactMap { ($0 as? String) ?? ($0 as? [String: Any])?["path"] as? String }
    }

    func aiComponentHistory(ecosystem: String, name: String) async throws -> [ConfidencePoint] {
        let json = try await getJSON("/api/v1/ai-usage/components/\(ecosystem)/\(name)/history")
        let rows = (json as? [[String: Any]]) ?? ((json as? [String: Any])?["history"] as? [[String: Any]]) ?? []
        return rows.compactMap { r in
            guard let ts = DCDates.parse(r["timestamp"] ?? r["captured_at"]) else { return nil }
            return ConfidencePoint(timestamp: ts, confidence: normalizeConfidence(r["confidence"]))
        }
    }

    func aiScan() async throws {
        try await post("/api/v1/ai-usage/scan", timeout: Self.scanTimeout)
    }

    func confidencePolicy(source: String = "merged") async throws -> String {
        let data = try await request("GET", "/api/v1/ai-usage/confidence/policy?source=\(source)")
        return String(data: data, encoding: .utf8) ?? ""
    }

    func validateConfidencePolicy(yaml: String) async throws -> Bool {
        let result = try await post("/api/v1/ai-usage/confidence/policy/validate", ["policy": yaml])
        return ((result as? [String: Any])?["valid"] as? Bool) ?? true
    }

    private func decodeComponent(_ r: [String: Any]) -> AIComponent {
        // Gateway signal shape: name/vendor/product/category/confidence/state/
        // detector/source (see /api/v1/ai-usage); older shapes used
        // ecosystem/version/last_seen — accept both.
        AIComponent(
            ecosystem: (r["ecosystem"] as? String) ?? (r["vendor"] as? String) ?? (r["category"] as? String) ?? "unknown",
            name: (r["name"] as? String) ?? (r["product"] as? String) ?? "?",
            version: (r["version"] as? String) ?? "—",
            confidence: normalizeConfidence(r["confidence"]),
            state: (r["state"] as? String) ?? "detected",
            lastSeen: DCDates.parse(r["last_seen"] ?? r["lastSeen"] ?? r["observed_at"]),
            locations: (r["locations"] as? [String]) ?? [(r["source"] as? String)].compactMap { $0 }
        )
    }

    private func normalizeConfidence(_ raw: Any?) -> Double {
        let value = (raw as? Double) ?? (raw as? Int).map(Double.init) ?? 0
        return value > 1 ? value / 100 : value // accept 0–100 or 0–1
    }
}
