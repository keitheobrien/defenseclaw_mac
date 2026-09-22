import SwiftUI

enum InspectorLayoutPolicy {
    static let width: CGFloat = 320
}

extension View {
    /// Let the table/header compress inside its available pane width instead
    /// of propagating its content minimum to the outer navigation split.
    func dcInspectorMainContent() -> some View {
        frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
    }

    /// Keep details in the same SwiftUI layout tree as the main content.
    /// A nested native inspector split can enter an AppKit constraint loop
    /// during selection, hydration, and close/reopen transitions on macOS.
    func dcInspector<Details: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Details
    ) -> some View {
        HStack(spacing: 0) {
            dcInspectorMainContent()
            if isPresented.wrappedValue {
                Divider()
                content()
                    .frame(width: InspectorLayoutPolicy.width)
                    .frame(maxHeight: .infinity)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel("Details")
            }
        }
        .dcInspectorMainContent()
        .onExitCommand {
            if isPresented.wrappedValue { isPresented.wrappedValue = false }
        }
    }
}
