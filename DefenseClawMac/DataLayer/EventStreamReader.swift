// Incremental tailer for ~/.defenseclaw/gateway.jsonl.
// Remembers byte offset, handles truncation/rotation (falls back to the last
// 512 KiB — the same budget the Go reader and TUI use), classifies rows into
// the four TUI log streams, and extracts scan findings / activity / egress rows.

import Foundation

struct StreamDelta: Sendable {
    var logRows: [LogRow] = []
    var findings: [ScanFindingEvent] = []
    var activity: [ActivityMutation] = []
    var egress: [EgressEvent] = []
}

actor EventStreamReader {
    static let tailBudget = 512 * 1024

    private let url: URL
    private var offset: UInt64 = 0
    private var rowCounter = 0

    private(set) var logBuffers: [LogStream: [LogRow]] = [:]
    private(set) var findings: [ScanFindingEvent] = []
    private(set) var activity: [ActivityMutation] = []
    private(set) var egress: [EgressEvent] = []

    /// Scan blocks grouped by scan_id — mirrors load_gateway_scan_blocks,
    /// which reads the WHOLE file (not the 512 KiB tail).
    private var scanBlockMap: [String: ScanBlockEvent] = [:]
    private var blocksScannedOnce = false

    var scanBlocks: [ScanBlockEvent] {
        scanBlockMap.values.sorted { $0.timestamp > $1.timestamp }
    }

    private let bufferCap = 20_000

    init(url: URL = ConfigStore.gatewayJSONLURL) {
        self.url = url
    }

    /// One full-file pass for scan/scan_finding rows (cheap substring prefilter,
    /// JSON parse only on candidate lines). Tail polling keeps it current after.
    private func scanWholeFileForBlocks() {
        guard let data = try? Data(contentsOf: url) else { return }
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") {
            guard line.contains("\"event_type\":\"scan") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            ingestScanBlock(obj)
        }
    }

    private func ingestScanBlock(_ obj: [String: Any]) {
        let eventType = (obj["event_type"] as? String) ?? ""
        let ts = DCDates.parse(obj["ts"] ?? obj["timestamp"]) ?? Date()
        let connector = (obj["connector"] as? String) ?? ""
        if eventType == "scan", let scan = obj["scan"] as? [String: Any],
           let scanID = scan["scan_id"].map({ String(describing: $0) }), !scanID.isEmpty {
            var block = scanBlockMap[scanID] ?? ScanBlockEvent(
                scanID: scanID, timestamp: ts, scanner: "", target: "",
                severity: .info, verdict: "", findingCount: 0, findingTitles: []
            )
            block.scanner = (scan["scanner"] as? String) ?? block.scanner
            block.target = (scan["target"] as? String) ?? block.target
            block.severity = Severity.parse((scan["severity_max"] as? String) ?? (obj["severity"] as? String))
            block.verdict = (scan["verdict"] as? String) ?? block.verdict
            block.timestamp = max(block.timestamp, ts)
            // Hook scans carry the connector in the target prefix
            // ("claudecode:PostToolUse"), not a top-level field.
            let resolved = !connector.isEmpty ? connector : ConnectorAttribution.fromTarget(block.target)
            if !resolved.isEmpty { block.connector = resolved }
            if let total = scan["total_count"] as? Int, total > block.findingCount {
                block.findingCount = total
            }
            scanBlockMap[scanID] = block
        } else if eventType == "scan_finding", let finding = obj["scan_finding"] as? [String: Any],
                  let scanID = finding["scan_id"].map({ String(describing: $0) }), !scanID.isEmpty {
            var block = scanBlockMap[scanID] ?? ScanBlockEvent(
                scanID: scanID, timestamp: ts,
                scanner: (finding["scanner"] as? String) ?? "",
                target: (finding["target"] as? String) ?? "",
                severity: Severity.parse(obj["severity"] as? String),
                verdict: "", findingCount: 0, findingTitles: []
            )
            block.findingCount += 1
            if let title = finding["title"] as? String, block.findingTitles.count < 5 {
                block.findingTitles.append(title)
            }
            block.timestamp = max(block.timestamp, ts)
            let resolved = !connector.isEmpty ? connector : ConnectorAttribution.fromTarget(block.target)
            if !resolved.isEmpty { block.connector = resolved }
            scanBlockMap[scanID] = block
        }
    }

    var fileExists: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    /// Reads any new bytes appended since the last call; first call reads the tail budget.
    func poll() -> StreamDelta {
        if !blocksScannedOnce {
            blocksScannedOnce = true
            scanWholeFileForBlocks()
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return StreamDelta() }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0

        if offset == 0 || offset > size {
            // First read, or the file was truncated/rotated: read tail budget only.
            offset = size > UInt64(Self.tailBudget) ? size - UInt64(Self.tailBudget) : 0
        }
        guard size > offset else { return StreamDelta() }

        try? handle.seek(toOffset: offset)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return StreamDelta() }
        offset = size

        var delta = StreamDelta()
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n") {
            guard let lineData = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }
            ingest(obj, raw: String(line), into: &delta)
        }

        for row in delta.logRows {
            logBuffers[row.stream, default: []].append(row)
            if logBuffers[row.stream]!.count > bufferCap {
                logBuffers[row.stream]!.removeFirst(logBuffers[row.stream]!.count - bufferCap)
            }
        }
        findings.append(contentsOf: delta.findings)
        activity.append(contentsOf: delta.activity)
        egress.append(contentsOf: delta.egress)
        if findings.count > bufferCap { findings.removeFirst(findings.count - bufferCap) }
        if activity.count > bufferCap { activity.removeFirst(activity.count - bufferCap) }
        if egress.count > bufferCap { egress.removeFirst(egress.count - bufferCap) }
        return delta
    }

    /// Reset and re-read the tail (the Logs panel's "reload from disk").
    func reload() -> StreamDelta {
        offset = 0
        logBuffers = [:]
        findings = []
        activity = []
        egress = []
        scanBlockMap = [:]
        blocksScannedOnce = false
        return poll()
    }

    private func nextID(_ obj: [String: Any], _ kind: String) -> String {
        if let id = obj["id"] as? String { return id }
        rowCounter += 1
        return "\(kind)-\(rowCounter)"
    }

    private func ingest(_ obj: [String: Any], raw: String, into delta: inout StreamDelta) {
        // Gateway rows carry their kind in "event_type" (scan / scan_finding / activity).
        let rowType = (obj["event_type"] as? String) ?? (obj["type"] as? String) ?? (obj["row_type"] as? String) ?? "event"
        ingestScanBlock(obj) // keeps the scan_id-grouped block map current
        let ts = DCDates.parse(obj["ts"] ?? obj["timestamp"] ?? obj["time"]) ?? Date()
        let severity = Severity.parse(obj["severity"] as? String)
        let action = (obj["action"] as? String) ?? ""
        let eventType = (obj["event_type"] as? String) ?? (obj["event"] as? String) ?? rowType
        let target = (obj["target"] as? String) ?? ""
        let details = (obj["details"] as? String) ?? (obj["message"] as? String) ?? (obj["msg"] as? String) ?? ""
        // Gateway JSONL rows carry the attributed connector at top level; fall
        // back to the connector= kv in details for older/embedded rows.
        let connector = (obj["connector"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? ConnectorAttribution.fromDetails(details)

        switch rowType {
        case "scan_finding":
            let finding = (obj["scan_finding"] as? [String: Any]) ?? obj
            let findingTarget = (finding["target"] as? String) ?? target
            delta.findings.append(ScanFindingEvent(
                id: nextID(obj, "finding"),
                timestamp: ts,
                scanner: (finding["scanner"] as? String) ?? "scanner",
                target: findingTarget,
                title: (finding["title"] as? String) ?? action,
                detail: (finding["description"] as? String) ?? details,
                location: (finding["location"] as? String) ?? "",
                remediation: (finding["remediation"] as? String) ?? "",
                severity: severity,
                runID: (obj["run_id"] as? String) ?? "",
                connector: connector.isEmpty ? ConnectorAttribution.fromTarget(findingTarget) : connector
            ))
        case "activity":
            let before = jsonString(obj["before_json"] ?? obj["before"])
            let after = jsonString(obj["after_json"] ?? obj["after"])
            delta.activity.append(ActivityMutation(
                id: nextID(obj, "activity"),
                timestamp: ts,
                actor: (obj["actor"] as? String) ?? "system",
                action: action.isEmpty ? eventType : action,
                targetType: (obj["target_type"] as? String) ?? "",
                targetID: (obj["target_id"] as? String) ?? target,
                reason: (obj["reason"] as? String) ?? details,
                versionFrom: String(describing: obj["version_from"] ?? ""),
                versionTo: String(describing: obj["version_to"] ?? ""),
                beforeJSON: before,
                afterJSON: after,
                connector: connector
            ))
        case "egress":
            delta.egress.append(EgressEvent(
                id: nextID(obj, "egress"),
                timestamp: ts,
                target: target.isEmpty ? ((obj["hostname"] as? String) ?? "") : target,
                decision: (obj["decision"] as? String) ?? action,
                reason: (obj["reason"] as? String) ?? details,
                looksLikeLLM: (obj["looks_like_llm"] as? Bool) ?? false,
                branch: (obj["branch"] as? String) ?? "",
                severity: severity,
                connector: connector
            ))
        default:
            break
        }

        // Every row also lands in a log stream (parity with load_gateway_log_views).
        let stream = classifyStream(rowType: rowType, eventType: eventType, action: action, details: details)
        let message = [action, target, details].filter { !$0.isEmpty }.joined(separator: " · ")
        delta.logRows.append(LogRow(
            id: nextID(obj, "log"),
            timestamp: ts,
            stream: stream,
            severity: severity,
            action: action,
            eventType: eventType,
            message: message.isEmpty ? raw : message,
            rawJSON: raw,
            connector: connector
        ))
    }

    private func classifyStream(rowType: String, eventType: String, action: String, details: String) -> LogStream {
        let haystack = "\(rowType) \(eventType) \(action) \(details)".lowercased()
        if haystack.contains("verdict") || haystack.contains("judge") || haystack.contains("triage") {
            return .verdicts
        }
        if haystack.contains("otel") || haystack.contains("otlp") || haystack.contains("telemetry") {
            return .otel
        }
        if haystack.contains("watchdog") || haystack.contains("health probe") {
            return .watchdog
        }
        return .gateway
    }

    private func jsonString(_ value: Any?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]) {
            return String(decoding: data, as: UTF8.self)
        }
        return String(describing: value)
    }
}
