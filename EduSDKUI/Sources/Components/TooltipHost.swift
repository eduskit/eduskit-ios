import SwiftUI

private struct TooltipAnchor {
    let id: UUID
    let bounds: Anchor<CGRect>
    let message: String
    let dismiss: () -> Void
}
private struct TooltipAnchors: PreferenceKey {
    static var defaultValue: [TooltipAnchor] = []
    static func reduce(value: inout [TooltipAnchor], nextValue: () -> [TooltipAnchor]) { value += nextValue() }
}
private struct TooltipAnchorModifier: ViewModifier {
    let message: String
    @Binding var presented: Bool
    @State private var id = UUID()
    func body(content: Content) -> some View {
        content.anchorPreference(key: TooltipAnchors.self, value: .bounds) { bounds in
            presented ? [TooltipAnchor(id: id, bounds: bounds, message: message, dismiss: { presented = false })] : []
        }
    }
}
private struct TooltipHeight: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct TooltipLayer: View {
    let anchor: TooltipAnchor
    let bounds: CGRect
    let viewport: CGSize
    @State private var height: CGFloat = 0
    var body: some View {
        let width = min(FeedbackTokens.tooltipWidth, max(1, viewport.width - FeedbackTokens.inset * 2))
        let x = max(FeedbackTokens.inset + width / 2, min(viewport.width - FeedbackTokens.inset - width / 2, bounds.midX))
        let above = bounds.minY - FeedbackTokens.tooltipOffset - height
        let top = above >= FeedbackTokens.inset ? above : bounds.maxY + FeedbackTokens.tooltipOffset
        let y = max(FeedbackTokens.inset, min(max(FeedbackTokens.inset, viewport.height - FeedbackTokens.inset - height), top))
        Text(anchor.message).font(EduFont.sans(FeedbackTokens.tooltipSize)).lineSpacing(3)
            .foregroundStyle(EduColors.onSurfaceVariant)
            .padding(.horizontal, FeedbackTokens.tooltipPaddingX).padding(.vertical, FeedbackTokens.tooltipPaddingY)
            .frame(width: width).fixedSize(horizontal: false, vertical: true)
            .background(EduColors.surfaceLowest, in: RoundedRectangle(cornerRadius: FeedbackTokens.tooltipRadius))
            .overlay(RoundedRectangle(cornerRadius: FeedbackTokens.tooltipRadius).stroke(EduColors.surfaceHigh, lineWidth: 1))
            .shadow(color: .black.opacity(0.1), radius: 6, y: 4)
            .background(GeometryReader { geometry in Color.clear.preference(key: TooltipHeight.self, value: geometry.size.height) })
            .onPreferenceChange(TooltipHeight.self) { height = $0 }
            .position(x: x, y: y + height / 2).opacity(height > 0 ? 1 : 0)
            .allowsHitTesting(false).accessibilityHidden(true)
            .task(id: anchor.id) {
                try? await Task.sleep(nanoseconds: UInt64(FeedbackTokens.tooltipDurationMs) * 1_000_000)
                if !Task.isCancelled { anchor.dismiss() }
            }
    }
}
public extension View {
    /// Declare an anchor; place eduTooltips() on the containing viewport.
    func eduTooltip(_ message: String, isPresented: Binding<Bool>) -> some View {
        modifier(TooltipAnchorModifier(message: message, presented: isPresented))
    }
    /// A reusable root overlay, independent of classroom state or business commands.
    func eduTooltips() -> some View {
        overlayPreferenceValue(TooltipAnchors.self) { anchors in
            GeometryReader { geometry in
                if let anchor = anchors.last {
                    TooltipLayer(anchor: anchor, bounds: geometry[anchor.bounds], viewport: geometry.size).id(anchor.id)
                }
            }.allowsHitTesting(false)
        }
    }
}
