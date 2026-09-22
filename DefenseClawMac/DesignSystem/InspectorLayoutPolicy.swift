import SwiftUI

enum InspectorLayoutPolicy {
    static let minimumWidth: CGFloat = 250
    static let idealWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 380
}

extension View {
    /// The native inspector supplies the split's width constraints. Let its
    /// main content compress instead of feeding a Table/header's changing
    /// intrinsic minimum back into AppKit during inspector presentation.
    /// Apply before `.inspector`, so the frame wraps the main pane itself.
    func dcInspectorMainContent() -> some View {
        frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }
}
