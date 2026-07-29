import Foundation

struct AlertDispositionInvocation: Equatable, Sendable {
    let arguments: [String]
    let standardInput: String
}

enum AlertDispositionCommand {
    /// Runtime 0.8.9 keeps severity selectors and asks for confirmation before
    /// applying a broad mutation. Supplying the answer on stdin also remains
    /// compatible with older tagged runtimes that ignore it.
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
