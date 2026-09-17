import SwiftUI
import EduSDK

/// Aligns with Web mobile.css + MobileClassroomLayout.vue
struct MobileClassroomLayout: View {
    let snapshot: UiSnapshot
    let title: String
    let elapsedLabel: String
    @Binding var document: DemoDocument
    let members: [ClassroomMember]
    let stageParticipants: [ClassroomParticipant]
    let videoLayout: VideoLayout
    let videoWallOpen: Bool
    var onOpenSettings: () -> Void
    var onOpenThumbnails: () -> Void
    var onFullscreen: () -> Void = {}
    var onVideoLayout: (VideoLayout) -> Void
    var onToggleVideoWall: () -> Void
    var onEnd: () -> Void
    var onBack: () -> Void
    var onSendMessage: (String) -> Void
    var onLoadMoreMembers: () -> Void = {}
    var onLoadMemberActions: (String, @escaping ([MemberActionAvailability]) -> Void) -> Void = { _, callback in callback([]) }
    var onMemberAction: (String, String, @escaping () -> Void) -> Void = { _, _, done in done() }
    var coursewareOpen: Bool = false
    var onToggleCourseware: () -> Void = {}
    var onRequestInteraction: (String) -> Void = { _ in }
    var onToggleMicrophone: () -> Void = {}
    var onToggleCamera: () -> Void = {}
    var featuredTeacher: ClassroomParticipant? = nil

    @State private var bloomOpen = false
    @State private var tab = 0
    /// 底栏（含 Home Indicator 内侧 padding）实测高度，用于顶起内容。
    @State private var bottomBarHeight: CGFloat = MobileBottomBarTokens.estimatedCollapsedHeight

    private var speaker: ClassroomParticipant? {
        stageParticipants.first(where: { $0.id != snapshot.userId }) ?? stageParticipants.first
    }

    private var videoMainStage: Bool {
        snapshot.isTeacherVideoMainStage()
    }

    private var annoTopBias: CGFloat {
        MobileLayoutTokens.annoTopBiasBase + EduDimens.pipSize + MobileLayoutTokens.annoTopBiasGap
    }

    var body: some View {
        GeometryReader { geo in
            let insets = EduSafeArea.merge(with: geo)
            let topInset = insets.top
            let bottomInset = insets.bottom

            ZStack(alignment: .bottom) {
                Color.white

                VStack(spacing: 0) {
                    ClassroomHeaderView(
                        snapshot: snapshot,
                        title: title,
                        elapsedLabel: elapsedLabel,
                        isPhone: true,
                        onOpenSettings: onOpenSettings,
                        onBack: onBack
                    )

                    stageBody(width: geo.size.width)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(EduColors.surfaceLow)
                }
                // 顶部避让刘海；底部按底栏真实高度留白（底栏自身沉入 Home Indicator）。
                .padding(.top, topInset)
                .padding(.bottom, bottomBarHeight)

                MobileBottomBarView(
                    videoLayout: videoLayout,
                    videoWallOpen: videoWallOpen,
                    coursewareOpen: coursewareOpen,
                    bottomInset: bottomInset,
                    onVideoLayout: onVideoLayout,
                    onToggleVideoWall: {
                        if !videoWallOpen {
                            bloomOpen = false
                        }
                        onToggleVideoWall()
                    },
                    onToggleCourseware: onToggleCourseware,
                    onOpenChat: { tab = 1 },
                    onRequestInteraction: onRequestInteraction,
                    audioMuted: snapshot.audioMuted,
                    videoMuted: snapshot.videoMuted,
                    onToggleMicrophone: onToggleMicrophone,
                    onToggleCamera: onToggleCamera,
                    permissionDeniedActions: snapshot.permissionDeniedActions,
                    showCourseware: !videoMainStage,
                    canEndClass: snapshot.canEndClass,
                    onEnd: onEnd
                )
                .background(
                    GeometryReader { barGeo in
                        Color.clear.preference(
                            key: MobileBottomBarHeightKey.self,
                            value: barGeo.size.height
                        )
                    }
                )
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onPreferenceChange(MobileBottomBarHeightKey.self) { height in
                if height > 0 { bottomBarHeight = height }
            }
            .onChange(of: videoWallOpen) { open in
                if open { bloomOpen = false }
            }
        }
        // 拿到含 Home Indicator 的全屏尺寸，避免底栏再被 Safe Area 顶起一层。
        .ignoresSafeArea()
    }

    @ViewBuilder
    private func stageBody(width: CGFloat) -> some View {
        ZStack {
            VStack(spacing: 0) {
                Group {
                    if videoMainStage {
                        MainVideoStageView(teacher: featuredTeacher, showLiveBadge: snapshot.needLive)
                    } else {
                        ContentCanvasView(
                            document: document,
                            compact: true,
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
                    .frame(
                        width: width,
                        height: DocHeaderTokens.compactHeight
                            + width / WhiteboardLayoutDefaults.aspectRatio
                    )
                    .background(EduColors.surfaceLowest)
                    .overlay(alignment: .bottom) {
                        Rectangle()
                            .fill(EduColors.surfaceVariant)
                            .frame(height: MobileLayoutTokens.canvasBottomHairline)
                    }

                MobileTabPanelView(
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
                    selectedTab: tab,
                    onTabChange: { tab = $0 }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            MobileStageBloomView(
                participants: stageParticipants,
                visible: bloomOpen,
                showLiveBadge: snapshot.needLive,
                onDismiss: {
                    withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.bloom)) {
                        bloomOpen = false
                    }
                }
            )
            .zIndex(MobileLayoutTokens.bloomZIndex)

            GeometryReader { geo in
                EduDraggableFloat(
                    containerSize: geo.size,
                    defaultAnchor: .topEnd,
                    topBias: MobileLayoutTokens.pipTopBias,
                    enabled: true
                ) {
                    MobileSpeakerPipView(
                        participant: speaker,
                        expanded: bloomOpen,
                        stageCount: stageParticipants.count
                    ) {
                        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.bloom)) {
                            bloomOpen.toggle()
                        }
                    }
                }
                .zIndex(bloomOpen ? MobileLayoutTokens.pipExpandedZIndex : MobileLayoutTokens.pipZIndex)

                if snapshot.canEditWhiteboard && !videoMainStage {
                    EduDraggableFloat(
                        containerSize: geo.size,
                        defaultAnchor: .topEnd,
                        topBias: annoTopBias,
                        enabled: true
                    ) {
                        AnnotationToolbarView(mobile: true)
                            .opacity(bloomOpen ? MobileLayoutTokens.annoDimmedOpacity : 1)
                            .allowsHitTesting(!bloomOpen)
                            .animation(
                                .timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.floatExpand),
                                value: bloomOpen
                            )
                    }
                    .zIndex(MobileLayoutTokens.annoToolbarZIndex)
                }
            }
            .zIndex(MobileLayoutTokens.floatsLayerZIndex)

            AnnotationMobilePanelSlot()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .zIndex(MobileLayoutTokens.annoPanelZIndex)
        }
    }
}

private enum MobileLayoutTokens {
    static let canvasBottomHairline: CGFloat = 1
    static let annoTopBiasBase: CGFloat = 160
    static let annoTopBiasGap: CGFloat = 12
    static let pipTopBias: CGFloat = 160
    static let annoDimmedOpacity: Double = 0.35
    static let bloomZIndex: Double = 28
    static let floatsLayerZIndex: Double = 30
    static let pipZIndex: Double = 30
    static let pipExpandedZIndex: Double = 32
    static let annoToolbarZIndex: Double = 55
    static let annoPanelZIndex: Double = 60
}

private struct MobileBottomBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
