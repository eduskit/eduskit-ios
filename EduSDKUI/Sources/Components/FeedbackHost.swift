import SwiftUI


public struct FeedbackHost: View {
    let feedback: UiFeedback?
    let onShown: (UInt64) -> Void
    let onDismiss: (UInt64, String) -> Void
    let onAction: (UInt64, String) -> Void

    public init(feedback: UiFeedback?, onShown: @escaping (UInt64) -> Void, onDismiss: @escaping (UInt64, String) -> Void,
                onAction: @escaping (UInt64, String) -> Void) {
        self.feedback = feedback
        self.onShown = onShown
        self.onDismiss = onDismiss
        self.onAction = onAction
    }

    public var body: some View {
        if let feedback {
            GeometryReader { geo in
                let safe = EduSafeArea.merge(with: geo)
                let landscape = geo.size.width > geo.size.height
                let modal = feedback.mode == .dialog
                let actionable = feedback.mode == .notification && !feedback.actions.isEmpty
                let top = safe.top + (modal ? FeedbackTokens.inset : FeedbackTokens.compactTop)
                let bottom = safe.bottom + (actionable && !landscape ? FeedbackTokens.compactBottom : FeedbackTokens.inset)
                let alignment: Alignment = modal ? .center
                    : actionable && !landscape ? .bottom
                    : feedback.mode == .notification && landscape ? .topTrailing : .top
                PopupShell(visible: true, onDismiss: { onDismiss(feedback.id, "backdrop") },
                    modal: modal && feedback.modal, dismissible: feedback.dismissible,
                    dismissOnBackdrop: feedback.dismissOnBackdrop, alignment: alignment,
                    onEscape: { onDismiss(feedback.id, "escape") }) {
                    FeedbackCardContent(feedback: feedback, onDismiss: onDismiss, onAction: onAction,
                        maxHeight: max(1, geo.size.height - top - bottom))
                        .id(feedback.id)
                        .frame(width: min(modal ? FeedbackTokens.dialogWidth : FeedbackTokens.cardWidth, max(1, geo.size.width - safe.leading - safe.trailing - FeedbackTokens.inset * 2)))
                        .padding(.leading, safe.leading + FeedbackTokens.inset).padding(.trailing, safe.trailing + FeedbackTokens.inset)
                        .padding(.top, top).padding(.bottom, bottom)
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: alignment)
            }
            .task(id: feedback.id) { onShown(feedback.id) }

        }
    }
}

private struct FeedbackCardContent: View {
    let feedback: UiFeedback
    let onDismiss: (UInt64, String) -> Void
    let onAction: (UInt64, String) -> Void
    let maxHeight: CGFloat
    @State private var bodyHeight: CGFloat = 0
    @State private var copied = false
    @State private var footerHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: FeedbackTokens.gap) {
            ScrollView {
                VStack(alignment: .leading, spacing: FeedbackTokens.gap) {
                    header
                    if let detail = feedback.detail {
                        Text(detail).font(EduFont.sans(FeedbackTokens.messageSize)).foregroundStyle(EduColors.onSurfaceVariant)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let diagnostic = feedback.diagnostic { diagnosticBlock(diagnostic) }
                }
                .background(heightReader(FeedbackBodyHeightKey.self))
            }
            .frame(height: min(bodyHeight, max(1, maxHeight - FeedbackTokens.padding * 2 - footerHeight - (feedback.actions.isEmpty ? 0 : FeedbackTokens.gap))))
            if !feedback.actions.isEmpty { actions.background(heightReader(FeedbackFooterHeightKey.self)) }
        }
        .padding(FeedbackTokens.padding)
        .background(EduColors.surfaceLowest)
        .clipShape(RoundedRectangle(cornerRadius: FeedbackTokens.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: FeedbackTokens.radius, style: .continuous).stroke(EduColors.surfaceHigh, lineWidth: 1))
        .eduShadow(.level3)
        .opacity(bodyHeight > 0 ? 1 : 0)
        .onPreferenceChange(FeedbackBodyHeightKey.self) { bodyHeight = $0 }
        .onPreferenceChange(FeedbackFooterHeightKey.self) { footerHeight = $0 }
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { if feedback.dismissible { onDismiss(feedback.id, "escape") } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: FeedbackTokens.gap) {
            toneIcon
            Text(feedback.message)
                .font(EduFont.sans(feedback.mode == .dialog ? FeedbackTokens.dialogMessageSize : FeedbackTokens.messageSize, weight: .semibold))
                .foregroundStyle(EduColors.onSurface)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            if feedback.dismissible { closeButton }
        }
    }

    private var closeButton: some View {
        Button { onDismiss(feedback.id, "close") } label: {
            EduIcon(EduIcons.close, size: 20, tint: EduColors.onSurfaceVariant)
                .frame(width: FeedbackTokens.touch, height: FeedbackTokens.touch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).accessibilityLabel(EduI18n.text("close"))
    }

    private var toneIcon: some View {
        EduIcon(feedback.tone == .info ? "info" : feedback.tone == .success ? EduIcons.checkCircle : EduIcons.warning,
                size: 20, tint: toneColor)
            .frame(width: FeedbackTokens.iconSize, height: FeedbackTokens.iconSize)
            .background(toneColor.opacity(0.08)).clipShape(Circle()).accessibilityHidden(true)
    }

    private var toneColor: Color {
        switch feedback.tone {
        case .info: return EduColors.primary
        case .success: return EduColors.success
        case .warning: return EduColors.warning
        case .error: return EduColors.error
        }
    }

    private var actions: some View {
        VStack(spacing: FeedbackTokens.gap) {
            ForEach(Array(stride(from: 0, to: feedback.actions.count, by: 2)), id: \.self) { start in
                HStack(spacing: FeedbackTokens.gap) {
                    ForEach(Array(feedback.actions[start..<min(start + 2, feedback.actions.count)])) { action in
                        actionButton(action, auxiliary: start > 0 && start == feedback.actions.count - 1)
                    }
                }
            }
        }
    }

    private func actionButton(_ action: FeedbackAction, auxiliary: Bool) -> some View {
        Button { onAction(feedback.id, action.id) } label: {
            Text(action.label).font(EduFont.sans(14, weight: .semibold)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8).padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: FeedbackTokens.touch)
                .foregroundStyle(action.style == .text ? EduColors.primary : action.style == .danger ? EduColors.onError : EduColors.onPrimary)
                .background(action.style == .text ? (auxiliary ? Color.clear : EduColors.primary.opacity(0.07))
                            : action.style == .danger ? EduColors.error : EduColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: FeedbackTokens.buttonRadius))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(feedback.busyActionIds.contains(action.id))
    }

    private func diagnosticBlock(_ diagnostic: FeedbackDiagnostic) -> some View {
        let text = (["code: \(diagnostic.code)", diagnostic.message,
            diagnostic.traceId.map { "traceId: \($0)" }].compactMap { $0 }).joined(separator: "\n")
        return DisclosureGroup(EduI18n.text("feedbackDetails")) {
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(EduFont.sans(12)).foregroundStyle(EduColors.onSurfaceVariant)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Button(EduI18n.text(copied ? "feedbackCopied" : "feedbackCopyDetails")) {
                    UIPasteboard.general.string = text; copied = true
                }.frame(minHeight: FeedbackTokens.touch)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.font(EduFont.sans(12)).foregroundStyle(EduColors.onSurfaceVariant)
    }

    private func heightReader<K: PreferenceKey>(_ key: K.Type) -> some View where K.Value == CGFloat {
        GeometryReader { proxy in Color.clear.preference(key: key, value: proxy.size.height) }
    }
}

private struct FeedbackBodyHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct FeedbackFooterHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}
