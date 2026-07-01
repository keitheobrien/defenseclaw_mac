import Foundation

struct InventoryOutputParseResult {
    var documents: [[String: Any]]
    var diagnostics: String
}

enum InventoryOutputParser {
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
