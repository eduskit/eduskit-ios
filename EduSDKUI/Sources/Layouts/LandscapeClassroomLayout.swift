import SwiftUI
import EduSDK

/// Phone-landscape layout.
///
/// The whiteboard fills the safe viewport while the stage drawer overlays its
/// trailing edge, so the collapsed toggle never reserves a blank column.
///
/// 横屏水平 Safe Area 只避让**刘海所在一侧**，另一侧贴边充满以提高空间利用率。
struct LandscapeClassroomLayout: View {
    let snapshot: UiSnapshot
    let title: String
    let elapsedLabel: String
    @Binding var document: DemoDocument
    let members: [ClassroomMember]
    let stageParticipants: [ClassroomParticipant]
    let videoLayout: VideoLayout
    let videoWallOpen: Bool
    @ObservedObject var orientation: OrientationController
    var onOpenSettings: () -> Void
    var onOpenThumbnails: () -> Void
    var onFullscreen: () -> Void = {}
    var onVideoLayout: (VideoLayout) -> Void
    var onToggleVideoWall: () -> Void
    var onEnd: () -> Void
    var onBack: () -> Void
    var onSendMessage: (String) -> Void
    var onRefreshMembers: () -> Void
    var onLoadMoreMembers: () -> Void = {}
    var onLoadMemberActions: (String, @escaping ([MemberActionAvailability]) -> Void) -> Void = { _, callback in callback([]) }
    var onMemberAction: (String, String, @escaping () -> Void) -> Void = { _, _, done in done() }
    var coursewareOpen: Bool = false
    var onToggleCourseware: () -> Void = {}
    var onRequestInteraction: (String) -> Void = { _ in }
    var onToggleMicrophone: () -> Void = {}
    var onToggleCamera: () -> Void = {}
    var featuredTeacher: ClassroomParticipant? = nil

    @State private var stageOpen = true
    @State private var drawerOpen = false
    @State private var drawerTab = 0
    @StateObject private var activity = EduActivityTicker()

    private var chromeFadePaused: Bool { drawerOpen }
    private var videoMainStage: Bool { snapshot.isTeacherVideoMainStage() }

    var body: some View {
        GeometryReader { geo in
            let insets = EduSafeArea.merge(with: geo)
            // 按界面方向识别硬件顶部（刘海），只垫那一侧；对侧贴边充满。
            let horizontal = EduSafeArea.landscapeHorizontalPads(insets: insets)

            ZStack {
                Color.white

                mainArea(topInset: insets.top, bottomInset: insets.bottom)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.leading, horizontal.leading)
                    .padding(
                        .trailing,
                        horizontal.trailing + (stageOpen ? LandscapeStageDrawer.panelWidth : 0)
                    )
                    .animation(
                        .timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.modal),
                        value: stageOpen
                    )

                LandscapeStageDrawer(
                    participants: stageParticipants,
                    open: $stageOpen,
                    trailingSafeInset: horizontal.trailing,
                    onInteract: { activity.bump() },
                    showLiveBadge: snapshot.needLive
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .zIndex(LandscapeLayoutTokens.stageDrawerZIndex)

                RightSideDrawer(
                    members: members,
                    onStageUsers: snapshot.onStage,
                    membersNextCursor: snapshot.membersNextCursor,
                    membersLoading: snapshot.membersLoading,
                    onLoadMoreMembers: onLoadMoreMembers,
                    onLoadMemberActions: onLoadMemberActions,
                    onMemberAction: onMemberAction,
                    messages: snapshot.messages,
                    currentUserId: snapshot.userId,
                    onSendMessage: onSendMessage,
                    sendPermissionDenied: snapshot.permissionDeniedActions.contains("send_message"),
                    open: $drawerOpen,
                    tab: $drawerTab
                )
                .padding(.trailing, horizontal.trailing)
                .zIndex(LandscapeLayoutTokens.drawerZIndex)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: videoWallOpen) { open in
                if open { drawerOpen = false }
            }
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func mainArea(topInset: CGFloat, bottomInset: CGFloat) -> some View {
        GeometryReader { main in
            ZStack {
                // 白板铺满主区（不再 16:9 居中留白边）。
                whiteboardLayer

                if snapshot.canEditWhiteboard && !videoMainStage {
                    EduDraggableFloat(
                        containerSize: main.size,
                        defaultAnchor: .leftCenter,
                        topBias: LandscapeLayoutTokens.annoTopBias,
                        enabled: true
                    ) {
                        AnnotationToolbarView(mobile: true)
                    }
                    .zIndex(LandscapeLayoutTokens.annoToolbarZIndex)
                }

                VStack(spacing: 0) {
                    LandscapeGlassHeader(
                        snapshot: snapshot,
                        title: title,
                        elapsedLabel: elapsedLabel,
                        orientation: orientation,
                        effectiveLandscape: main.size.width > main.size.height,
                        onOpenSettings: onOpenSettings,
                        onBack: onBack,
                        onInteract: { activity.bump() }
                    )
                    .padding(.top, topInset)
                    .eduIdleAutoSlide(
                        activity: activity,
                        edge: .top,
                        interval: LandscapeLayoutTokens.chromeIdleIntervalSeconds,
                        paused: chromeFadePaused
                    )

                    Spacer(minLength: 0)

                    LandscapeGlassBottomBar(
                        videoLayout: videoLayout,
                        videoWallOpen: videoWallOpen,
                        drawerOpen: drawerOpen,
                        coursewareOpen: coursewareOpen,
                        bottomInset: bottomInset,
                        onVideoLayout: onVideoLayout,
                        onToggleVideoWall: onToggleVideoWall,
                        onToggleDrawer: {
                            if !drawerOpen { onRefreshMembers() }
                            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.modal)) {
                                drawerOpen.toggle()
                            }
                        },
                        onToggleCourseware: onToggleCourseware,
                        onEnd: onEnd,
                        onRequestInteraction: onRequestInteraction,
                        audioMuted: snapshot.audioMuted,
                        videoMuted: snapshot.videoMuted,
                        onToggleMicrophone: onToggleMicrophone,
                        onToggleCamera: onToggleCamera,
                        permissionDeniedActions: snapshot.permissionDeniedActions,
                        showCourseware: !videoMainStage,
                        canEndClass: snapshot.canEndClass,
                        onInteract: { activity.bump() }
                    )
                    .eduIdleAutoSlide(
                        activity: activity,
                        edge: .bottom,
                        interval: LandscapeLayoutTokens.chromeIdleIntervalSeconds,
                        paused: chromeFadePaused
                    )
                }
                .zIndex(LandscapeLayoutTokens.chromeZIndex)

                AnnotationMobilePanelSlot()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .zIndex(LandscapeLayoutTokens.annoPanelZIndex)

                ChromeRevealHandle(
                    visible: !activity.visible,
                    onReveal: { activity.bump() }
                )
                .padding(.top, topInset)
                .zIndex(LandscapeLayoutTokens.revealHandleZIndex)
            }
            .frame(width: main.size.width, height: main.size.height)
        }
    }

    @ViewBuilder
    private var whiteboardLayer: some View {
        Group {
            if videoMainStage {
                MainVideoStageView(teacher: featuredTeacher, showLiveBadge: snapshot.needLive)
            } else {
                ContentCanvasView(
                    document: document,
                    compact: true,
                    headerEndInset: LandscapeStageDrawer.toggleWidth,
                    onOpenThumbnails: onOpenThumbnails,
                    onPrevPage: {
                        document.currentPage = max(1, document.currentPage - 1)
                    },
                    onNextPage: {
                        document.currentPage = min(document.totalPages, document.currentPage + 1)
                    },
                    onFullscreen: onFullscreen
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ChromeRevealHandle: View {
    let visible: Bool
    let onReveal: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onReveal) {
                EduIcon(
                    EduIcons.unfoldMore,
                    size: LandscapeLayoutTokens.revealHandleIconSize,
                    tint: EduColors.primary
                )
                    .padding(.horizontal, LandscapeLayoutTokens.revealHandleHorizontalPadding)
                    .padding(.vertical, LandscapeLayoutTokens.revealHandleVerticalPadding)
                    .background {
                        LandscapeRevealHandleShape()
                            .fill(.ultraThinMaterial)
                            .overlay {
                                LandscapeRevealHandleShape()
                                    .fill(
                                        EduColors.surface.opacity(
                                            LandscapeLayoutTokens.revealHandleSurfaceOpacity
                                        )
                                    )
                            }
                    }
                    .shadow(
                        color: Color.black.opacity(LandscapeLayoutTokens.revealHandleShadowOpacity),
                        radius: LandscapeLayoutTokens.revealHandleShadowRadius,
                        y: LandscapeLayoutTokens.revealHandleShadowY
                    )
                    .frame(
                        width: LandscapeLayoutTokens.revealHandleTouchWidth,
                        height: LandscapeLayoutTokens.revealHandleTouchHeight,
                        alignment: .top
                    )
            }
            .buttonStyle(EduPressButtonStyle())
            .accessibilityLabel(Text(LandscapeLayoutTokens.revealHandleAccessibilityLabel))

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(
            .easeOut(duration: LandscapeLayoutTokens.revealHandleAnimationDuration),
            value: visible
        )
    }
}

private struct LandscapeRevealHandleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}

private enum LandscapeLayoutTokens {
    static let annoTopBias: CGFloat = 96
    static let chromeIdleIntervalSeconds: TimeInterval = 5
    static let chromeZIndex: Double = 40
    static let annoToolbarZIndex: Double = 45
    static let drawerZIndex: Double = 50
    static let annoPanelZIndex: Double = 55
    static let stageDrawerZIndex: Double = 35
    static let revealHandleZIndex: Double = 41
    static let revealHandleTouchWidth: CGFloat = 50
    static let revealHandleTouchHeight: CGFloat = 44
    static let revealHandleIconSize: CGFloat = 18
    static let revealHandleHorizontalPadding: CGFloat = 16
    static let revealHandleVerticalPadding: CGFloat = 4
    static let revealHandleSurfaceOpacity: Double = 0.80
    static let revealHandleShadowOpacity: Double = 0.08
    static let revealHandleShadowRadius: CGFloat = 2
    static let revealHandleShadowY: CGFloat = 1
    static let revealHandleAnimationDuration: Double = 0.2
    static let revealHandleAccessibilityLabel = EduI18n.text("ariaRevealControls")
}
