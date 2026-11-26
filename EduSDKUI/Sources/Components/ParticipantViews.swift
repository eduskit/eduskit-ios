import SwiftUI

enum VideoLiveBadgeTokens {
    static let inset: CGFloat = 8
    static let paddingH: CGFloat = 6
    static let paddingV: CGFloat = 2
    static let fontSize: CGFloat = 8
    static let tracking: CGFloat = 0.5
}

struct VideoLiveBadge: View {
    var body: some View {
        Text(EduI18n.text("videoLiveBadge"))
            .font(EduFont.sans(VideoLiveBadgeTokens.fontSize, weight: .bold))
            .tracking(VideoLiveBadgeTokens.tracking)
            .foregroundStyle(EduColors.onLive)
            .padding(.horizontal, VideoLiveBadgeTokens.paddingH)
            .padding(.vertical, VideoLiveBadgeTokens.paddingV)
            .background(EduColors.live, in: Capsule())
    }
}

struct ParticipantVideoTile: View {
    let participant: ClassroomParticipant
    var compact: Bool = false
    var featured: Bool = false
    /// 不可见时卸槽，避免侧栏收起仍拉远端视频。
    var bindVideo: Bool = true
    var showLiveBadge: Bool = false
    var fixedWidth: CGFloat? = nil
    @Environment(\.liveUiSnapshot) private var liveSnapshot

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 阴影只能挂在背景 shape 上，不能包住 RtcVideoSlotView：
            // SwiftUI `.clipShape` / `.shadow` 会离屏拍图，TRTC Metal 层会被拍成空白。
            RoundedRectangle(cornerRadius: MobileClassroomTokens.cardRadius)
                .fill(EduColors.surfaceHighest)
                .eduShadow(.soft)
            let avatarSize = featured
                ? EduDimens.tileAvatarSizeFeatured
                : (compact ? EduDimens.tileAvatarSizeCompact : EduDimens.tileAvatarSize)
            CenteredTileAvatar(avatarUrl: participant.avatarUrl, size: avatarSize)
            let liveName = liveSnapshot.flatMap { LiveStreams.byUser($0)[participant.id] }
            let showCamera = showsParticipantCameraSurface(videoMuted: participant.videoMuted)
            if let liveName, showsParticipantLiveSurface(liveStreamName: liveName) {
                LiveVideoSlotView(streamName: liveName, cornerRadius: MobileClassroomTokens.cardRadius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                if !showCamera {
                    EduColors.surfaceHighest.frame(maxWidth: .infinity, maxHeight: .infinity)
                    CenteredTileAvatar(avatarUrl: participant.avatarUrl, size: avatarSize)
                }
            } else if showCamera, bindVideo {
                RtcVideoSlotView(userId: participant.id, cornerRadius: MobileClassroomTokens.cardRadius)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            VStack {
                HStack {
                    Text(participant.displayName).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                        .padding(.horizontal, 6).padding(.vertical, 2).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
                    Spacer(minLength: 0)
                }
                Spacer(minLength: 0)
                HStack(spacing: 4) {
                    EduIcon(participant.audioMuted ? EduIcons.micOff : EduIcons.mic, size: 14, tint: participant.audioMuted ? Color(hex: 0xFF6B8A) : .white)
                        .frame(width: 24, height: 24).background(.black.opacity(0.45), in: Circle())
                    EduIcon(participant.videoMuted ? EduIcons.videocamOff : EduIcons.videocam, size: 14, tint: .white)
                        .frame(width: 24, height: 24).background(.black.opacity(0.45), in: Circle())
                    Spacer(minLength: 0)
                }
            }.padding(compact ? 8 : 6)
        }
        .overlay(alignment: .topTrailing) {
            if showLiveBadge {
                VideoLiveBadge()
                    .padding(VideoLiveBadgeTokens.inset)
            }
        }
        .aspectRatio(16 / 9, contentMode: featured ? .fill : .fit)
        .frame(
            maxWidth: featured ? .infinity : nil,
            maxHeight: featured ? .infinity : nil
        )
        .frame(width: featured ? nil : (fixedWidth ?? (compact ? EduDimens.bloomCardW : EduDimens.videoTileW)))
    }
}

struct ParticipantListItemView: View {
    let participant: ClassroomParticipant
    var dense: Bool = false
    var hostId: String? = nil
    var onClick: (() -> Void)? = nil

    private var isHost: Bool {
        if let hostId { return participant.id == hostId }
        return (participant.roleLabel ?? "").lowercased() == "host"
    }

    private var roleText: String {
        isHost ? EduI18n.text("roleHost") : (participant.roleLabel ?? "")
    }

    var body: some View {
        // Web `.edu-plist__item` pad 8; `.edu-plist__person` gap 16.
        HStack(spacing: dense ? 12 : 16) {
            ZStack(alignment: .bottomTrailing) {
                RemoteAvatarImage(avatarUrl: participant.avatarUrl)
                    .frame(width: 40, height: 40)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(EduColors.surfaceLow, lineWidth: 2))
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 0) {
                Text(participant.displayName)
                    .font(EduFont.sans(14, weight: .bold))
                    .foregroundStyle(EduColors.onSurface)
                    .lineLimit(1)
                if !roleText.isEmpty {
                    Text(isHost ? roleText.uppercased() : roleText)
                        .font(EduFont.sans(10, weight: isHost ? .bold : .regular))
                        .foregroundStyle(isHost ? EduColors.primary : EduColors.onSurfaceVariant)
                }
            }
            Spacer(minLength: 0)
            if onClick != nil {
                EduIcon(EduIcons.chevronRight, size: 18, tint: EduColors.onSurfaceVariant)
            }
        }
        .padding(dense ? 0 : 8)
        .contentShape(Rectangle())
        .onTapGesture { onClick?() }
    }
}

struct ParticipantStripView: View {
    let participants: [ClassroomParticipant]
    var vertical: Bool = false
    var namespace: Namespace.ID? = nil
    var bindVideo: Bool = true
    var showLiveBadge: Bool = false

    var body: some View {
        Group {
            if vertical {
                VStack(spacing: EduDimens.videoGap) {
                    ForEach(participants) { p in
                        tile(p).frame(maxWidth: .infinity)
                    }
                }
                .padding(EduDimens.stackSm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: EduDimens.videoGap) {
                        ForEach(participants) { p in
                            tile(p)
                        }
                    }
                    .padding(.horizontal, EduDimens.stackMd)
                }
                .frame(height: EduDimens.stripHeight)
            }
        }
    }

    @ViewBuilder
    private func tile(_ p: ClassroomParticipant) -> some View {
        if let namespace {
            ParticipantVideoTile(participant: p, bindVideo: bindVideo, showLiveBadge: showLiveBadge)
                .matchedGeometryEffect(id: p.id, in: namespace, properties: .frame, anchor: .center, isSource: true)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        } else {
            ParticipantVideoTile(participant: p, bindVideo: bindVideo, showLiveBadge: showLiveBadge)
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        }
    }
}
