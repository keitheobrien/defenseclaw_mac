import Foundation

@main
enum RuntimeContractSurfaceTests {
    static func main() {
        precondition(CommandRegistry.sourceCount == 231, "unexpected upstream command count")
        precondition(CommandRegistry.all.count == CommandRegistry.sourceCount, "registry count mismatch")

        let titles = CommandRegistry.all.map(\.title)
        precondition(Set(titles).count == titles.count, "command titles must be unique")
        precondition(titles.contains("setup omnigent"), "OmniGent setup command is missing")
        precondition(titles.contains("setup galileo"), "Galileo setup command is missing")
        precondition(titles.contains("config show effective observability"), "effective observability command is missing")
        precondition(titles.contains("observability plan"), "observability plan command is missing")
        precondition(!titles.contains("setup observability migrate-splunk"), "retired migrate-splunk command remains")
        precondition(!titles.contains("setup redaction"), "retired setup redaction command remains")

        let galileo = command(titled: "setup galileo")
        precondition(galileo.requiresTerminal, "interactive Galileo setup must be terminal-only")

        let keysSet = command(titled: "keys set")
        precondition(keysSet.acceptsSecretInput, "keys set must use hidden stdin")
        let secret = "credential-value-that-must-not-enter-argv"
        let invocation = try! keysSet.invocation(
            extraArguments: ["GALILEO_API_KEY"],
            secretInput: secret
        )
        precondition(invocation.arguments == ["keys", "set", "GALILEO_API_KEY"])
        precondition(invocation.standardInput == secret)
        precondition(!invocation.arguments.contains(secret), "credential leaked into argv")

        let alertInvocation = try! command(titled: "alerts acknowledge").invocation(
            extraArguments: ["--severity", "HIGH"],
            secretInput: ""
        )
        precondition(alertInvocation.standardInput == AlertDispositionCommand.confirmationInput)
        precondition(alertInvocation.arguments == ["alerts", "acknowledge", "--severity", "HIGH"])

        let directAlertInvocation = AlertDispositionCommand.acknowledge(severity: "HIGH")
        precondition(directAlertInvocation.arguments == alertInvocation.arguments)
        precondition(directAlertInvocation.standardInput == "y")

        print("Runtime contract surface tests passed")
    }

    private static func command(titled title: String) -> CommandDefinition {
        guard let result = CommandRegistry.all.first(where: { $0.title == title }) else {
            preconditionFailure("missing command: \(title)")
        }
        return result
    }
}
