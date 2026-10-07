import Foundation

@main
struct RedactionCommandTests {
    static func main() {
        let prefixes: [RedactionAdvancedAction: [String]] = [
            .status: ["status"], .removeAll: ["remove-all"], .applyAll: ["apply"], .applyDefaults: ["apply"],
            .defaultsSet: ["defaults", "set"], .defaultsReset: ["defaults", "reset"],
            .bucketList: ["bucket", "list"], .bucketSet: ["bucket", "set"], .bucketReset: ["bucket", "reset"],
            .profileList: ["profile", "list"], .profileShow: ["profile", "show"], .profileSet: ["profile", "set"], .profileRemove: ["profile", "remove"],
            .destinationShow: ["destination", "show"], .destinationSend: ["destination", "send"], .destinationInherit: ["destination", "inherit"],
            .routeList: ["route", "list"], .routeAdd: ["route", "add"], .routeSet: ["route", "set"], .routeMove: ["route", "move"], .routeRemove: ["route", "remove"],
        ]
        for action in RedactionAdvancedAction.allCases {
            var options = RedactionCommandOptions(action: action)
            options.destination = "synthetic-sink"
            options.customProfile = "fixture-profile"
            options.routeName = "fixture-route"
            options.routeBuckets = "security.finding,tool.activity"
            options.position = "1"
            options.emitJSON = true
            options.restart = true
            precondition(options.validationError == nil, action.rawValue)
            let args = options.buildArguments()
            precondition(args.starts(with: ["setup", "redaction"] + prefixes[action]!), action.rawValue)
            precondition(args.contains("--dry-run") == action.isMutation, "every mutation defaults to preview")
            precondition(!args.contains("--restart"), "preview never restarts")
            precondition(args.contains("--json") == action.supportsJSON, "unsupported output flags are absent")
            options.dryRun = false
            precondition(options.buildArguments().contains("--restart") == action.isMutation)
        }
        var route = RedactionCommandOptions(action: .routeAdd)
        route.destination = "sink with spaces"
        route.routeName = "route; literal"
        route.routeAction = "drop"
        route.policyProfile = "stale"
        precondition(!route.buildArguments().contains("stale"), "drop never sends a profile")
        precondition(route.buildArguments().contains("route; literal"), "names remain one argv element")
        route.position = "-1"
        precondition(route.validationError != nil, "invalid route position")
        var bucket = RedactionCommandOptions(action: .bucketSet)
        bucket.policyProfile = "inherit"
        bucket.logs = "off"
        precondition(bucket.buildArguments().contains("--inherit-profile"))
        precondition(bucket.buildArguments().contains("--no-logs"))
        print("RedactionCommandTests: all 21 actions, preview defaults, flags and validation passed")
    }
}
