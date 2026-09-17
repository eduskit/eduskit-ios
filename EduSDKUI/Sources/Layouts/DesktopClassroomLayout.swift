import SwiftUI

struct DesktopClassroomLayout: View {
    let snapshot: UiSnapshot
    let title: String
    let elapsedLabel: String
    let document: DemoDocument
    let participants: [ClassroomParticipant]
    let stageParticipants: [ClassroomParticipant]
    let videoLayout: VideoLayout
    let videoWallOpen: Bool
    @Binding var sidebarCollapsed: Bool
    var sidebarInstant: Bool
    var layoutFlipping: Bool = false
    var namespace: Namespace.ID
    var onOpenSettings: () -> Void
    var onOpenThumbnails: () -> Void
    var onZoomIn: () -> Void
    var onZoomOut: () -> Void
    var onFullscreen: () -> Void = {}
    var onVideoLayout: (VideoLayout) -> Void
    var onToggleVideoWall: () -> Void
    var coursewareOpen: Bool = false
    var onToggleCourseware: () -> Void = {}
    var onRequestInteraction: (String) -> Void = { _ in }
    var onToggleMicrophone: () -> Void = {}
    var onToggleCamera: () -> Void = {}
    var featuredTeacher: ClassroomParticipant? = nil
    var onEnd: () -> Void
    var onSendMessage: (String) -> Void
    var onLoadMoreMembers: () -> Void = {}
    var onLoadMemberActions: (String, @escaping ([MemberActionAvailability]) -> Void) -> Void = { _, callback in callback([]) }
    var onMemberAction: (String, String, @escaping () -> Void) -> Void = { _, _, done in done() }

    private var flipAnim: Animation {
        EduMotion.flip(EduMotion.flipMin + 0.08)
    }

    var body: some View {
        // 根 ZStack：白板工具栏提到最上层，面板可盖住 header / footer（对齐 Web z-index: 30）
        ZStack(alignment: .leading) {
            VStack(spacing: 0) {
                ClassroomHeaderView(
                    snapshot: snapshot,
                    title: title,
                    elapsedLabel: elapsedLabel,
                    onOpenSettings: onOpenSettings
                )
                HStack(spacing: 0) {
                    ZStack(alignment: .bottom) {
                        VStack(spacing: 12) {
                            if videoLayout == .top && !videoWallOpen {
                                ParticipantStripView(participants: stageParticipants, namespace: namespace, showLiveBadge: snapshot.needLive)
                                    .transition(.opacity)
                            }
                            Group {
                                if snapshot.isTeacherVideoMainStage() {
                                    MainVideoStageView(teacher: featuredTeacher, showLiveBadge: snapshot.needLive)
                                } else {
                                    ContentCanvasView(
                                        document: document,
                                        onOpenThumbnails: onOpenThumbnails,
                                        onZoomIn: onZoomIn,
                                        onZoomOut: onZoomOut,
                                        onFullscreen: onFullscreen
                                    )
                                }
                            }
                            .frame(maxHeight: .infinity)
                            if videoLayout == .bottom && !videoWallOpen {
                                ParticipantStripView(participants: stageParticipants, namespace: namespace, showLiveBadge: snapshot.needLive)
                                    .transition(.opacity)
                            }
                        }
                        .padding(16)

                        FloatingToolbarView(
                            videoLayout: videoLayout,
                            videoWallOpen: videoWallOpen,
                            coursewareOpen: coursewareOpen,
                            onVideoLayout: onVideoLayout,
                            onToggleVideoWall: onToggleVideoWall,
                            onToggleCourseware: onToggleCourseware,
                            onRequestInteraction: onRequestInteraction,
                            audioMuted: snapshot.audioMuted,
                            videoMuted: snapshot.videoMuted,
                            onToggleMicrophone: onToggleMicrophone,
                            onToggleCamera: onToggleCamera,
                            permissionDeniedActions: snapshot.permissionDeniedActions,
                            showCourseware: !snapshot.isTeacherVideoMainStage(),
                            canEndClass: snapshot.canEndClass,
                            onEnd: onEnd
                        )
                        .padding(.bottom, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    MeetingSidebarView(
                        participants: participants,
                        messages: snapshot.messages,
                        currentUserId: snapshot.userId,
                        onSendMessage: onSendMessage,
                        sendPermissionDenied: snapshot.permissionDeniedActions.contains("send_message"),
                        membersNextCursor: snapshot.membersNextCursor,
                        membersLoading: snapshot.membersLoading,
                        onLoadMoreMembers: onLoadMoreMembers,
                        onLoadMemberActions: onLoadMemberActions,
                        onMemberAction: onMemberAction,
                        videoLayout: videoLayout,
                        videoWallOpen: videoWallOpen,
                        collapsed: $sidebarCollapsed,
                        instant: sidebarInstant,
                        flipClip: layoutFlipping,
                        namespace: namespace,
                        showLiveBadge: snapshot.needLive
                    )
                }
            }

            // 舞台左缘 16 + 工具栏 inset 12；下移 headerHeight/2，使垂直中心对齐内容区（非整窗）
            if snapshot.canEditWhiteboard && !snapshot.isTeacherVideoMainStage() {
                AnnotationToolbarView()
                    .padding(.leading, 28)
                    .offset(y: EduDimens.headerHeight / 2)
                    .zIndex(40)
            }
        }
        .background(EduColors.surfaceBright)
        .animation(flipAnim, value: videoLayout)
    }
}
