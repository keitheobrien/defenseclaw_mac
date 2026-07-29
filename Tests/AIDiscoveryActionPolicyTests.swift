import Foundation

@main
enum AIDiscoveryActionPolicyTests {
    static func main() {
        let disabled = AIDiscoveryPrimaryAction.resolve(enabled: false)
        expect(disabled == .enable, "disabled discovery must offer Enable")
        expect(disabled.label == "Enable AI Discovery", "enable action label drifted")
        expect(
            disabled.arguments == ["agent", "discovery", "enable", "--yes"],
            "enable action must use the canonical non-interactive runtime command"
        )

        let enabled = AIDiscoveryPrimaryAction.resolve(enabled: true)
        expect(enabled == .scan, "enabled discovery must offer Scan")
        expect(enabled.label == "Scan Now", "scan action label drifted")
        expect(
            enabled.arguments == ["agent", "discovery", "scan"],
            "scan action must use the canonical runtime command"
        )

        expect(
            AIDiscoveryScanRequestStep.resolve(statusLoaded: false, enabled: false) == .loadStatus,
            "a first-open scan request must wait for status instead of being dropped"
        )
        expect(
            AIDiscoveryScanRequestStep.resolve(statusLoaded: true, enabled: false) == .showDisabled,
            "a disabled status must explain how to enable discovery"
        )
        expect(
            AIDiscoveryScanRequestStep.resolve(statusLoaded: true, enabled: true) == .scan,
            "an enabled status must run the requested scan"
        )

        let disabledBody = #"{"error":"ai discovery disabled"}"#
        expect(
            GatewayErrorBody.userFacingMessage(status: 503, body: disabledBody)
                == "AI Discovery is disabled. Enable it before starting a scan.",
            "canonical disabled response must be actionable"
        )
        expect(
            GatewayErrorBody.userFacingMessage(status: 500, body: disabledBody) == nil,
            "non-503 responses must retain their normal error handling"
        )
        expect(
            GatewayErrorBody.userFacingMessage(status: 503, body: #"{"error":"internal details"}"#) == nil,
            "unknown gateway bodies must not be surfaced"
        )

        print("AI Discovery action policy tests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAILED: \(message)\n", stderr)
            exit(1)
        }
    }
}
