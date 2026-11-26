import SwiftUI

/// Reusable presentation shell; dismissal never invokes a classroom command itself.
public struct PopupShell<Content: View>: View {
    let visible: Bool
    let onDismiss: () -> Void
    let onEscape: (() -> Void)?
    let alignBottom: Bool
    let modal: Bool
    let dismissible: Bool
    let dismissOnBackdrop: Bool
    let alignment: Alignment
    let content: () -> Content
    public init(visible: Bool, onDismiss: @escaping () -> Void, alignBottom: Bool = false,
                modal: Bool = true, dismissible: Bool = true, dismissOnBackdrop: Bool = true,
                alignment: Alignment = .center, onEscape: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.visible = visible; self.onDismiss = onDismiss; self.alignBottom = alignBottom
        self.modal = modal; self.dismissible = dismissible; self.dismissOnBackdrop = dismissOnBackdrop
        self.alignment = alignment; self.content = content; self.onEscape = onEscape
    }
    public var body: some View {
        if visible {
            ZStack(alignment: alignment) {
                if modal {
                    Color(red: 15/255, green: 23/255, blue: 42/255).opacity(0.32).ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { if dismissOnBackdrop { onDismiss() } }
                }
                if alignBottom { VStack { Spacer(); content() } } else { content() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(modal ? .isModal : [])
            .accessibilityAction(.escape) { if dismissible { (onEscape ?? onDismiss)() } }
        }
    }
}
