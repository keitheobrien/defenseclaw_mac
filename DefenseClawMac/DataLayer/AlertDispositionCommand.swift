import Foundation

struct AlertDispositionInvocation: Equatable, Sendable {
    let arguments: [String]
    let standardInput: String
}

enum AlertDispositionCommand {
    /// Tagged runtime 0.8.6 accepts only severity selectors. Current mainline
    /// keeps those selectors but asks for confirmation before applying a broad
    /// mutation. Supplying the answer on stdin works with both contracts: the
    /// tagged runtime ignores it, while current mainline consumes it.
    static let confirmationInput = "y"

    static func acknowledge(severity: String) -> AlertDispositionInvocation {
        invocation(action: "acknowledge", severity: severity)
    }

    static func dismiss(severity: String?) -> AlertDispositionInvocation {
        invocation(action: "dismiss", severity: severity ?? "all")
    }

    static func suppliesConfirmation(for arguments: [String]) -> Bool {
        arguments.starts(with: ["alerts", "acknowledge"])
            || arguments.starts(with: ["alerts", "dismiss"])
    }

    private static func invocation(action: String, severity: String) -> AlertDispositionInvocation {
        AlertDispositionInvocation(
            arguments: ["alerts", action, "--severity", severity],
            standardInput: confirmationInput
        )
    }
}
