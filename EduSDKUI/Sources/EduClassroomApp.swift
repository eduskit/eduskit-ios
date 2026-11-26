import Combine
import EduSDK
import SwiftUI

public struct EduClassroomApp: View {
    @ObservedObject var controller: ClassroomController
    @ObservedObject var orientation: OrientationController
    var themeMode: EduThemeMode
    var localeTag: String?
    var onLeaveFinished: () -> Void
    var onKeepListening: () -> Void

    @State private var document = DemoData.document
    @State private var videoLayout: VideoLayout = .rightTop
    @State private var sidebarCollapsed = false
    @State private var sidebarInstant = false
    @State private var layoutFlipping = false
    @State private var thumbnailsOpen = false
    @State private var coursewareOpen = false
    @State private var settingsOpen = false
    @State private var videoWallOpen = false
    @State private var contentFullscreen = false
    private var stripParticipants: [ClassroomParticipant] { controller.snapshot.stageParticipants }
    private var featuredTeacher: ClassroomParticipant? { controller.snapshot.featuredTeacher }
    @Namespace private var tileNamespace

    private var flipDuration: Double { EduMotion.flipMin + 0.08 }

    private var classroomTimerLabel: String {
        guard controller.snapshot.timerMode != .hidden,
              let total = controller.snapshot.timerSeconds else { return "" }
        let days = total / (Self.secondsPerMinute * Self.minutesPerHour * Self.hoursPerDay)
        let hours = total / (Self.secondsPerMinute * Self.minutesPerHour) % Self.hoursPerDay
        let minutes = total / Self.secondsPerMinute % Self.minutesPerHour
        let seconds = total % Self.secondsPerMinute
        let key = controller.snapshot.timerMode == .countdown ? "classroomStartsIn" : "classroomElapsed"
        return EduI18n.text(key, ["days": days, "hours": hours, "minutes": minutes, "seconds": seconds])
    }

    private static let secondsPerMinute: Int64 = 60
    private static let minutesPerHour: Int64 = 60
    private static let hoursPerDay: Int64 = 24

    public init(
        controller: ClassroomController,
        orientation: OrientationController = OrientationController(),
        themeMode: EduThemeMode = .system,
        localeTag: String? = nil,
        onLeaveFinished: @escaping () -> Void,
        onKeepListening: @escaping () -> Void = {}
    ) {
        self.controller = controller
        self.orientation = orientation
        self.themeMode = themeMode
        self.localeTag = localeTag
        self.onLeaveFinished = onLeaveFinished
        self.onKeepListening = onKeepListening
    }

    public var body: some View {
        GeometryReader { geo in
            let isLandscape = shouldUseLandscape(geo: geo)
            let isPhone = geo.size.width < EduDimens.phoneBreakpoint
            ZStack {
                Group {
                    MobileClassroomLayout(
                        toolsPanel: { AnyView(TeachingToolsPanel(controller: controller, portrait: true, onNotice: portraitNotice)) },
                        snapshot: controller.snapshot,
                        title: classroomTitle,
                        elapsedLabel: classroomTimerLabel,
                        document: $document,
                        members: controller.snapshot.members,
                        stageParticipants: stripParticipants,
                        videoLayout: videoLayout,
                        videoWallOpen: videoWallOpen,
                        onOpenSettings: { withAnimation(modalAnim) { settingsOpen = true } },
                        onNotifications: { portraitNotice(EduI18n.text("portraitToastNotifications")) },
                        onNotice: portraitNotice,
                        onOpenThumbnails: { withAnimation(modalAnim) { thumbnailsOpen = true } },
                        onFullscreen: { withAnimation(modalAnim) { contentFullscreen = true } },
                        onVideoLayout: { setLayout($0, isPhone: true) },
                        onToggleVideoWall: {
                            withAnimation(modalAnim) { videoWallOpen.toggle() }
                        },
                        onEnd: endOrLeave,
                        onBack: leave,
                        onSendMessage: controller.sendImMessage,
                        onLoadMoreMembers: controller.loadMoreMembers,
                        onLoadMemberActions: { userId, completion in
                            controller.loadMemberActions(userId: userId, completion: completion)
                        },
                        onMemberAction: { action, userId, completion in
                            controller.performMemberAction(action: action, userId: userId, completion: completion)
                        },
                        coursewareOpen: coursewareOpen,
                        onToggleCourseware: {
                            withAnimation(modalAnim) { coursewareOpen.toggle() }
                        },
                        onRequestInteraction: { _ = controller.requestInteraction($0) },
                        onToggleMicrophone: { controller.setMicrophoneEnabled(controller.snapshot.audioMuted) },
                        onToggleCamera: { controller.setCameraEnabled(controller.snapshot.videoMuted) },
                        onToggleHand: {
                            if controller.snapshot.onStage.contains(where: { $0.userId == controller.snapshot.userId }) {
                                controller.leaveStage()
                            } else if controller.snapshot.handRaised {
                                controller.cancelHand()
                            } else {
                                controller.raiseHand()
                            }
                        },
                        onToggleScreenShare: {
                            if controller.snapshot.localScreenSharing { controller.stopScreenShare() }
                            else { controller.startScreenShare() }
                        },
                        featuredTeacher: featuredTeacher,
                        landscape: isLandscape,
                        onOpenDevices: controller.openDeviceCheck,
                        onStartClass: controller.startClass
                    )

                if contentFullscreen && !controller.snapshot.isTeacherVideoMainStage() {
                    ContentCanvasView(
                        document: document,
                        compact: isPhone || isLandscape,
                        isFullscreen: true,
                        onOpenThumbnails: { withAnimation(modalAnim) { thumbnailsOpen = true } },
                        onZoomIn: { document.zoomPercent = min(200, document.zoomPercent + 10) },
                        onZoomOut: { document.zoomPercent = max(50, document.zoomPercent - 10) },
                        onPrevPage: { document.currentPage = max(1, document.currentPage - 1) },
                        onNextPage: {
                            document.currentPage = min(document.totalPages, document.currentPage + 1)
                        },
                        onFullscreen: { withAnimation(modalAnim) { contentFullscreen = false } }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(EduColors.surfaceBright)
                    .transition(.opacity)
                    .zIndex(14)
                }

                if videoWallOpen {
                    VideoWallView(
                        participants: stripParticipants,
                        namespace: tileNamespace,
                        onClose: { withAnimation(modalAnim) { videoWallOpen = false } },
                        showLiveBadge: controller.snapshot.needLive
                    )
                    .eduModalEnter(visible: true)
                    .transition(.opacity)
                    .zIndex(10)
                }

                PopupShell(visible: thumbnailsOpen, onDismiss: {
                    withAnimation(modalAnim) { thumbnailsOpen = false }
                }, alignBottom: isPhone) {
                    ThumbnailPopoverView(
                        onDismiss: { withAnimation(modalAnim) { thumbnailsOpen = false } },
                        sheet: isPhone,
                        onNotice: portraitNotice
                    )
                }
                .zIndex(11)

                if !controller.snapshot.isTeacherVideoMainStage() {
                    PopupShell(visible: coursewareOpen, onDismiss: {
                        withAnimation(modalAnim) { coursewareOpen = false }
                    }) {
                        CoursewarePanelView(
                            controller: controller,
                            onDismiss: { withAnimation(modalAnim) { coursewareOpen = false } }
                        )
                    }
                    .zIndex(11)
                }

                PopupShell(visible: settingsOpen, onDismiss: {
                    withAnimation(modalAnim) { settingsOpen = false }
                }) {
                    SettingsModalView(controller: controller, onDismiss: {
                        withAnimation(modalAnim) { settingsOpen = false }
                    }, onCheckDevices: {
                        withAnimation(modalAnim) { settingsOpen = false }
                        controller.openDeviceCheck()
                    })
                }
                .zIndex(12)

                PopupShell(visible: controller.snapshot.deviceCheckOpen, onDismiss: {
                    controller.closeDeviceCheck()
                }, alignBottom: isPhone || isLandscape) {
                    DeviceCheckModalView(controller: controller)
                }
                .zIndex(13)

                }

            }
            .background(EduColors.surfaceLowest)
            .frame(width: geo.size.width, height: geo.size.height)
            .overlay {
                FeedbackHost(
                    feedback: controller.snapshot.feedback,
                    onShown: controller.feedbackShown,
                    onDismiss: { id, reason in controller.dismissFeedback(id: id, reason: reason) },
                    onAction: controller.handleFeedbackAction
                )
            }
            .eduTooltips()
            .onAppear {
                EduFontRegistrar.registerIfNeeded()
            }
            .onReceive(controller.$snapshot) { snapshot in
                if snapshot.isTeacherVideoMainStage() {
                    coursewareOpen = false
                    contentFullscreen = false
                }
            }
        }
        // 根容器全屏 bleed，子布局用 safeAreaInsets 自行处理顶/底/刘海。
        .ignoresSafeArea(.container)
        .preferredColorScheme(preferredColorScheme)
        .environment(\.chatHistoryControls, ChatHistoryControls(loading: controller.snapshot.historyLoading,
            hasMore: controller.snapshot.historyHasMore, error: controller.snapshot.historyError, load: controller.loadImMessageHistory,
            ready: controller.snapshot.initStatus == .ready,
            notice: controller.snapshot.classroomView.runtime.historyNotice))
        .environment(\.locale, Locale(identifier: localeTag ?? Locale.current.identifier))
        .environment(\.liveUiSnapshot, controller.snapshot)
        .environment(\.classroomVideoBinder, ClassroomVideoBinder(
            bindUserVideo: { slot, view in
                controller.bindUserVideo(slot: slot, view: view)
            },
            unbindUserVideo: { slot, view in
                controller.unbindUserVideo(slot: slot, view: view)
            },
            bindLiveStream: { streamName, view in
                controller.bindLiveStream(streamName: streamName, view: view)
            },
            unbindLiveStream: { streamName, view in
                controller.unbindLiveStream(streamName: streamName, view: view)
            }
        ))
    }

    private var classroomTitle: String {
        if !controller.snapshot.classroomTitle.isEmpty {
            return controller.snapshot.classroomTitle
        }
        if case .loading = controller.snapshot.initStatus {
            return ""
        }
        return DemoData.meeting.title
    }

    private var preferredColorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    private var modalAnim: Animation {
        .timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.modal)
    }

    /// Landscape layout is used when the user has explicitly locked landscape,
    /// or when the system reports a compact height (< 500pt) with wider-than-tall aspect.
    private func shouldUseLandscape(geo: GeometryProxy) -> Bool {
        switch orientation.mode {
        case .lockedLandscape:
            return true
        case .lockedPortrait:
            return false
        case .auto:
            let size = EduSafeArea.windowSize ?? geo.size
            return size.width > size.height
        }
    }

    private func portraitNotice(_ message: String) {
        controller.presentFeedback(FeedbackRequest.create(
            mode: .toast,
            tone: .info,
            message: message,
            autoDismissMs: 3000
        ))
    }

    private func setLayout(_ next: VideoLayout, isPhone: Bool) {
        guard next != videoLayout, !videoWallOpen, !layoutFlipping else { return }
        if isPhone {
            videoLayout = next
            return
        }
        layoutFlipping = true
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: flipDuration)) {
            if next.isRight && sidebarCollapsed {
                sidebarInstant = true
                sidebarCollapsed = false
            }
            videoLayout = next
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + flipDuration) {
            layoutFlipping = false
            if sidebarInstant {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) {
                    sidebarInstant = false
                }
            }
        }
    }

    private func endOrLeave() {
        if controller.endOrLeaveClassroom() {
            onLeaveFinished()
        }
    }

    private func leave() {
        if controller.snapshot.continuation != nil {
            controller.promptClassroomBack(onContinue: onKeepListening, onLeave: {
                controller.leaveClassroom()
                onLeaveFinished()
            })
            return
        }
        controller.leaveClassroom()
        onLeaveFinished()
    }
}
