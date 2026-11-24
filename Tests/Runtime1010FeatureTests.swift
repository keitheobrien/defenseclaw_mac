import Foundation

@main enum Runtime1010FeatureTests {
    static func main() throws {
        let routing = Runtime1010Features.routing
        let model = routing.first { $0.id == "model-add" }!
        let values = ["name": "alias with spaces", "provider": "openai", "model": "model; $(literal)", "api": "chat\nresponses"]
        precondition(model.validation(values) == nil)
        let args = model.command(values)
        precondition(args == ["routing", "models", "add", "--provider=openai", "--model=model; $(literal)", "--api=chat", "--api=responses", "--", "alias with spaces"])
        precondition(model.validation(values.merging(["api-key-env": "not a variable"]) { _, b in b }) != nil)
        let price = Runtime1010Features.pricing.first { $0.id == "pricing-set" }!
        for bad in ["nan", "inf", "-1", "abc"] {
            precondition(price.validation(["target": "openai/model", "input": bad, "output": "1"]) != nil)
        }
        let explain = Runtime1010Features.guardrail[0]
        precondition(explain.validation(["input": "/private/tmp/decision.json"]) == nil)
        let config = Runtime1010Features.configuration
        let scope = ["setting": "guardrail.cascade.lanes.alignment", "profile": "engineering", "connector": "codex", "value": "\"alert\""]
        precondition(config.configKey(scope) == "guardrail.profiles.engineering.connectors.codex.cascade.lanes.alignment")
        precondition(config.validation(scope) == nil)
        precondition(config.validation(scope.merging(["profile": "a.b"]) { _, b in b }) != nil)
        precondition(config.validation(scope.merging(["value": "{bad}"]) { _, b in b }) != nil)
        let context = Runtime1010Features.context
        let contextValues = ["recent_user_turns": "2", "include_first_user_turn": "true", "include_tool_names": "false", "max_bytes": "8192", "per_turn_bytes": "2048"]
        precondition(context.validation(contextValues) == nil)
        precondition(context.configKey(contextValues) == "routing.context")
        precondition(RuntimeFeatureJSON.object(context.configurationValue(contextValues))?["recent_user_turns"] as? Int == 2)
        precondition(context.validation(contextValues.merging(["recent_user_turns": "9"]) { _, new in new }) != nil)
        precondition(Runtime1010Features.supported("1.0.10"))
        precondition(Runtime1010Features.supported("1.0.11"))
        precondition(!Runtime1010Features.supported("1.0.9"))
        precondition(!Runtime1010Features.supported(nil))
        for invalid in ["1.0.10.extra", "1..10", "1.0.-1"] {
            precondition(!Runtime1010Features.supported(invalid))
        }
        let available = CommandRegistry.paletteCommands(supportedSetupCommands: ["cowork"], runtimeVersion: "1.0.10")
        precondition(available.contains { $0.title == "routing status" })
        precondition(!CommandRegistry.paletteCommands(supportedSetupCommands: [], runtimeVersion: "1.0.9").contains { $0.arguments.first == "routing" })
        for verb in ["login", "run", "connect", "pull"] {
            precondition(CommandRegistry.all.filter { $0.arguments.starts(with: ["substrate", verb]) }.allSatisfy(\.requiresTerminal))
        }
        precondition(RuntimeFeatureJSON.object("not JSON") == nil)
        precondition(RuntimeFeatureJSON.records([NSNull(), ["name": "valid"]]).count == 1)
        let status = RuntimeFeatureJSON.object("{\"models\":[{\"alias\":\"fast\",\"provider\":\"openai\",\"model\":\"fixture\",\"locked\":true}],\"effective\":{\"budgets\":[{\"id\":\"daily\",\"limit_usd\":20,\"exceeded\":true}]}}")!
        let rows = RuntimeFeatureJSON.routingRows(status)
        precondition(rows.count == 2 && rows[0].detail.contains("locked") && rows[1].detail.contains("exceeded"))
        precondition(RuntimeFeatureJSON.cost(nil) == "unknown")
        precondition(RuntimeFeatureJSON.cost(NSNull()) == "unknown")
        precondition(RuntimeFeatureJSON.cost(true) == "unknown")
        precondition(RuntimeFeatureJSON.cost(0) == "$0.0000")
        precondition(RuntimeFeatureJSON.cost(Double.nan) == "unknown")
        if CommandLine.arguments.count > 1 {
            let cases: [(String, [String: String])] = [
                ("model-add", ["name": "fixture", "provider": "openai", "model": "fixture-model"]),
                ("model-default", ["name": "fixture"]),
                ("rule-add", ["id": "fixture-rule", "connectors": "codex", "allow": "fixture", "default": "fixture"]),
                ("rule-move", ["id": "fixture-rule", "to": "1"]),
                ("budget-add", ["id": "fixture-budget", "scope": "user", "subject": "*", "period": "month", "limit-usd": "20", "on-exceed": "warn"]),
                ("pricing-set", ["target": "openai/fixture-model", "input": "1", "output": "2"]),
                ("budget-remove", ["id": "fixture-budget"]),
                ("rule-remove", ["id": "fixture-rule"])
            ]
            let actions = routing + Runtime1010Features.pricing
            let commands = cases.map { id, values in actions.first { $0.id == id }!.command(values) }
            let payload: [String: Any] = ["commands": commands, "configScript": Runtime1010Features.configScript, "contextValue": context.configurationValue(contextValues)]
            try JSONSerialization.data(withJSONObject: payload).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        }
        print("Runtime1010FeatureTests passed")
    }
}
