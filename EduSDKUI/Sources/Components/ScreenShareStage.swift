import SwiftUI
import EduSDK

private enum ScreenShareStageTokens {
    static let captionPadding: CGFloat = 12
    static let captionSpacing: CGFloat = 6
    static let captionIconSize: CGFloat = 16
    static let captionFontSize: CGFloat = 13
}

/// 屏幕共享主舞台。
///
/// 只负责挂一个 screen 轨道的渲染槽；订阅与渲染由 Headless → RTC Adapter 完成，
/// 谁在共享由 Core 的 `screenShareUserIds` 决定，组件不做任何挑选逻辑。
struct ScreenShareStageView: View {
    let userId: String
    let displayName: String
    @Environment(\.liveUiSnapshot) private var liveSnapshot

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous)
                .fill(EduColors.surfaceLow)
            if let liveName = liveSnapshot.flatMap({ LiveStreams.auxStreamName($0, userId: userId) }) {
                LiveVideoSlotView(streamName: liveName)
            } else {
                RtcVideoSlotView(userId: userId, streamType: .screen)
            }
            HStack(spacing: ScreenShareStageTokens.captionSpacing) {
                EduIcon(
                    EduIcons.screenShare,
                    size: ScreenShareStageTokens.captionIconSize,
                    tint: EduColors.onSurface
                )
                Text(EduI18n.text("screenShareStageCaption", ["name": displayName]))
                    .font(EduFont.sans(ScreenShareStageTokens.captionFontSize, weight: .regular))
                    .foregroundStyle(EduColors.onSurface)
            }
            .padding(ScreenShareStageTokens.captionPadding)
        }
        .accessibilityElement(children: .combine)
    }
}
