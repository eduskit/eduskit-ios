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

    private var initials: String {
        if let initials = participant.initials { return initials }
        let parts = participant.displayName.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)) }.joined()
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // 阴影只能挂在背景 shape 上，不能包住 RtcVideoSlotView：
            // SwiftUI `.clipShape` / `.shadow` 会离屏拍图，TRTC Metal 层会被拍成空白。
            RoundedRectangle(cornerRadius: EduDimens.radiusXl)
                .fill(EduColors.surfaceHighest)
                .eduShadow(.soft)
            CenteredTileAvatar(
                avatarUrl: participant.avatarUrl,
                initials: initials,
                size: featured
                    ? EduDimens.tileAvatarSizeFeatured
                    : (compact ? EduDimens.tileAvatarSizeCompact : EduDimens.tileAvatarSize),
                fontSize: featured
                    ? EduDimens.tileAvatarFontFeatured
                    : (compact ? EduDimens.tileAvatarFontCompact : EduDimens.tileAvatarFont)
            )
            if bindVideo {
                RtcVideoSlotView(userId: participant.id, cornerRadius: EduDimens.radiusXl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            HStack(spacing: 4) {
                if participant.audioMuted {
                    EduIcon(EduIcons.micOff, size: 12, tint: EduColors.error)
                }
                if participant.videoMuted {
                    EduIcon(EduIcons.videocamOff, size: 12, tint: EduColors.error)
                }
                Text(participant.displayName.uppercased())
                    .font(EduFont.sans(10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(8)
        }
        .overlay(alignment: .bottomTrailing) {
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
        .frame(width: featured ? nil : (compact ? EduDimens.bloomCardW : EduDimens.videoTileW))
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
                RemoteAvatarImage(avatarUrl: participant.avatarUrl) {
                    Text(participant.initials ?? String(participant.displayName.prefix(2)).uppercased())
                        .font(EduFont.sans(14, weight: .bold))
                        .foregroundStyle(EduColors.onSurfaceVariant)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(EduColors.surfaceHigh)
                }
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
