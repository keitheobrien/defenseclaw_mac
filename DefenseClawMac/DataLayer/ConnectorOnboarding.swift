import Foundation

enum ConnectorOnboarding {
    static func installedConnectors(from discoveryOutput: String, supportedOrder: [String]) -> [String] {
        guard let start = discoveryOutput.firstIndex(of: "{"),
              let end = discoveryOutput.lastIndex(of: "}"),
              start <= end,
              let root = try? JSONSerialization.jsonObject(
                  with: Data(discoveryOutput[start...end].utf8)
              ) as? [String: Any],
              let agents = root["agents"] as? [String: Any]
        else { return [] }

        let installed = Set(agents.compactMap { key, value -> String? in
            guard let details = value as? [String: Any], details["installed"] as? Bool == true else {
                return nil
            }
            let candidate = (details["name"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let raw = candidate.isEmpty ? key : candidate
            return normalizedConnector(raw)
        })
        return supportedOrder.filter { installed.contains(normalizedConnector($0)) }
    }

    static func initializationArguments(
        detectedConnectors: [String],
        fallbackConnector: String,
        actionConnectors: Set<String>,
        profile: String,
        scannerMode: String,
        llmJudge: Bool,
        failMode: String,
        humanApproval: Bool,
        hiltSeverity: String,
        startGateway: Bool,
        verify: Bool
    ) -> [String] {
        var arguments = ["init", "--non-interactive", "--yes", "--json-summary"]
        if detectedConnectors.isEmpty {
            arguments += ["--connector", normalizedConnector(fallbackConnector), "--profile", profile]
        } else {
            arguments.append("--observe-all")
            if profile == "action" {
                let selected = detectedConnectors
                    .map(normalizedConnector)
                    .filter { actionConnectors.contains($0) }
                if !selected.isEmpty {
                    arguments += ["--action-connectors", selected.joined(separator: ",")]
                }
            }
        }
        arguments += [
            "--scanner-mode", scannerMode,
            llmJudge ? "--with-judge" : "--no-judge",
            "--fail-mode", failMode,
        ]
        if profile == "action" {
            arguments.append(humanApproval ? "--human-approval" : "--no-human-approval")
            if humanApproval { arguments += ["--hilt-min-severity", hiltSeverity] }
        }
        arguments.append(startGateway ? "--start-gateway" : "--no-start-gateway")
        arguments.append(verify ? "--verify" : "--no-verify")
        return arguments
    }

    static func normalizedConnector(_ connector: String) -> String {
        let normalized = connector.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "claude-code" ? "claudecode" : normalized
    }
}
