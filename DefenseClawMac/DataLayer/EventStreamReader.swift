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
            let summarySeverity = Severity.parse((scan["severity_max"] as? String) ?? (obj["severity"] as? String))
            if summarySeverity > block.severity { block.severity = summarySeverity }
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
            let findingSeverity = Severity.parse((finding["severity"] as? String) ?? (obj["severity"] as? String))
            if findingSeverity > block.severity { block.severity = findingSeverity }
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
        let parsed = parseLogFields(obj, rowType: rowType)
        let action = parsed.action
        let eventType = parsed.eventType
        let target = parsed.target
        let details = parsed.details
        // Gateway JSONL rows carry the attributed connector at top level or in
        // nested lifecycle/audit payloads; fall back to connector= kv details.
        let connector = parsed.connector.isEmpty
            ? ConnectorAttribution.fromDetails(details)
            : parsed.connector

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
        let message = displayMessage(for: parsed, severity: severity, raw: raw)
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

    private struct ParsedLogFields {
        var rowType = ""
        var eventType = ""
        var action = ""
        var target = ""
        var details = ""
        var actor = ""
        var connector = ""
        var subsystem = ""
        var transition = ""
        var scanner = ""
        var verdict = ""
        var findingTitle = ""
        var findingLocation = ""
        var findingCount: Int?
    }

    private func parseLogFields(_ obj: [String: Any], rowType: String) -> ParsedLogFields {
        let lifecycle = obj["lifecycle"] as? [String: Any]
        let lifecycleDetails = lifecycle?["details"] as? [String: Any]
        let scan = obj["scan"] as? [String: Any]
        let finding = obj["scan_finding"] as? [String: Any]
        let audit = obj["audit"] as? [String: Any]
        let payload = obj["payload"] as? [String: Any]

        let eventType = firstString(
            obj["event_type"], obj["event"], obj["type"], obj["row_type"], rowType
        )
        let action = firstString(
            obj["action"],
            lifecycleDetails?["action"],
            audit?["action"],
            payload?["action"],
            scan?["action"],
            finding?["action"]
        )
        let target = firstString(
            obj["target"],
            lifecycleDetails?["target"],
            audit?["target"],
            payload?["target"],
            scan?["target"],
            finding?["target"]
        )
        let details = sanitizeLogDetails(firstString(
            obj["details"],
            obj["message"],
            obj["msg"],
            obj["content"],
            lifecycleDetails?["details"],
            lifecycleDetails?["content"],
            audit?["details"],
            audit?["content"],
            payload?["details"],
            payload?["content"],
            finding?["description"],
            finding?["content"],
            scan?["details"],
            scan?["content"]
        ))
        let connector = firstString(
            obj["connector"],
            lifecycleDetails?["connector"],
            audit?["connector"],
            payload?["connector"],
            scan?["connector"],
            finding?["connector"],
            ConnectorAttribution.fromTarget(target),
            ConnectorAttribution.fromDetails(details)
        )
        return ParsedLogFields(
            rowType: rowType,
            eventType: eventType,
            action: action,
            target: target,
            details: details,
            actor: firstString(obj["actor"], lifecycleDetails?["actor"], audit?["actor"], payload?["actor"]),
            connector: connector,
            subsystem: firstString(lifecycle?["subsystem"], obj["subsystem"], payload?["subsystem"]),
            transition: firstString(lifecycle?["transition"], obj["transition"], payload?["transition"]),
            scanner: firstString(scan?["scanner"], finding?["scanner"], obj["scanner"]),
            verdict: firstString(scan?["verdict"], obj["verdict"], payload?["verdict"]),
            findingTitle: firstString(finding?["title"], obj["title"]),
            findingLocation: firstString(finding?["location"], obj["location"]),
            findingCount: firstInt(scan?["total_count"], scan?["finding_count"], obj["finding_count"])
        )
    }

    private func displayMessage(for row: ParsedLogFields, severity: Severity, raw: String) -> String {
        switch row.eventType {
        case "lifecycle":
            let subject = [row.subsystem, row.transition].filter { !$0.isEmpty }.joined(separator: " ")
            let headline = [subject, row.action].filter { !$0.isEmpty }.joined(separator: " ")
            let actorTarget = actorTarget(row.actor, row.target)
            return joinedParts(headline, actorTarget, row.details, fallback: raw)
        case "scan":
            let findingText = row.findingCount.map { "\($0) finding\($0 == 1 ? "" : "s")" } ?? ""
            let severityText = severity > .info ? severity.rawValue : ""
            let headline = joinedWords("Scan", row.verdict, row.scanner)
            return joinedParts(headline, row.target, severityText, findingText, row.details, fallback: raw)
        case "scan_finding":
            let headline = joinedWords("Finding", row.findingTitle)
            let severityText = severity > .info ? severity.rawValue : ""
            return joinedParts(headline, row.scanner, row.target, row.findingLocation, severityText, row.details, fallback: raw)
        default:
            let headline = joinedWords(row.action, row.eventType == "event" ? "" : row.eventType)
            return joinedParts(headline, actorTarget(row.actor, row.target), row.details, fallback: raw)
        }
    }

    private func actorTarget(_ actor: String, _ target: String) -> String {
        if !actor.isEmpty && !target.isEmpty { return "\(actor) -> \(target)" }
        return actor.isEmpty ? target : actor
    }

    private func joinedWords(_ parts: String...) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func joinedParts(_ parts: String..., fallback: String) -> String {
        let message = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        return message.isEmpty ? fallback : message
    }

    private func firstString(_ values: Any?...) -> String {
        for value in values {
            if let string = value as? String {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            } else if let value {
                let string = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
                if !string.isEmpty { return string }
            }
        }
        return ""
    }

    private func firstInt(_ values: Any?...) -> Int? {
        for value in values {
            if let int = value as? Int { return int }
            if let string = value as? String, let int = Int(string) { return int }
        }
        return nil
    }

    private func sanitizeLogDetails(_ details: String) -> String {
        let tokens = logDetailTokens(from: details)
            .filter { !isNoisyLogDetailToken($0) }
        return tokens.joined(separator: " ")
    }

    private func logDetailTokens(from text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var angleDepth = 0

        func appendCurrent() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { tokens.append(trimmed) }
            current = ""
        }

        for character in text {
            if character == "<" {
                angleDepth += 1
                current.append(character)
            } else if character == ">" {
                if angleDepth > 0 { angleDepth -= 1 }
                current.append(character)
            } else if isWhitespace(character), angleDepth == 0 {
                appendCurrent()
            } else {
                current.append(character)
            }
        }
        appendCurrent()
        return tokens
    }

    private func isNoisyLogDetailToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: ",;")).lowercased()
        guard !lower.isEmpty else { return true }

        let parts = lower.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let key = parts.first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'` "))
            ?? lower
        let value = parts.count > 1 ? String(parts[1]) : ""
        let hasValue = parts.count > 1

        if !hasValue {
            if lower.contains("<redacted"), lower.contains("len=") || lower.contains("sha=") {
                return true
            }
            return isLikelyHashValue(lower)
        }
        if key.contains("hash") || key.contains("hmac") || key.contains("checksum") || key.contains("digest") {
            return true
        }
        if key == "sha" || key.hasPrefix("sha") || key.hasSuffix("_sha") {
            return true
        }
        if key.contains("elapsed") || key.contains("duration") || key.contains("latency") || key == "took" || key == "took_ms" {
            return true
        }
        if key.contains("bytes") || key == "byte" || key == "size" ||
            key == "content-length" || key == "content_length" ||
            key == "payload_len" || key == "body_len" ||
            key == "request_len" || key == "response_len" {
            return true
        }
        if value.contains("<redacted"), value.contains("len=") || value.contains("sha=") {
            return true
        }
        if isLikelyHashValue(value) {
            return true
        }
        return false
    }

    private func isLikelyHashValue(_ value: String) -> Bool {
        let candidate = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'`,;<>"))
        guard candidate.count >= 16 else { return false }
        return candidate.unicodeScalars.allSatisfy { scalar in
            ("0"..."9").contains(Character(scalar)) ||
                ("a"..."f").contains(Character(scalar)) ||
                ("A"..."F").contains(Character(scalar))
        }
    }

    private func isWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
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
