import Combine
import EduSDK
import SwiftUI

public struct EduClassroomApp: View {
    @ObservedObject var controller: ClassroomController
    @ObservedObject var orientation: OrientationController
    var themeMode: EduThemeMode
    var localeTag: String?
    var onLeaveFinished: () -> Void

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
    /// 成员映射结果缓存。放在 `body` 里算会让每一帧（含动画帧）重跑一遍
    /// 建 Set + 映射 + 过滤，这里改为随快照变化重算一次。
    @State private var participants: [ClassroomParticipant] = []
    @State private var stageParticipants: [ClassroomParticipant] = []
    @State private var stripParticipants: [ClassroomParticipant] = []
    @State private var featuredTeacher: ClassroomParticipant?
    @Namespace private var tileNamespace

    private enum Tokens {
        /// 后台 `member.stageStatus` 的「台上」取值。
        static let stageStatusOn = "on"
    }

    private static func buildParticipants(
        members: [ClassroomMember],
        onStage: [StageUser],
        streamInfos: [StreamInfo]
    ) -> [ClassroomParticipant] {
        let stageIds = Set(onStage.map(\.userId))
        func muteOf(_ userId: String) -> (Bool, Bool) {
            let stream = streamInfos.first { $0.userId == userId }
            return (stream?.audioMuted ?? true, stream?.videoMuted ?? true)
        }
        var result = members.map { member in
            let mute = muteOf(member.userId)
            return ClassroomParticipant(
                id: member.userId,
                displayName: member.displayName?.isEmpty == false ? member.displayName! : member.userId,
                roleLabel: member.role,
                avatarUrl: member.avatarUrl,
                initials: nil,
                onStage: member.stageStatus == Tokens.stageStatusOn || stageIds.contains(member.userId),
                audioMuted: mute.0,
                videoMuted: mute.1
            )
        }
        let mappedIds = Set(result.map(\.id))
        for user in onStage where !mappedIds.contains(user.userId) {
            let mute = muteOf(user.userId)
            result.append(ClassroomParticipant(
                id: user.userId,
                displayName: user.displayName?.isEmpty == false ? user.displayName! : user.userId,
                roleLabel: nil,
                avatarUrl: nil,
                initials: nil,
                onStage: true,
                audioMuted: mute.0,
                videoMuted: mute.1
            ))
        }
        return result
    }

    private func refreshParticipants(from snapshot: UiSnapshot) {
        let next = Self.buildParticipants(
            members: snapshot.members,
            onStage: snapshot.onStage,
            streamInfos: snapshot.streamInfos
        )
        let nextStage = next.filter(\.onStage)
        let nextTeacher = snapshot.featuredTeacherParticipant()
        let nextStrip = snapshot.isTeacherVideoMainStage()
            ? stripParticipantsExcludingTeacher(nextStage, teacherUserId: snapshot.teacherUserId)
            : nextStage
        guard next != participants
            || nextStage != stageParticipants
            || nextTeacher != featuredTeacher
            || nextStrip != stripParticipants else { return }
        participants = next
        stageParticipants = nextStage
        featuredTeacher = nextTeacher
        stripParticipants = nextStrip
    }

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
        onLeaveFinished: @escaping () -> Void
    ) {
        self.controller = controller
        self.orientation = orientation
        self.themeMode = themeMode
        self.localeTag = localeTag
        self.onLeaveFinished = onLeaveFinished
    }

    public var body: some View {
        GeometryReader { geo in
            let isLandscape = shouldUseLandscape(geo: geo)
            let isPhone = geo.size.width < EduDimens.phoneBreakpoint
            ZStack {
                Group {
                if isLandscape {
                    LandscapeClassroomLayout(
                        snapshot: controller.snapshot,
                        title: classroomTitle,
                        elapsedLabel: classroomTimerLabel,
                        document: $document,
                        members: controller.snapshot.members,
                        stageParticipants: stripParticipants,
                        videoLayout: videoLayout,
                        videoWallOpen: videoWallOpen,
                        orientation: orientation,
                        onOpenSettings: { withAnimation(modalAnim) { settingsOpen = true } },
                        onOpenThumbnails: { withAnimation(modalAnim) { thumbnailsOpen = true } },
                        onFullscreen: { withAnimation(modalAnim) { contentFullscreen = true } },
                        onVideoLayout: { setLayout($0, isPhone: true) },
                        onToggleVideoWall: {
                            withAnimation(modalAnim) { videoWallOpen.toggle() }
                        },
                        onEnd: endOrLeave,
                        onBack: leave,
                        onSendMessage: controller.sendImMessage,
                        onRefreshMembers: controller.refreshMembers,
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
                        featuredTeacher: featuredTeacher
                    )
                } else if isPhone {
                    MobileClassroomLayout(
                        snapshot: controller.snapshot,
                        title: classroomTitle,
                        elapsedLabel: classroomTimerLabel,
                        document: $document,
                        members: controller.snapshot.members,
                        stageParticipants: stripParticipants,
                        videoLayout: videoLayout,
                        videoWallOpen: videoWallOpen,
                        onOpenSettings: { withAnimation(modalAnim) { settingsOpen = true } },
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
                        featuredTeacher: featuredTeacher
                    )
                } else {
                    // Desktop 仍走系统 Safe Area（顶/底/侧），与手机沉浸策略区分。
                    DesktopClassroomLayout(
                        snapshot: controller.snapshot,
                        title: classroomTitle,
                        elapsedLabel: classroomTimerLabel,
                        document: document,
                        participants: participants,
                        stageParticipants: stripParticipants,
                        videoLayout: videoLayout,
                        videoWallOpen: videoWallOpen,
                        sidebarCollapsed: $sidebarCollapsed,
                        sidebarInstant: sidebarInstant,
                        layoutFlipping: layoutFlipping,
                        namespace: tileNamespace,
                        onOpenSettings: { withAnimation(modalAnim) { settingsOpen = true } },
                        onOpenThumbnails: { withAnimation(modalAnim) { thumbnailsOpen = true } },
                        onZoomIn: { document.zoomPercent = min(200, document.zoomPercent + 10) },
                        onZoomOut: { document.zoomPercent = max(50, document.zoomPercent - 10) },
                        onFullscreen: { withAnimation(modalAnim) { contentFullscreen = true } },
                        onVideoLayout: { setLayout($0, isPhone: false) },
                        onToggleVideoWall: {
                            withAnimation(modalAnim) { videoWallOpen.toggle() }
                        },
                        coursewareOpen: coursewareOpen,
                        onToggleCourseware: {
                            withAnimation(modalAnim) { coursewareOpen.toggle() }
                        },
                        onRequestInteraction: { _ = controller.requestInteraction($0) },
                        onToggleMicrophone: { controller.setMicrophoneEnabled(controller.snapshot.audioMuted) },
                        onToggleCamera: { controller.setCameraEnabled(controller.snapshot.videoMuted) },
                        featuredTeacher: featuredTeacher,
                        onEnd: endOrLeave,
                        onSendMessage: controller.sendImMessage,
                        onLoadMoreMembers: controller.loadMoreMembers
                    )
                    .padding(.top, geo.safeAreaInsets.top)
                    .padding(.bottom, geo.safeAreaInsets.bottom)
                    .padding(.leading, geo.safeAreaInsets.leading)
                    .padding(.trailing, geo.safeAreaInsets.trailing)
                }

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

                ModalScrimHost(visible: thumbnailsOpen, onDismiss: {
                    withAnimation(modalAnim) { thumbnailsOpen = false }
                }) {
                    ThumbnailPopoverView(
                        onDismiss: { withAnimation(modalAnim) { thumbnailsOpen = false } }
                    )
                }
                .zIndex(11)

                if !controller.snapshot.isTeacherVideoMainStage() {
                    ModalScrimHost(visible: coursewareOpen, onDismiss: {
                        withAnimation(modalAnim) { coursewareOpen = false }
                    }) {
                        CoursewarePanelView(
                            controller: controller,
                            onDismiss: { withAnimation(modalAnim) { coursewareOpen = false } }
                        )
                    }
                    .zIndex(11)
                }

                ModalScrimHost(visible: settingsOpen, onDismiss: {
                    withAnimation(modalAnim) { settingsOpen = false }
                }) {
                    SettingsModalView(onDismiss: {
                        withAnimation(modalAnim) { settingsOpen = false }
                    }, onCheckDevices: {
                        withAnimation(modalAnim) { settingsOpen = false }
                        controller.openDeviceCheck()
                    })
                }
                .zIndex(12)

                ModalScrimHost(visible: controller.snapshot.deviceCheckOpen, onDismiss: {
                    controller.closeDeviceCheck()
                }) {
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
                    onDismiss: controller.dismissFeedback,
                    onAction: controller.handleFeedbackAction
                )
            }
            .onAppear {
                EduFontRegistrar.registerIfNeeded()
                refreshParticipants(from: controller.snapshot)
            }
            .onReceive(controller.$snapshot) { snapshot in
                refreshParticipants(from: snapshot)
                if snapshot.isTeacherVideoMainStage() {
                    coursewareOpen = false
                    contentFullscreen = false
                }
            }
        }
        // 根容器全屏 bleed，子布局用 safeAreaInsets 自行处理顶/底/刘海。
        .ignoresSafeArea()
        .preferredColorScheme(preferredColorScheme)
        .environment(\.locale, Locale(identifier: localeTag ?? Locale.current.identifier))
        .environment(\.classroomVideoBinder, ClassroomVideoBinder(
            bindUserVideo: { userId, view in
                controller.bindUserVideo(userId: userId, view: view)
            },
            unbindUserVideo: { userId, view in
                controller.unbindUserVideo(userId: userId, view: view)
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
            let compactHeight = geo.size.height < 500
            let wider = geo.size.width > geo.size.height
            return compactHeight && wider
        }
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
        controller.leaveClassroom()
        onLeaveFinished()
    }
}
