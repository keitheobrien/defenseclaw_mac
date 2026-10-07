import Foundation

// The catalog reader's process boundary is stubbed; these tests exercise the
// production decoder and action gate without importing a runtime or executing it.
enum CatalogCLIError: Error { case invalidJSON(String), commandFailed(String) }
actor CLIRunner {
    struct Result { var succeeded: Bool; var output: String }
    func locateRuntimePython() -> URL? { nil }
    func run(binary: URL? = nil, arguments: [String], standardInput: String? = nil,
             mutation: Bool) -> Result { Result(succeeded: false, output: "unused") }
}

@main
struct PolicyCatalogModelTests {
    static func main() throws {
        let row: [String: Any] = ["id": "one", "cells": ["global"], "detail": "Effective posture", "actions": []]
        func payload(_ ids: [String], cells: [String]? = nil) throws -> String {
            var entry = row
            if let cells { entry["cells"] = cells }
            let views = ids.map { ["id": $0, "scope": "", "title": $0, "columns": ["Name"],
                                   "rows": [entry], "empty": "", "error": ""] as [String: Any] }
            let data = try JSONSerialization.data(withJSONObject: ["scopes": ["global"], "views": views])
            return "runtime diagnostic\nDCPOLICY:" + String(decoding: data, as: UTF8.self)
        }
        let snapshot = try PolicyCatalogSnapshot.decode(payload(PolicyCatalogView.identifiers))
        precondition(snapshot.view("posture", scope: "global")?.rows.first?.matches("POSTURE") == true)
        for invalid in ["{}", try payload(["posture"]), try payload(PolicyCatalogView.identifiers, cells: [])] {
            do { _ = try PolicyCatalogSnapshot.decode(invalid); fatalError("Malformed catalog accepted") }
            catch { }
        }
        var action = PolicyCatalogAction(title: "Switch pack", group: "Rule pack",
                                        arguments: ["guardrail", "use-pack", "strict"], consequence: "Changes protection",
                                        weaker: false, mutation: true)
        precondition(!action.allowed, "pack switches require validation")
        action.validationArguments = ["guardrail", "validate-pack", "/fixture/strict.yaml", "--json"]
        precondition(action.allowed)
        action.arguments = ["setup", "reset", "--yes"]
        precondition(!action.allowed, "catalog cannot introduce unrelated commands")
        action.arguments = ["guardrail", "mode", "action\0"]
        precondition(!action.allowed)
        action.arguments = ["guardrail", "validate-pack", "/fixture/strict.yaml", "--json"]
        action.mutation = false
        precondition(action.allowed)
        action.arguments = ["guardrail", "mode", "action"]
        precondition(!action.allowed, "mutations cannot masquerade as validation")
        print("Policy catalog model tests passed")
    }
}
