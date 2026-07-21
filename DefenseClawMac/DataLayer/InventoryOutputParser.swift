import Foundation

struct InventoryOutputParseResult {
    var documents: [[String: Any]]
    var diagnostics: String
}

enum InventoryOutputParser {
    /// DefenseClaw 0.8.5+ serializes these expected connector limitations in
    /// `errors` and emits a failure warning for them. They explain empty
    /// categories; they do not represent failed inventory collection.
    private static let nonActionableCapabilityNotes: [String: String] = [
        "agents": "agents are not a first-class concept on this connector",
        "tools": "tool registry is owned by each plugin's manifest",
        "models": "model providers are configured inside the framework",
        "memory": "memory backend is private to the framework",
    ]

    /// Prefer structured errors so known capability notes can be separated
    /// from real subprocess, permission, and configuration failures. Older
    /// payloads without details retain their summary count.
    static func actionableErrorCount(in document: [String: Any]) -> Int {
        if let errors = document["errors"] as? [Any] {
            return errors.reduce(into: 0) { count, error in
                if !isNonActionableCapabilityNote(error, in: document) {
                    count += 1
                }
            }
        }
        let summary = document["summary"] as? [String: Any]
        if let count = summary?["errors"] as? Int { return max(0, count) }
        if let count = summary?["errors"] as? NSNumber { return max(0, count.intValue) }
        return 0
    }

    /// Collapse per-connector aggregate warnings into one accurate warning,
    /// preserving every unrelated diagnostic line.
    static func userFacingDiagnostics(from result: InventoryOutputParseResult) -> String {
        var removedAggregateWarning = false
        var lines = result.diagnostics.components(separatedBy: .newlines).filter { line in
            if isAggregateInventoryFailureWarning(line) {
                removedAggregateWarning = true
                return false
            }
            return !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let failureCount = result.documents.reduce(0) {
            $0 + actionableErrorCount(in: $1)
        }
        if removedAggregateWarning, failureCount > 0 {
            lines.insert(
                "Warning: \(failureCount) connector inventory command(s) failed",
                at: 0
            )
        }
        return lines.joined(separator: "\n")
    }

    /// DefenseClaw emits one object for a single connector and an array for
    /// multiple connectors. CLI diagnostics may surround that JSON because the
    /// app combines stdout and stderr for Activity output.
    static func parse(_ output: String) -> InventoryOutputParseResult? {
        let bytes = Array(output.utf8)
        var candidateStart = 0

        while candidateStart < bytes.count {
            guard bytes[candidateStart] == 0x7B || bytes[candidateStart] == 0x5B else {
                candidateStart += 1
                continue
            }
            guard let candidateEnd = matchingJSONEnd(in: bytes, from: candidateStart) else {
                candidateStart += 1
                continue
            }

            let data = Data(bytes[candidateStart...candidateEnd])
            if let value = try? JSONSerialization.jsonObject(with: data),
               let documents = normalizedDocuments(from: value) {
                let before = String(decoding: bytes[..<candidateStart], as: UTF8.self)
                let afterStart = candidateEnd + 1
                let after = afterStart < bytes.count
                    ? String(decoding: bytes[afterStart...], as: UTF8.self)
                    : ""
                let diagnostics = [before, after]
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: "\n")
                return InventoryOutputParseResult(documents: documents, diagnostics: diagnostics)
            }
            candidateStart += 1
        }
        return nil
    }

    private static func normalizedDocuments(from value: Any) -> [[String: Any]]? {
        if let document = value as? [String: Any], isInventoryDocument(document) {
            return [document]
        }
        if let documents = value as? [[String: Any]],
           documents.allSatisfy(isInventoryDocument) {
            return documents
        }
        return nil
    }

    private static func isInventoryDocument(_ document: [String: Any]) -> Bool {
        document["connector"] != nil
            || document["claw_mode"] != nil
            || document["summary"] != nil
    }

    private static func isNonActionableCapabilityNote(
        _ value: Any,
        in document: [String: Any]
    ) -> Bool {
        guard let error = value as? [String: Any],
              let command = error["command"] as? String,
              let message = error["error"] as? String
        else { return false }

        let connector = (document["connector"] as? String)
            ?? (document["claw_mode"] as? String)
            ?? ""
        guard !connector.isEmpty else { return false }

        return nonActionableCapabilityNotes.contains { category, expectedMessage in
            command.caseInsensitiveCompare("\(connector):\(category)") == .orderedSame
                && message == expectedMessage
        }
    }

    private static func isAggregateInventoryFailureWarning(_ line: String) -> Bool {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "Warning: "
        let suffix = " connector inventory command(s) failed"
        guard value.hasPrefix(prefix), value.hasSuffix(suffix) else { return false }
        let countStart = value.index(value.startIndex, offsetBy: prefix.count)
        let countEnd = value.index(value.endIndex, offsetBy: -suffix.count)
        return Int(value[countStart..<countEnd]) != nil
    }

    private static func matchingJSONEnd(in bytes: [UInt8], from start: Int) -> Int? {
        var expectedClosers: [UInt8] = []
        var inString = false
        var escaped = false

        for index in start..<bytes.count {
            let byte = bytes[index]
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C {
                    escaped = true
                } else if byte == 0x22 {
                    inString = false
                }
                continue
            }

            switch byte {
            case 0x22:
                inString = true
            case 0x7B:
                expectedClosers.append(0x7D)
            case 0x5B:
                expectedClosers.append(0x5D)
            case 0x7D, 0x5D:
                guard expectedClosers.last == byte else { return nil }
                expectedClosers.removeLast()
                if expectedClosers.isEmpty { return index }
            default:
                break
            }
        }
        return nil
    }
}
