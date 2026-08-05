import CoreGraphics

enum InspectorLayoutPolicy {
    static let minimumWidth: CGFloat = 250
    static let idealWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 380
    static let compactWindowThreshold: CGFloat = 1_180

    static func shouldCollapseSidebar(windowWidth: CGFloat, inspectorPresented: Bool) -> Bool {
        inspectorPresented && windowWidth < compactWindowThreshold
    }
}
