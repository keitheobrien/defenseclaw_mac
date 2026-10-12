// Copyright 2026 Cisco Systems, Inc. and its affiliates
// SPDX-License-Identifier: Apache-2.0
import Foundation

/// Bounded read-only projections of the 1.0 TUI's IDE and agent identity rows.
enum RuntimeV1Inventory {
    static func ideRows(_ document: [String: Any]) -> [InventoryItem] {
        ((document["ide_plugins"] as? [[String: Any]]) ?? []).prefix(10_000).map { row in
            let name = text(row, "plugin_id", "display_name")
            let user = text(row, "user", "user_name", "user_id")
            let product = text(row, "ide_product", "ide_family")
            let fields = projectedFields(row, keys: ["plugin_id", "display_name", "publisher", "version", "user", "user_name", "user_id", "ide_family", "ide_product", "ide_version", "enabled", "enabled_source", "scope", "remote_kind", "is_ai", "ai_signature_id", "installed_at", "last_seen", "fingerprint"])
            return InventoryItem(category: .idePlugins, name: name, version: text(row, "version"),
                path: [user, product, text(row, "scope"), text(row, "fingerprint")].joined(separator: "/"),
                detail: [product, user, (row["is_ai"] as? Bool) == true ? "AI extension" : "", text(row, "remote_kind")].filter { !$0.isEmpty }.joined(separator: " · "),
                status: text(row, "enabled").isEmpty ? "unknown" : text(row, "enabled"), fields: fields)
        }
    }

    static func agentRows(_ output: String) -> (items: [InventoryItem], note: String)? {
        guard let object = InventoryOutputParser.firstJSONObject(in: output),
              let rows = object["identities"] as? [[String: Any]] else { return nil }
        let items = rows.prefix(1000).compactMap { row -> InventoryItem? in
            let id = text(row, "agent_id")
            guard !id.isEmpty else { return nil }
            return InventoryItem(category: .agents, name: id, version: "", path: "agent identity",
                detail: text(row, "user", "user_name", "user_id"), connector: text(row, "connector"), status: "observed",
                fields: projectedFields(row, keys: ["agent_id", "connector", "user", "user_name", "user_id", "first_seen", "last_seen", "sessions_seen"]))
        }
        let total = (object["total"] as? Int) ?? rows.count
        let note = total > items.count ? "Showing \(items.count) of \(total) agent identities (bounded to 1,000)." : ""
        return (items, note)
    }

    private static func text(_ row: [String: Any], _ keys: String...) -> String {
        keys.compactMap { row[$0] as? String }.first(where: { !$0.isEmpty }) ?? ""
    }

    private static func projectedFields(_ row: [String: Any], keys: [String]) -> [InventoryField] {
        keys.compactMap { key in
            guard let value = row[key], !(value is NSNull), value is String || value is NSNumber else { return nil }
            return InventoryField(label: key.replacingOccurrences(of: "_", with: " ").capitalized,
                                  value: String(describing: value))
        }
    }
}
