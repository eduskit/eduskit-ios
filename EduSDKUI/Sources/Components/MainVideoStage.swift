import SwiftUI

private enum MainVideoStageTokens {
    static let waitingPadding: CGFloat = 24
    static let waitingIconSize: CGFloat = 32
    static let waitingStackSpacing: CGFloat = 8
    static let titleFontSize: CGFloat = 16
    static let hintFontSize: CGFloat = 13
}

struct MainVideoStageView: View {
    let teacher: ClassroomParticipant?
    var showLiveBadge: Bool = false
    @Environment(\.liveUiSnapshot) private var liveSnapshot

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous)
                .fill(EduColors.surfaceLow)
            if let teacher {
                ParticipantVideoTile(participant: teacher, featured: true, showLiveBadge: showLiveBadge)
                if let audioName = liveSnapshot.flatMap(LiveStreams.audioStreamName) {
                    LiveVideoSlotView(streamName: audioName)
                        .frame(width: 1, height: 1)
                        .opacity(0)
                        .allowsHitTesting(false)
                }
            } else {
                VStack(spacing: MainVideoStageTokens.waitingStackSpacing) {
                    EduIcon(
                        EduIcons.personOff,
                        size: MainVideoStageTokens.waitingIconSize,
                        tint: EduColors.outline
                    )
                    Text(EduI18n.text("teacherWaiting"))
                        .font(EduFont.sans(MainVideoStageTokens.titleFontSize, weight: .semibold))
                        .foregroundStyle(EduColors.onSurface)
                }
                .padding(MainVideoStageTokens.waitingPadding)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}
