import SwiftUI
import EduSDK

struct MobileSpeakerPipView: View {
    let participant: ClassroomParticipant?
    var expanded: Bool = false
    var stageCount: Int = 0
    var onClick: () -> Void

    var body: some View {
        if let participant {
            let shortName: String = {
                let first = participant.displayName.split(separator: " ").first.map(String.init) ?? participant.displayName
                return String(first.prefix(8))
            }()
            let initials: String = {
                if let i = participant.initials { return i }
                return participant.displayName.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined()
            }()
            Button(action: onClick) {
                ZStack {
                    CenteredTileAvatar(
                        avatarUrl: participant.avatarUrl,
                        initials: initials,
                        size: EduDimens.tileAvatarSizePip,
                        fontSize: EduDimens.tileAvatarFontPip
                    )

                    VStack {
                        Spacer()
                        Text(shortName)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .background(Color.black.opacity(0.4))
                    }
                }
                .frame(width: EduDimens.pipSize, height: EduDimens.pipSize)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(expanded ? EduColors.primary : Color.white, lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(expanded ? 2 : 0)
                .overlay {
                    if expanded {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(EduColors.primary.opacity(0.35), lineWidth: 2)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if stageCount > 1 {
                        Text("\(stageCount)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .frame(height: 18)
                            .background(EduColors.primary)
                            .clipShape(Capsule())
                            .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                            .offset(x: 6, y: -6)
                    }
                }
            }
            .buttonStyle(EduPressButtonStyle())
            .scaleEffect(1)
        }
    }
}

struct MobileStageBloomView: View {
    let participants: [ClassroomParticipant]
    let visible: Bool
    var showLiveBadge: Bool = false
    var onDismiss: () -> Void

    private var cardH: CGFloat { EduDimens.bloomCardW * 9 / 16 }
    private var maxStackH: CGFloat { cardH * 3 + 10 * 2 }
    private var scrollable: Bool { participants.count > 3 }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            EduColors.scrim
                .opacity(visible ? 1 : 0)
                .ignoresSafeArea(edges: [])
                .onTapGesture { if visible { onDismiss() } }
                .allowsHitTesting(visible)

            if !participants.isEmpty {
                VStack(alignment: .trailing, spacing: 8) {
                    Button(action: onDismiss) {
                        HStack(spacing: 6) {
                            EduIcon(EduIcons.close, size: 14, tint: EduColors.onSurface)
                            Text(EduI18n.text("stageCount", ["count": participants.count]))
                                .font(EduFont.sans(12, weight: .semibold))
                        }
                        .foregroundStyle(EduColors.onSurface)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.white.opacity(0.92))
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    }
                    .buttonStyle(EduPressButtonStyle())
                    .scaleEffect(visible ? 1 : 0.72, anchor: .topTrailing)
                    .opacity(visible ? 1 : 0)
                    .offset(y: visible ? 0 : 12)
                    .allowsHitTesting(visible)

                    Group {
                        if scrollable {
                            ScrollView(.vertical, showsIndicators: false) {
                                cardStack
                            }
                            .frame(maxHeight: maxStackH)
                            .mask(
                                GeometryReader { geo in
                                    LinearGradient(
                                        stops: [
                                            .init(color: .black, location: 0),
                                            .init(color: .black, location: max(0, (geo.size.height - 28) / max(1, geo.size.height))),
                                            .init(color: .black.opacity(0), location: 1),
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    )
                                }
                            )
                        } else {
                            cardStack
                        }
                    }
                    .frame(width: EduDimens.bloomCardW)

                    if scrollable {
                        Text(EduI18n.text("stageBloomScrollMore"))
                            .font(EduFont.sans(10, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                            .opacity(visible ? 0.9 : 0)
                            .frame(maxWidth: .infinity)
                    }
                }
                .padding(.top, 228)
                .padding(.trailing, 12)
                .allowsHitTesting(visible)
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.bloom), value: visible)
        .allowsHitTesting(visible)
    }

    private var cardStack: some View {
        VStack(spacing: 10) {
            ForEach(Array(participants.enumerated()), id: \.element.id) { index, p in
                BloomCardView(participant: p, index: index, visible: visible, showLiveBadge: showLiveBadge)
            }
        }
    }
}

private struct BloomCardView: View {
    let participant: ClassroomParticipant
    let index: Int
    let visible: Bool
    var showLiveBadge: Bool = false
    @State private var progress: CGFloat = 0

    var body: some View {
        ZStack {
            CenteredTileAvatar(
                avatarUrl: participant.avatarUrl,
                initials: participant.initials
                    ?? participant.displayName.split(separator: " ").prefix(2).compactMap { $0.first.map(String.init) }.joined(),
                size: EduDimens.tileAvatarSizeCompact,
                fontSize: EduDimens.tileAvatarFontCompact
            )
            if visible {
                RtcVideoSlotView(userId: participant.id, cornerRadius: EduDimens.radius2xl)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Text(String(participant.displayName.split(separator: " ").first?.prefix(10) ?? Substring(participant.displayName)))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                )
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if showLiveBadge {
                VideoLiveBadge()
                    .padding(VideoLiveBadgeTokens.inset)
            }
        }
        .frame(width: EduDimens.bloomCardW, height: EduDimens.bloomCardW * 9 / 16)
        .background(
            RoundedRectangle(cornerRadius: EduDimens.radius2xl, style: .continuous)
                .fill(EduColors.surfaceHighest)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: EduDimens.radius2xl, style: .continuous)
                .stroke(Color.white, lineWidth: 2)
        )
        .scaleEffect(0.28 + 0.72 * progress, anchor: .topTrailing)
        .offset(x: 18 * (1 - progress), y: -8 * (1 - progress))
        .opacity(progress)
        .onAppear { sync(visible) }
        .onChange(of: visible) { sync($0) }
    }

    private func sync(_ open: Bool) {
        if open {
            progress = 0
            let delay = Double(index) * EduMotion.bloomStagger
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.bloom)) {
                    progress = 1
                }
            }
        } else {
            let delay = Double(max(0, 12 - index)) * EduMotion.bloomStagger * 0.45
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.bloom)) {
                    progress = 0
                }
            }
        }
    }
}

struct MobileTabPanelView: View {
    let members: [ClassroomMember]
    var onStageUsers: [StageUser] = []
    var membersNextCursor: String? = nil
    var membersLoading: Bool = false
    var onLoadMoreMembers: () -> Void = {}
    var onLoadMemberActions: (String, @escaping ([MemberActionAvailability]) -> Void) -> Void = { _, callback in callback([]) }
    var onMemberAction: (String, String, @escaping () -> Void) -> Void = { _, _, done in done() }
    let messages: [ImMessage]
    let currentUserId: String
    let onSendMessage: (String) -> Void
    var sendPermissionDenied: Bool = false
    var selectedTab: Int = 0
    var onTabChange: ((Int) -> Void)? = nil

    @State private var tab = 0
    @State private var selectedMember: ClassroomParticipant?
    @State private var selectedActions: [MemberActionAvailability] = []
    @State private var policyLoading = false
    @State private var actionLoading = false
    private let labels = [EduI18n.text("tabParticipantsZh"), EduI18n.text("tabChatZh"), EduI18n.text("tabToolsZh")]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                    let active = tab == i
                    Button {
                        tab = i
                        onTabChange?(i)
                    } label: {
                        VStack(spacing: 0) {
                            Text(label)
                                .font(EduFont.sans(14, weight: active ? .bold : .medium))
                                .foregroundStyle(active ? EduColors.primary : EduColors.onSurfaceVariant)
                            Rectangle()
                                .fill(active ? EduColors.primary : Color.clear)
                                .frame(height: 2)
                                .padding(.top, 10)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(EduPressButtonStyle())
                }
            }
            .background(EduColors.surface)
            .overlay(alignment: .bottom) {
                Rectangle().fill(EduColors.surfaceVariant).frame(height: 1)
            }

            Group {
                switch tab {
                case 0:
                    memberDirectoryList
                case 1:
                    ClassroomChatView(
                        messages: messages,
                        currentUserId: currentUserId,
                        onSendMessage: onSendMessage,
                        sendPermissionDenied: sendPermissionDenied
                    )
                default:
                    Text(EduI18n.text("tabToolsPlaceholder"))
                        .font(EduFont.sans(14))
                        .foregroundStyle(EduColors.onSurfaceVariant)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 32)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(EduColors.surfaceLowest)
        }
        .onAppear { tab = selectedTab }
        .onChange(of: selectedTab) { tab = $0 }
        .overlay(alignment: .bottom) {
            if let member = selectedMember {
                MemberActionsSheet(
                    memberName: member.displayName,
                    actions: selectedActions,
                    policyLoading: policyLoading,
                    actionLoading: actionLoading,
                    onClose: { selectedMember = nil },
                    onSelect: { action in
                        actionLoading = true
                        onMemberAction(action, member.id) {
                            actionLoading = false
                            selectedMember = nil
                        }
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var memberDirectoryList: some View {
        let columns = MemberColumns.split(onStageUsers: onStageUsers, members: members)
        if columns.onStage.isEmpty && columns.audience.isEmpty {
            Text(EduI18n.text("emptyParticipants"))
                .foregroundStyle(EduColors.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if !columns.onStage.isEmpty {
                        Text(EduI18n.text("sectionOnStage"))
                            .font(EduFont.sans(12, weight: .semibold))
                            .foregroundStyle(EduColors.onSurfaceVariant)
                        ForEach(columns.onStage, id: \.userId) { member in
                            ClassroomMemberCardView(member: member) {
                                selectedMember = participant(member)
                                selectedActions = []
                                policyLoading = true
                                onLoadMemberActions(member.userId) { selectedActions = $0; policyLoading = false }
                            }
                        }
                    }
                    if !columns.audience.isEmpty {
                        Text(EduI18n.text("sectionInAudience"))
                            .font(EduFont.sans(12, weight: .semibold))
                            .foregroundStyle(EduColors.onSurfaceVariant)
                        ForEach(columns.audience, id: \.userId) { member in
                            ClassroomMemberCardView(member: member) {
                                selectedMember = participant(member)
                                selectedActions = []
                                policyLoading = true
                                onLoadMemberActions(member.userId) { selectedActions = $0; policyLoading = false }
                            }
                        }
                    }
                    if membersNextCursor != nil || membersLoading {
                        Text(EduI18n.text(membersLoading ? "membersLoadingMore" : "membersLoadMore"))
                            .font(EduFont.sans(12))
                            .foregroundStyle(EduColors.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .onAppear {
                                if membersNextCursor != nil && !membersLoading {
                                    onLoadMoreMembers()
                                }
                            }
                    }
                }
                .padding(16)
            }
        }
    }
}

private struct ClassroomMemberCardView: View {
    let member: ClassroomMember
    var onClick: () -> Void = {}

    var body: some View {
        ClassroomMemberListItemView(member: member)
            .contentShape(Rectangle())
            .onTapGesture(perform: onClick)
            .padding(12)
            .background(EduColors.surfaceLowest)
            .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: EduDimens.radiusXl, style: .continuous)
                    .stroke(EduColors.surfaceVariant, lineWidth: 1)
            )
    }
}

private func participant(_ member: ClassroomMember) -> ClassroomParticipant {
    ClassroomParticipant(id: member.userId, displayName: member.displayName ?? member.userId, roleLabel: member.role, onStage: member.stageStatus == "on")
}

/// 成员页直接渲染 Headless SDK 的权威成员 DTO，不注入本地音视频模拟状态。
private struct ClassroomMemberListItemView: View {
    let member: ClassroomMember

    private var displayName: String {
        guard let value = member.displayName, !value.isEmpty else { return member.userId }
        return value
    }

    var body: some View {
        HStack(spacing: 12) {
            RemoteAvatarImage(avatarUrl: member.avatarUrl) {
                Text(String(displayName.prefix(2)).uppercased())
                    .font(EduFont.sans(14, weight: .bold))
                    .foregroundStyle(EduColors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(EduColors.surfaceHigh)
            }
                .frame(width: 40, height: 40)
                .clipShape(Circle())
                .overlay(Circle().stroke(EduColors.surfaceLow, lineWidth: 2))

            VStack(alignment: .leading, spacing: 0) {
                Text(displayName)
                    .font(EduFont.sans(14, weight: .bold))
                    .foregroundStyle(EduColors.onSurface)
                    .lineLimit(1)
                if let role = member.role, !role.isEmpty {
                    Text(role)
                        .font(EduFont.sans(10))
                        .foregroundStyle(EduColors.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            EduIcon(EduIcons.chevronRight, size: 18, tint: EduColors.onSurfaceVariant)
        }
    }
}

/// 竖屏底栏尺寸 / 间距 token（禁止魔法字面量散落）。
enum MobileBottomBarTokens {
    static let rowHorizontalPadding: CGFloat = 16
    static let rowVerticalPadding: CGFloat = 8
    static let navButtonHeight: CGFloat = 56
    static let moreSectionTopPadding: CGFloat = 16
    static let moreSectionBottomPadding: CGFloat = 32
    static let moreHorizontalPadding: CGFloat = 24
    static let moreTileSize: CGFloat = 48
    static let moreIconSize: CGFloat = 24
    static let topCornerRadius: CGFloat = 12
    static let shadowRadius: CGFloat = 20
    static let shadowYOffset: CGFloat = -4
    static let shadowOpacity: Double = 0.06
    static let dangerButtonWidth: CGFloat = 64
    static let navButtonWidth: CGFloat = 56
    static let navIconSize: CGFloat = 22
    static let navLabelSpacing: CGFloat = 2
    /// 折叠态内容高度（不含 Home Indicator）：上下 padding + 按钮行。
    static var estimatedCollapsedHeight: CGFloat {
        rowVerticalPadding * 2 + navButtonHeight
    }
}

struct MobileBottomBarView: View {
    let videoLayout: VideoLayout
    let videoWallOpen: Bool
    var coursewareOpen: Bool = false
    /// 由全屏 GeometryReader 传入的系统底部 inset（Home Indicator）。
    var bottomInset: CGFloat = 0
    var onVideoLayout: (VideoLayout) -> Void
    var onToggleVideoWall: () -> Void
    var onToggleCourseware: () -> Void = {}
    var onOpenChat: () -> Void = {}
    var onRequestInteraction: (String) -> Void = { _ in }
    var audioMuted: Bool = true
    var videoMuted: Bool = true
    var onToggleMicrophone: () -> Void = {}
    var onToggleCamera: () -> Void = {}
    var permissionDeniedActions: Set<String> = []
    var showCourseware: Bool = true
    var canEndClass: Bool = false
    var onEnd: () -> Void

    @State private var expanded = false
    private var micOn: Bool { !audioMuted }
    private var camOn: Bool { !videoMuted }
    private let handUp = false
    private let sharing = false
    @State private var layoutOpen = false

    private var topRadius: EduRoundedCorners {
        EduRoundedCorners(
            topLeading: MobileBottomBarTokens.topCornerRadius,
            bottomLeading: 0,
            bottomTrailing: 0,
            topTrailing: MobileBottomBarTokens.topCornerRadius
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            // Row first (matches Web DOM)
            HStack(spacing: 0) {
                navBtn(
                    icon: micOn ? EduIcons.mic : EduIcons.micOff,
                    label: permissionLabel(EduI18n.text("controlMic"), "use_microphone"),
                    off: !micOn,
                    enabled: !permissionDeniedActions.contains("use_microphone")
                ) { onToggleMicrophone() }
                navBtn(
                    icon: camOn ? EduIcons.videocam : EduIcons.videocamOff,
                    label: permissionLabel(EduI18n.text("settingsNavVideo"), "use_camera"),
                    off: !camOn,
                    enabled: !permissionDeniedActions.contains("use_camera")
                ) { onToggleCamera() }
                navBtn(
                    icon: expanded ? EduIcons.expandMore : EduIcons.expandLess,
                    label: expanded ? EduI18n.text("controlLess") : EduI18n.text("controlMore"),
                    active: expanded
                ) {
                    withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.floatExpand)) {
                        expanded.toggle()
                        if !expanded { layoutOpen = false }
                    }
                }
                navBtn(icon: EduIcons.chat, label: EduI18n.text("tabChat"), action: onOpenChat)
                navBtn(icon: EduIcons.callEnd, label: EduI18n.text(canEndClass ? "controlEnd" : "controlLeave"), danger: true, action: onEnd)
            }
            .padding(.horizontal, MobileBottomBarTokens.rowHorizontalPadding)
            .padding(.vertical, MobileBottomBarTokens.rowVerticalPadding)

            if expanded {
                VStack(spacing: 0) {
                    if layoutOpen {
                        LayoutPopupView(selected: videoLayout) {
                            onVideoLayout($0)
                            layoutOpen = false
                        }
                        .padding(.horizontal, MobileBottomBarTokens.rowHorizontalPadding)
                        .padding(.top, MobileBottomBarTokens.rowVerticalPadding)
                    }
                    HStack(spacing: MobileBottomBarTokens.rowHorizontalPadding) {
                        moreTile(icon: EduIcons.frontHand, label: EduI18n.text("controlRaiseHand"), active: handUp) {
                            onRequestInteraction("raise_hand")
                        }
                        moreTile(icon: EduIcons.screenShare, label: permissionLabel(EduI18n.text("controlShare"), "share_screen"), active: sharing, enabled: !permissionDeniedActions.contains("share_screen")) {
                            onRequestInteraction("share_screen")
                        }
                        if showCourseware {
                            moreTile(icon: EduIcons.description, label: EduI18n.text("controlSlides"), active: coursewareOpen, action: onToggleCourseware)
                        }
                        moreTile(icon: EduIcons.viewAgenda, label: EduI18n.text("controlLayout"), active: layoutOpen) { layoutOpen.toggle() }
                        moreTile(icon: EduIcons.gridView, label: EduI18n.text("videoWallTitle"), active: videoWallOpen, action: onToggleVideoWall)
                    }
                    .padding(.horizontal, MobileBottomBarTokens.moreHorizontalPadding)
                    .padding(.top, MobileBottomBarTokens.moreSectionTopPadding)
                    .padding(.bottom, MobileBottomBarTokens.moreSectionBottomPadding)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        // 控件抬离 Home Indicator；白底随 padding 铺到屏幕物理底边。
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
        .background(Color.white)
        .clipShape(topRadius)
        .shadow(
            color: .black.opacity(MobileBottomBarTokens.shadowOpacity),
            radius: MobileBottomBarTokens.shadowRadius,
            y: MobileBottomBarTokens.shadowYOffset
        )
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.floatExpand), value: expanded)
    }

    private func moreTile(
        icon: String,
        label: String,
        active: Bool,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                EduIcon(
                    icon,
                    size: MobileBottomBarTokens.moreIconSize,
                    tint: active ? EduColors.primary : EduColors.onSurface
                )
                .frame(
                    width: MobileBottomBarTokens.moreTileSize,
                    height: MobileBottomBarTokens.moreTileSize
                )
                .background(active ? EduColors.surfaceLow : EduColors.surfaceContainer)
                .clipShape(RoundedRectangle(
                    cornerRadius: MobileBottomBarTokens.topCornerRadius,
                    style: .continuous
                ))
                .eduShadow(active ? .soft : .level2)
                Text(label)
                    .font(EduFont.sans(11, weight: active ? .semibold : .medium))
                    .foregroundStyle(active ? EduColors.primary : EduColors.onSurfaceVariant)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(EduPressButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func navBtn(
        icon: String,
        label: String,
        active: Bool = false,
        danger: Bool = false,
        off: Bool = false,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        let tint: Color = {
            if danger { return EduColors.onError }
            if off { return EduColors.error }
            if active { return EduColors.primary }
            return EduColors.onSurfaceVariant
        }()
        let bg: Color = {
            if danger { return EduColors.error }
            if active { return EduColors.surfaceLow }
            if off { return EduTint.errorTint8 }
            return .clear
        }()
        return Button(action: action) {
            VStack(spacing: MobileBottomBarTokens.navLabelSpacing) {
                EduIcon(icon, size: MobileBottomBarTokens.navIconSize, tint: tint)
                Text(label)
                    .font(EduFont.sans(10, weight: danger ? .semibold : .medium))
                    .tracking(danger ? 0.5 : 0)
                    .foregroundStyle(tint)
            }
            .frame(
                width: danger ? MobileBottomBarTokens.dangerButtonWidth : MobileBottomBarTokens.navButtonWidth,
                height: MobileBottomBarTokens.navButtonHeight
            )
            .background(bg)
            .clipShape(RoundedRectangle(
                cornerRadius: MobileBottomBarTokens.topCornerRadius,
                style: .continuous
            ))
            .modifier(DangerShadow(enabled: danger))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(EduPressButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func permissionLabel(_ label: String, _ action: String) -> String {
        permissionDeniedActions.contains(action)
            ? "\(label) · \(EduI18n.text("permissionUnavailableShort"))"
            : label
    }
}

private struct DangerShadow: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.eduShadow(.md) } else { content }
    }
}
