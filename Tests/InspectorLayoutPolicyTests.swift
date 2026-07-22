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

        for width: CGFloat in [980, 1_024, 1_179] {
            expect(
                InspectorLayoutPolicy.shouldCollapseSidebar(
                    windowWidth: width,
                    inspectorPresented: true
                ),
                "compact window \(Int(width)) should collapse the sidebar"
            )
        }
        for width: CGFloat in [1_180, 1_440, 1_600] {
            expect(
                !InspectorLayoutPolicy.shouldCollapseSidebar(
                    windowWidth: width,
                    inspectorPresented: true
                ),
                "wide window \(Int(width)) should retain the sidebar"
            )
        }
        expect(
            !InspectorLayoutPolicy.shouldCollapseSidebar(
                windowWidth: 980,
                inspectorPresented: false
            ),
            "closing the inspector should restore the normal layout"
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
