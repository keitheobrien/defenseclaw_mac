import Foundation

/// Release 1.0's canonical alert selection includes findings, non-allow
/// outcomes, health failures, and hook decisions, with agent attribution.
enum RuntimeV1Alerts {
    static func parse(_ output: String) -> [AuditEvent]? {
        guard let data = InventoryOutputParser.firstJSONArrayData(in: output),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              rows.count <= 500 else { return nil }
        var result: [AuditEvent] = []
        var seen = Set<String>()
        for row in rows {
            guard let id = row["id"] as? String, !id.isEmpty, seen.insert(id).inserted,
                  let action = row["action"] as? String,
                  let timestamp = DCDates.parse(row["timestamp"]) else { return nil }
            func text(_ key: String) -> String { row[key] as? String ?? "" }
            let facts = ["decision", "route", "rule", "scanner", "location", "sandbox", "path", "moved_to", "user", "agent_identity_id", "agent_instance_id", "session_id", "agent_depth"].compactMap { key -> InventoryField? in
                guard let value = row[key], value is String || value is NSNumber else { return nil }
                return InventoryField(label: key.replacingOccurrences(of: "_", with: " ").capitalized, value: String(describing: value))
            }
            // ERROR is actionable in the canonical queue; retain its label in
            // facts while mapping to the app's high-severity display bucket.
            let severity = text("severity").uppercased()
            result.append(AuditEvent(id: id, timestamp: timestamp, action: action,
                eventType: "runtime-alert", connector: text("connector"), target: text("target"),
                actor: text("actor"), details: text("details"), structuredJSON: "",
                severity: severity == "ERROR" ? .high : Severity.parse(severity), runID: "",
                runtimeFacts: facts + [InventoryField(label: "Runtime severity", value: severity)]))
        }
        return result
    }
}
