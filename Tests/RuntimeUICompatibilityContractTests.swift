import Foundation

@main
enum RuntimeUICompatibilityContractTests {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: RuntimeUICompatibilityContractTests <repository-root>\n", stderr)
            exit(2)
        }

        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let configEditorSource = try source(
            at: root.appendingPathComponent("DefenseClawMac/Features/ConfigEditorDefinitions.swift")
        )
        let logsSource = try source(
            at: root.appendingPathComponent("DefenseClawMac/Features/LogsView.swift")
        )

        expect(!configEditorSource.contains("privacy.disable_redaction"),
               "the config editor must not expose the removed privacy.disable_redaction key")

        for unsupportedSurface in [
            "setup redaction",
            "RedactionToggleSheet",
            "showRedactionToggle",
            "redactionButton",
        ] {
            expect(!logsSource.contains(unsupportedSurface),
                   "the Logs UI must not expose the unsupported runtime 0.8.10 surface: \(unsupportedSurface)")
        }

        expect(logsSource.contains(".inspector(isPresented:"),
               "the Logs view must retain the native inspector crash hotfix")
        expect(logsSource.contains(".dcInspectorColumnWidth()"),
               "the Logs inspector must retain its bounded column width")

        print("RuntimeUICompatibilityContractTests passed")
    }

    private static func source(at url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAILED: \(message)\n", stderr)
            exit(1)
        }
    }
}
