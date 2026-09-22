import CoreGraphics
import Foundation

@main
struct InspectorLayoutPolicyTests {
    static func main() {
        expect(InspectorLayoutPolicy.width.isFinite, "inspector width must be finite")
        expect(InspectorLayoutPolicy.width > 0, "inspector width must be positive")

        print("InspectorLayoutPolicyTests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAILED: \(message)\n", stderr)
            exit(1)
        }
    }
}
