import SwiftUI

/// Right-side overlay drawer used in phone-landscape layout.
///
/// Layout is a horizontal `[toggle handle][panel]`:
/// - **Toggle handle** — a pill-shaped button (rounded on the leading side,
///   flat on the trailing side) mirroring the Web `.edu-sidebar__toggle`
///   design. Always visible so users can reopen the panel after collapsing.
/// - **Panel** — participants stacked top-to-bottom in 16:9 tiles. Rendered
///   only when `open` is true; sliding in from the trailing edge.
///
/// The parent overlays this view on the whiteboard's trailing edge so the
/// collapsed toggle never reserves layout width.
struct LandscapeStageDrawer: View {
    static let panelWidth: CGFloat = 172
    /// Toggle handle column width — shared with landscape ContentCanvas `headerEndInset`.
    static let toggleWidth: CGFloat = 28

    let participants: [ClassroomParticipant]
    @Binding var open: Bool
    /// 横屏右侧刘海 / Dynamic Island 避让；计入抽屉列宽，开关不会压在不安全区上。
    var trailingSafeInset: CGFloat = 0
    var onInteract: () -> Void = {}
    var showLiveBadge: Bool = false

    private enum Tokens {
        static let panelWidth = LandscapeStageDrawer.panelWidth
        static let toggleColWidth = LandscapeStageDrawer.toggleWidth
        static let toggleHeight: CGFloat = 48
        static let cardWidth: CGFloat = 156
        static let toggleIconSize: CGFloat = 20
        static let emptyIconSize: CGFloat = 28
        static let emptySpacing: CGFloat = 8
        static let emptyHorizontalPadding: CGFloat = 12
        static let emptyHintFontSize: CGFloat = 11
    }

    var body: some View {
        HStack(spacing: 0) {
            toggleHandle
            if open {
                panel
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
            // 右侧不安全区占位：抽屉收起时开关仍在刘海左侧。
            if trailingSafeInset > 0 {
                Color.white
                    .frame(width: trailingSafeInset)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var toggleHandle: some View {
        let shape = EduRoundedCorners(
            topLeading: Tokens.toggleHeight / 2,
            bottomLeading: Tokens.toggleHeight / 2,
            bottomTrailing: 0,
            topTrailing: 0
        )
        return VStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.modal)) {
                    open.toggle()
                }
                onInteract()
            } label: {
                EduIcon(
                    open ? EduIcons.chevronRight : EduIcons.chevronLeft,
                    size: Tokens.toggleIconSize,
                    tint: EduColors.onSurfaceVariant
                )
                .frame(width: Tokens.toggleColWidth, height: Tokens.toggleHeight)
                .background(EduColors.surfaceLowest)
                .clipShape(shape)
                .overlay(shape.stroke(EduColors.surfaceLow, lineWidth: 1))
                .eduShadow(.soft)
            }
            .buttonStyle(EduPressButtonStyle())
            .accessibilityLabel(Text(open ? EduI18n.text("ariaCloseStage") : EduI18n.text("ariaOpenStage")))
            Spacer(minLength: 0)
        }
        .frame(width: Tokens.toggleColWidth)
        .frame(maxHeight: .infinity)
    }

    private var panel: some View {
        Group {
            if participants.isEmpty {
                VStack(spacing: Tokens.emptySpacing) {
                    EduIcon(
                        EduIcons.group,
                        size: Tokens.emptyIconSize,
                        tint: EduColors.outline
                    )
                    Text(EduI18n.text("stageEmpty"))
                        .font(EduFont.sans(14, weight: .semibold))
                        .foregroundStyle(EduColors.onSurface)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Tokens.emptyHorizontalPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(participants) { p in
                            StageTileView(participant: p, width: Tokens.cardWidth, showLiveBadge: showLiveBadge)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 10)
                }
            }
        }
        .frame(width: Tokens.panelWidth)
        .frame(maxHeight: .infinity)
        .background(EduColors.surfaceLowest)
        .overlay(alignment: .leading) {
            Rectangle().fill(EduColors.surfaceLow).frame(width: 1)
        }
    }
}

private struct StageTileView: View {
    let participant: ClassroomParticipant
    let width: CGFloat
    var showLiveBadge: Bool = false
    @Environment(\.liveUiSnapshot) private var liveSnapshot

    private enum Tokens {
        static let cornerRadius: CGFloat = 10
    }


    private var shortName: String {
        let first = participant.displayName.split(separator: " ").first.map(String.init) ?? participant.displayName
        return String(first.prefix(10))
    }

    var body: some View {
        ZStack {
            CenteredTileAvatar(
                avatarUrl: participant.avatarUrl,
                size: EduDimens.tileAvatarSizeCompact
            )
            let liveName = liveSnapshot.flatMap { LiveStreams.byUser($0)[participant.id] }
            let showCamera = showsParticipantCameraSurface(videoMuted: participant.videoMuted)
            if let liveName, showsParticipantLiveSurface(liveStreamName: liveName) {
                LiveVideoSlotView(streamName: liveName, cornerRadius: Tokens.cornerRadius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                if !showCamera {
                    EduColors.surfaceVariant.frame(maxWidth: .infinity, maxHeight: .infinity)
                    CenteredTileAvatar(
                        avatarUrl: participant.avatarUrl,
                        size: EduDimens.tileAvatarSizeCompact
                    )
                }
            } else if showCamera {
                RtcVideoSlotView(userId: participant.id, cornerRadius: Tokens.cornerRadius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                HStack(spacing: 4) {
                    if participant.audioMuted {
                        EduIcon(EduIcons.micOff, size: 12, tint: EduColors.error)
                    }
                    if participant.videoMuted {
                        EduIcon(EduIcons.videocamOff, size: 12, tint: EduColors.error)
                    }
                    Text(shortName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showLiveBadge {
                VideoLiveBadge()
                    .padding(VideoLiveBadgeTokens.inset)
            }
        }
        .frame(width: width, height: width * 9 / 16)
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.cornerRadius, style: .continuous)
                .stroke(EduColors.surfaceVariant, lineWidth: 1)
        )
    }
}
