import SwiftUI

private enum FeedbackTokens {
    static let nanosecondsPerMillisecond: UInt64 = 1_000_000
    static let desktopInset: CGFloat = 32
    static let mobileInset: CGFloat = 20
    static let dialogWidth: CGFloat = 400
    static let notificationWidth: CGFloat = 320
    static let dialogPadding: CGFloat = 24
    static let dialogGap: CGFloat = 16
    static let headerGap: CGFloat = 12
    static let actionGap: CGFloat = 12
    static let titleSize: CGFloat = 24
    static let messageSize: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let toastVerticalPadding: CGFloat = 12
    static let toastHorizontalPadding: CGFloat = 16
    static let iconContainerSize: CGFloat = 28
    static let contentPadding: CGFloat = 12
    static let metaGap: CGFloat = 8
    static let metaLabelWidth: CGFloat = 72
    static let metaLabelSize: CGFloat = 12
    static let metaValueSize: CGFloat = 13
}

public struct FeedbackHost: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let feedback: UiFeedback?
    let onDismiss: (UInt64) -> Void
    let onAction: (UInt64, String) -> Void

    public init(
        feedback: UiFeedback?,
        onDismiss: @escaping (UInt64) -> Void,
        onAction: @escaping (UInt64, String) -> Void
    ) {
        self.feedback = feedback
        self.onDismiss = onDismiss
        self.onAction = onAction
    }

    public var body: some View {
        if let feedback {
            GeometryReader { geo in
                let inset = horizontalSizeClass == .compact
                    ? FeedbackTokens.mobileInset
                    : FeedbackTokens.desktopInset
                let availableWidth = max(geo.size.width - inset * 2, 0)
                let availableHeight = max(geo.size.height - inset * 2, 0)
                ZStack {
                    if feedback.mode == .dialog && feedback.modal {
                        EduColors.surface.opacity(0.50)
                            .background(.ultraThinMaterial)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if feedback.dismissOnBackdrop { onDismiss(feedback.id) }
                            }
                    }
                    positioned(feedback) {
                        switch feedback.mode {
                        case .toast:
                            toast(feedback)
                                .frame(maxWidth: availableWidth)
                        case .dialog:
                            dialog(
                                feedback,
                                maxWidth: min(FeedbackTokens.dialogWidth, availableWidth),
                                maxHeight: availableHeight
                            )
                        case .notification:
                            notification(feedback)
                                .frame(maxWidth: min(FeedbackTokens.notificationWidth, availableWidth))
                        }
                    }
                    .padding(inset)
                }
            }
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .task(id: feedback.id) {
                guard let durationMs = feedback.autoDismissMs, durationMs > 0 else { return }
                try? await Task.sleep(
                    nanoseconds: durationMs * FeedbackTokens.nanosecondsPerMillisecond
                )
                guard !Task.isCancelled else { return }
                onDismiss(feedback.id)
            }
        }
    }

    @ViewBuilder
    private func positioned<Content: View>(
        _ feedback: UiFeedback,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack {
            if feedback.mode == .dialog { Spacer() }
            HStack {
                if feedback.mode == .notification { Spacer() }
                content()
            }
            if feedback.mode != .dialog { Spacer() }
            if feedback.mode == .dialog { Spacer() }
        }
    }

    private func toast(_ feedback: UiFeedback) -> some View {
        HStack(spacing: 12) {
            EduIcon(EduIcons.check, size: 14, filled: true, tint: EduColors.onSecondaryContainer)
                .frame(width: FeedbackTokens.iconContainerSize, height: FeedbackTokens.iconContainerSize)
                .background(EduColors.secondaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusFull))
            Text(feedback.message)
                .font(EduFont.title)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if feedback.dismissible {
                Button { onDismiss(feedback.id) } label: {
                    EduIcon(EduIcons.close, size: 18, tint: EduColors.onSurfaceVariant)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, FeedbackTokens.toastHorizontalPadding)
        .padding(.vertical, FeedbackTokens.toastVerticalPadding)
        .feedbackCard(level: .level2)
    }

    private func dialog(
        _ feedback: UiFeedback,
        maxWidth: CGFloat,
        maxHeight: CGFloat
    ) -> some View {
        FeedbackFittingScroll(maxHeight: maxHeight) {
            VStack(alignment: .leading, spacing: FeedbackTokens.dialogGap) {
                HStack(alignment: .top, spacing: FeedbackTokens.headerGap) {
                    EduIcon(EduIcons.warning, size: 24, filled: true, tint: EduColors.error)
                    Text(feedback.title)
                        .font(EduFont.sans(FeedbackTokens.titleSize, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(feedback.message)
                    .font(EduFont.sans(FeedbackTokens.messageSize))
                    .foregroundStyle(EduColors.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let diagnostic = feedback.diagnostic {
                    diagnosticBlock(diagnostic)
                }
                HStack(spacing: FeedbackTokens.actionGap) {
                    Spacer(minLength: 0)
                    ForEach(feedback.actions) { action in
                        actionButton(action, feedbackId: feedback.id)
                    }
                }
            }
            .padding(FeedbackTokens.dialogPadding)
            .frame(width: maxWidth, alignment: .leading)
        }
        .feedbackCard(level: .level3)
    }

    private func notification(_ feedback: UiFeedback) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                HStack(alignment: .top, spacing: 8) {
                    EduIcon(notificationIcon(feedback.tone), size: 20, filled: true, tint: toneColor(feedback.tone))
                    Text(feedback.title)
                        .font(EduFont.title)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if feedback.dismissible {
                    Button { onDismiss(feedback.id) } label: {
                        EduIcon(EduIcons.close, size: 18, tint: EduColors.onSurfaceVariant)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(feedback.message)
                .font(EduFont.sans(14))
                .foregroundStyle(EduColors.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(FeedbackTokens.contentPadding)
                .background(EduColors.surfaceBright)
                .clipShape(RoundedRectangle(cornerRadius: EduDimens.radius))
                .overlay(
                    RoundedRectangle(cornerRadius: EduDimens.radius)
                        .stroke(EduColors.surfaceHigh, lineWidth: 1)
                )
            ForEach(feedback.actions) { action in
                actionButton(action, feedbackId: feedback.id)
                    .frame(maxWidth: feedback.actions.count == 1 ? .infinity : nil)
            }
        }
        .padding(FeedbackTokens.cardPadding)
        .frame(maxWidth: FeedbackTokens.notificationWidth)
        .feedbackCard(level: .level3)
    }

    @ViewBuilder
    private func diagnosticBlock(_ diagnostic: FeedbackDiagnostic) -> some View {
        let rows: [(String, String)] = [
            diagnostic.code.isEmpty ? nil : (EduI18n.text("feedbackDiagCode"), diagnostic.code),
            diagnostic.message.flatMap { $0.isEmpty ? nil : (EduI18n.text("feedbackDiagMessage"), $0) },
            diagnostic.traceId.flatMap { $0.isEmpty ? nil : (EduI18n.text("feedbackDiagTraceId"), $0) },
        ].compactMap { $0 }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: FeedbackTokens.metaGap) {
                ForEach(rows, id: \.0) { label, value in
                    HStack(alignment: .top, spacing: FeedbackTokens.metaGap) {
                        Text(label)
                            .font(EduFont.sans(FeedbackTokens.metaLabelSize, weight: .semibold))
                            .foregroundStyle(EduColors.onSurfaceVariant)
                            .frame(width: FeedbackTokens.metaLabelWidth, alignment: .leading)
                        Text(value)
                            .font(EduFont.sans(FeedbackTokens.metaValueSize))
                            .foregroundStyle(EduColors.onSurface)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(FeedbackTokens.contentPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(EduColors.surfaceBright)
            .clipShape(RoundedRectangle(cornerRadius: EduDimens.radius))
            .overlay(
                RoundedRectangle(cornerRadius: EduDimens.radius)
                    .stroke(EduColors.surfaceHigh, lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private func actionButton(_ action: FeedbackAction, feedbackId: UInt64) -> some View {
        let button = Button(action.label) { onAction(feedbackId, action.id) }
            .buttonStyle(.plain)
            .font(EduFont.sans(14, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        switch action.style {
        case .text:
            button.foregroundStyle(EduColors.primary)
        case .primary:
            button
                .foregroundStyle(EduColors.onPrimary)
                .background(EduColors.primary)
                .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
        case .danger:
            button
                .foregroundStyle(EduColors.onError)
                .background(EduColors.error)
                .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
        }
    }

    private func toneColor(_ tone: FeedbackTone) -> Color {
        switch tone {
        case .info: return EduColors.secondary
        case .success: return EduColors.success
        case .warning: return EduColors.warning
        case .error: return EduColors.error
        }
    }

    private func notificationIcon(_ tone: FeedbackTone) -> String {
        switch tone {
        case .info: return EduIcons.pending
        case .success: return EduIcons.checkCircle
        case .warning, .error: return EduIcons.warning
        }
    }
}

private struct FeedbackContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct FeedbackFittingScroll<Content: View>: View {
    let maxHeight: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content()
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: FeedbackContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
        }
        .onPreferenceChange(FeedbackContentHeightKey.self) { contentHeight = $0 }
        .frame(height: contentHeight > 0 ? min(contentHeight, maxHeight) : nil)
    }
}

private extension View {
    func feedbackCard(level: EduElevation) -> some View {
        background(EduColors.surfaceLowest)
            .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous)
                    .stroke(EduColors.surfaceHigh, lineWidth: 1)
            )
            .eduShadow(level)
    }
}
