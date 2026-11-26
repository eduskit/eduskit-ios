import SwiftUI
import EduSDK

// MARK: - Landscape header (full-width, standard phone-style bar)

/// Landscape header — same visual language as the phone portrait header
/// (`ClassroomHeaderView.phoneHeader`), plus an inline orientation toggle in
/// the trailing action group. Slides off-screen when idle via `.eduIdleAutoSlide`.
struct LandscapeGlassHeader: View {
    let snapshot: UiSnapshot
    let title: String
    let elapsedLabel: String
    @ObservedObject var orientation: OrientationController
    let effectiveLandscape: Bool
    var onOpenSettings: () -> Void
    var onBack: () -> Void
    var onInteract: () -> Void = {}

    private var statusLabel: String {
        switch snapshot.initStatus {
        case .loading: return EduI18n.text("statusConnecting")
        case .error: return EduI18n.text("statusError")
        case .ready: return snapshot.badgeText.isEmpty ? EduI18n.text("statusInProgress") : snapshot.badgeText
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    EduIcon(EduIcons.arrowBack, size: 18, tint: EduColors.onSurface)
                        .padding(4)
                }
                .buttonStyle(EduPressButtonStyle())
                Rectangle()
                    .fill(EduColors.outlineVariant)
                    .frame(width: 1, height: 16)
                    .padding(.horizontal, 4)
                Text(EduI18n.text("brandNameShort"))
                    .font(EduFont.sans(18, weight: .bold))
                    .foregroundStyle(EduColors.onSurface)
            }

            HStack(spacing: 8) {
                Text(title)
                    .font(EduFont.sans(13, weight: .semibold))
                    .tracking(0.26)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(statusLabel.uppercased())
                    .font(EduFont.sans(9, weight: .semibold))
                    .foregroundStyle(EduColors.onSecondaryContainer)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(EduColors.secondaryContainer)
                    .clipShape(Capsule())
                    .fixedSize()
                if !elapsedLabel.isEmpty {
                    Text(elapsedLabel)
                        .font(EduFont.sans(11, weight: .semibold))
                        .foregroundStyle(EduColors.secondary)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            HStack(spacing: 4) {
                OrientationToggleButton(
                    controller: orientation,
                    effectiveLandscape: effectiveLandscape,
                    onInteract: onInteract
                )
                Button {} label: {
                    EduIcon(EduIcons.notifications, size: 20, tint: EduColors.secondary)
                        .padding(8)
                }
                .buttonStyle(EduPressButtonStyle())
                Button(action: onOpenSettings) {
                    EduIcon(EduIcons.settings, size: 20, tint: EduColors.secondary)
                        .padding(8)
                }
                .buttonStyle(EduPressButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, minHeight: EduDimens.headerHeightPhone)
        .background(EduColors.surfaceLowest)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EduColors.surfaceLow).frame(height: 1)
        }
    }
}

// MARK: - Landscape glass bottom bar (floating pill)

/// 横屏浮层底栏 token。
private enum LandscapeChromeTokens {
    static let stackSpacing: CGFloat = 8
    static let popupOffsetY: CGFloat = 8
    static let popupAnimDuration: Double = 0.18
    static let barAnimDuration: Double = 0.2
    static let iconSpacing: CGFloat = 4
    static let barHorizontalPadding: CGFloat = 10
    static let barVerticalPadding: CGFloat = 6
    static let pillCornerRadius: CGFloat = 28
    static let dividerWidth: CGFloat = 1
    static let dividerHeight: CGFloat = 24
    static let dividerHorizontalPadding: CGFloat = 2
    static let iconButtonWidth: CGFloat = 44
    static let iconButtonHeight: CGFloat = 40
    static let iconSize: CGFloat = 20
    static let iconCornerRadius: CGFloat = 12
    /// 无 Home Indicator 时浮层底栏与屏幕底边的最小间隙。
    static let minBottomGap: CGFloat = 8
}

struct LandscapeGlassBottomBar: View {
    let videoLayout: VideoLayout
    let videoWallOpen: Bool
    let drawerOpen: Bool
    let coursewareOpen: Bool
    /// 由全屏 GeometryReader 传入；横屏 Home Indicator 较矮时仍保留最小浮层间隙。
    var bottomInset: CGFloat = 0
    var onVideoLayout: (VideoLayout) -> Void
    var onToggleVideoWall: () -> Void
    var onToggleDrawer: () -> Void
    var onToggleCourseware: () -> Void
    var onEnd: () -> Void
    var onRequestInteraction: (String) -> Void = { _ in }
    var audioMuted: Bool = true
    var videoMuted: Bool = true
    var onToggleMicrophone: () -> Void = {}
    var onToggleCamera: () -> Void = {}
    var toolbarEntries: [String: ToolbarEntry] = [:]
    var handRaised: Bool = false
    var localScreenSharing: Bool = false
    var onToggleHand: () -> Void = {}
    var onToggleScreenShare: () -> Void = {}
    var showCourseware: Bool = true
    var canEndClass: Bool = false
    var onInteract: () -> Void = {}

    private var micOn: Bool { !audioMuted }
    private var camOn: Bool { !videoMuted }
    // 可见性与可用性全部来自 Core 的 interaction_policy。
    private var mic: ToolbarEntry { toolbarEntries.entry("use_microphone") }
    private var camera: ToolbarEntry { toolbarEntries.entry("use_camera") }
    private var raiseHand: ToolbarEntry { toolbarEntries.entry("raise_hand") }
    private var share: ToolbarEntry { toolbarEntries.entry("share_screen") }
    private var courseware: ToolbarEntry { toolbarEntries.entry("operate_courseware") }
    @State private var layoutOpen = false

    private var resolvedBottomPadding: CGFloat {
        max(bottomInset, LandscapeChromeTokens.minBottomGap)
    }

    var body: some View {
        VStack(spacing: LandscapeChromeTokens.stackSpacing) {
            if layoutOpen {
                LayoutPopupView(selected: videoLayout) { picked in
                    onVideoLayout(picked)
                    withAnimation(.easeOut(duration: LandscapeChromeTokens.popupAnimDuration)) {
                        layoutOpen = false
                    }
                }
                .transition(
                    .opacity.combined(with: .offset(y: LandscapeChromeTokens.popupOffsetY))
                )
            }

            HStack(spacing: LandscapeChromeTokens.iconSpacing) {
                if mic.visible {
                    iconBtn(icon: micOn ? EduIcons.mic : EduIcons.micOff, off: !micOn, enabled: !mic.disabled, description: restrictedLabel(EduI18n.text("controlMic"), mic)) {
                        onToggleMicrophone(); onInteract()
                    }
                }
                if camera.visible {
                    iconBtn(icon: camOn ? EduIcons.videocam : EduIcons.videocamOff, off: !camOn, enabled: !camera.disabled, description: restrictedLabel(EduI18n.text("controlCamera"), camera)) {
                        onToggleCamera(); onInteract()
                    }
                }
                divider

                iconBtn(icon: EduIcons.group, active: drawerOpen) {
                    onToggleDrawer(); onInteract()
                }
                if showCourseware && courseware.visible {
                    iconBtn(icon: EduIcons.description, active: coursewareOpen, enabled: !courseware.disabled, description: restrictedLabel(EduI18n.text("controlSlides"), courseware)) {
                        onToggleCourseware(); onInteract()
                    }
                }
                divider

                if raiseHand.visible {
                    iconBtn(icon: EduIcons.frontHand, active: handRaised, enabled: !raiseHand.disabled, description: restrictedLabel(EduI18n.text("controlRaiseHand"), raiseHand)) {
                        onToggleHand(); onInteract()
                    }
                }
                if share.visible {
                    iconBtn(icon: EduIcons.screenShare, active: localScreenSharing, enabled: !share.disabled, description: restrictedLabel(EduI18n.text("controlShare"), share)) {
                        onToggleScreenShare(); onInteract()
                    }
                }
                iconBtn(icon: EduIcons.viewAgenda, active: layoutOpen) {
                    withAnimation(.easeOut(duration: LandscapeChromeTokens.popupAnimDuration)) {
                        layoutOpen.toggle()
                    }
                    onInteract()
                }
                iconBtn(icon: EduIcons.gridView, active: videoWallOpen) {
                    onToggleVideoWall(); onInteract()
                }
                divider

                iconBtn(
                    icon: EduIcons.callEnd,
                    danger: true,
                    description: EduI18n.text(canEndClass ? "controlEnd" : "controlLeave")
                ) { onEnd() }
            }
            .padding(.horizontal, LandscapeChromeTokens.barHorizontalPadding)
            .padding(.vertical, LandscapeChromeTokens.barVerticalPadding)
            .eduGlass(
                cornerRadius: LandscapeChromeTokens.pillCornerRadius,
                borderColor: EduTint.outlineVariant45,
                tier: .level3
            )
        }
        .padding(.bottom, resolvedBottomPadding)
        .frame(maxWidth: .infinity)
        .animation(
            .easeOut(duration: LandscapeChromeTokens.barAnimDuration),
            value: layoutOpen
        )
    }

    private var divider: some View {
        Rectangle()
            .fill(EduTint.outlineVariant30)
            .frame(
                width: LandscapeChromeTokens.dividerWidth,
                height: LandscapeChromeTokens.dividerHeight
            )
            .padding(.horizontal, LandscapeChromeTokens.dividerHorizontalPadding)
    }

    @ViewBuilder
    private func iconBtn(
        icon: String,
        active: Bool = false,
        off: Bool = false,
        danger: Bool = false,
        enabled: Bool = true,
        description: String? = nil,
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
        Button(action: action) {
            EduIcon(icon, size: LandscapeChromeTokens.iconSize, tint: tint)
                .frame(
                    width: LandscapeChromeTokens.iconButtonWidth,
                    height: LandscapeChromeTokens.iconButtonHeight
                )
                .background(bg)
                .clipShape(RoundedRectangle(
                    cornerRadius: LandscapeChromeTokens.iconCornerRadius,
                    style: .continuous
                ))
        }
        .buttonStyle(EduPressButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(Text(description ?? icon))
    }
}

// MARK: - Orientation toggle (flat icon button, embedded in header actions)

struct OrientationToggleButton: View {
    @ObservedObject var controller: OrientationController
    let effectiveLandscape: Bool
    var onInteract: () -> Void = {}

    private var icon: String {
        switch controller.mode {
        case .auto: return EduIcons.screenRotation
        case .lockedLandscape: return EduIcons.stayCurrentLandscape
        case .lockedPortrait: return EduIcons.stayCurrentPortrait
        }
    }

    private var accessibilityText: String {
        switch controller.mode {
        case .auto: return effectiveLandscape ? EduI18n.text("ariaLockLandscape") : EduI18n.text("ariaLockPortrait")
        case .lockedLandscape, .lockedPortrait: return EduI18n.text("ariaAutoRotate")
        }
    }

    var body: some View {
        Button {
            controller.toggle(currentIsLandscape: effectiveLandscape)
            onInteract()
        } label: {
            EduIcon(icon, size: 20, tint: EduColors.secondary)
                .padding(8)
        }
        .buttonStyle(EduPressButtonStyle())
        .accessibilityLabel(Text(accessibilityText))
    }
}

// MARK: - Right side drawer (overlay + scrim + panel)

struct RightSideDrawer: View {
    let toolsPanel: () -> AnyView
    let members: [ClassroomDirectoryMember]
    var onStageUsers: [StageUser] = []
    var membersNextCursor: String? = nil
    var membersLoading: Bool = false
    var onLoadMoreMembers: () -> Void = {}
    var onLoadMemberActions: (String, @escaping ([MemberActionAvailability]) -> Void) -> Void = { _, callback in callback([]) }
    var onMemberAction: (String, String, @escaping () -> Void) -> Void = { _, _, done in done() }
    let messages: [ClassroomChatMessageView]
    let currentUserId: String
    let onSendMessage: (String) async -> Bool
    var sendPermissionDenied: Bool = false
    @Binding var open: Bool
    @Binding var tab: Int
    var width: CGFloat = 340

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(open ? 0.35 : 0)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.modal)) {
                        open = false
                    }
                }
                .allowsHitTesting(open)

            if open {
                MobileTabPanelView(
                        toolsPanel: toolsPanel,
                    members: members,
                    onStageUsers: onStageUsers,
                    membersNextCursor: membersNextCursor,
                    membersLoading: membersLoading,
                    onLoadMoreMembers: onLoadMoreMembers,
                    onLoadMemberActions: onLoadMemberActions,
                    onMemberAction: onMemberAction,
                    messages: messages,
                    currentUserId: currentUserId,
                    onSendMessage: onSendMessage,
                    sendPermissionDenied: sendPermissionDenied,
                    selectedTab: tab,
                    onTabChange: { tab = $0 }
                )
                .frame(width: width)
                .frame(maxHeight: .infinity)
                .background(EduColors.surfaceLowest)
                .overlay(alignment: .leading) {
                    Rectangle().fill(EduColors.surfaceVariant).frame(width: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 20, x: -6, y: 0)
                .transition(.move(edge: .trailing))
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            if value.translation.width > 60 {
                                withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.modal)) {
                                    open = false
                                }
                            }
                        }
                )
            }
        }
        .animation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.modal), value: open)
    }
}
