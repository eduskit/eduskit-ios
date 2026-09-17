import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Web `.edu-btn` press feedback — `scale 0.9 + spring` + light haptic.
/// Apply via `.buttonStyle(EduPressButtonStyle())`.
public struct EduPressButtonStyle: ButtonStyle {
    public var scale: CGFloat = 0.9
    public var haptic: Bool = true

    public init(scale: CGFloat = 0.9, haptic: Bool = true) {
        self.scale = scale
        self.haptic = haptic
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { pressed in
                #if canImport(UIKit)
                if pressed && haptic {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                #endif
            }
    }
}

/// Convenience: wrap a view in a `Button` styled with `EduPressButtonStyle`.
public struct EduPressable<Content: View>: View {
    var action: () -> Void
    var haptic: Bool
    @ViewBuilder var content: () -> Content

    public init(haptic: Bool = true, action: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.action = action
        self.haptic = haptic
        self.content = content
    }

    public var body: some View {
        Button(action: action) {
            content()
        }
        .buttonStyle(EduPressButtonStyle(haptic: haptic))
    }
}
