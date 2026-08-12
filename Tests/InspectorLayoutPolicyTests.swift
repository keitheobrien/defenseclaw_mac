import CoreGraphics
import Foundation

@main
struct InspectorLayoutPolicyTests {
    static func main() {
        expect(
            InspectorLayoutPolicy.minimumWidth <= InspectorLayoutPolicy.idealWidth,
            "minimum inspector width must not exceed ideal"
        )
        expect(
            InspectorLayoutPolicy.idealWidth <= InspectorLayoutPolicy.maximumWidth,
            "ideal inspector width must not exceed maximum"
        )

        print("InspectorLayoutPolicyTests passed")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fputs("FAILED: \(message)\n", stderr)
            exit(1)
        }
    }
}
