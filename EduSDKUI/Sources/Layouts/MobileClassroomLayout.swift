import SwiftUI
import EduSDK

/// Aligns with Web mobile.css + MobileClassroomLayout.vue
struct MobileClassroomLayout: View {
    let toolsPanel: () -> AnyView
    let snapshot: UiSnapshot
    let title: String
    let elapsedLabel: String
    @Binding var document: DemoDocument
    let members: [ClassroomMember]
    let stageParticipants: [ClassroomParticipant]
    let videoLayout: VideoLayout
    let videoWallOpen: Bool
    var onOpenSettings: () -> Void
    var onNotifications: () -> Void = {}
    var onNotice: (String) -> Void = { _ in }
    var onOpenThumbnails: () -> Void
    var onFullscreen: () -> Void = {}
    var onVideoLayout: (VideoLayout) -> Void
    var onToggleVideoWall: () -> Void
    var onEnd: () -> Void
    var onBack: () -> Void
    var onSendMessage: (String) async -> Bool
    var onLoadMoreMembers: () -> Void = {}
    var onLoadMemberActions: (String, @escaping ([MemberActionAvailability]) -> Void) -> Void = { _, callback in callback([]) }
    var onMemberAction: (String, String, @escaping () -> Void) -> Void = { _, _, done in done() }
    var coursewareOpen: Bool = false
    var onToggleCourseware: () -> Void = {}
    var onRequestInteraction: (String) -> Void = { _ in }
    var onToggleMicrophone: () -> Void = {}
    var onToggleCamera: () -> Void = {}
    var onToggleHand: () -> Void = {}
    var onToggleScreenShare: () -> Void = {}
    var featuredTeacher: ClassroomParticipant? = nil

    var landscape = false
    var onOpenDevices: () -> Void = {}
    var onStartClass: () -> Void = {}
    @State var tab = 1
    @State var panelOpen = false
    @State var videoExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var entryFocused: Bool
    @State private var annotationOpen = false
    @State private var keyboardVisible = false

    private var videoMainStage: Bool { snapshot.isTeacherVideoMainStage() }
    var body: some View {
        GeometryReader { outer in
            let insets = EduSafeArea.merge(with: outer)
            let availableWidth = max(0, outer.size.width - insets.leading - insets.trailing)
            let panelWidth = landscape ? min(availableWidth, keyboardVisible ? availableWidth : MobileClassroomTokens.landscapeDrawerWidth) : availableWidth
            let boardAreaWidth = max(0, availableWidth - (landscape && videoExpanded ? MobileClassroomTokens.landscapeVideoWidth + MobileClassroomTokens.gap : 0))
            ZStack(alignment: .bottomLeading) {
                VStack(spacing: 0) {
                    MobileClassroomHeader(snapshot: snapshot, title: title, elapsed: elapsedLabel, landscape: landscape,
                        onBack: onBack, onDevices: onOpenDevices, onPanel: { tab = 3; panelOpen.toggle() })
                        .frame(height: landscape ? 0 : MobileClassroomTokens.header).clipped().accessibilityHidden(landscape)
                    GeometryReader { geo in
                        let boardWidth = landscape ? min(boardAreaWidth, geo.size.height * MobileClassroomTokens.boardAspectWidth / MobileClassroomTokens.boardAspectHeight) : geo.size.width
                        let boardHeight = landscape ? boardWidth * MobileClassroomTokens.boardAspectHeight / MobileClassroomTokens.boardAspectWidth : keyboardVisible ? MobileClassroomTokens.keyboardSummary : min(geo.size.width * MobileClassroomTokens.boardAspectHeight / MobileClassroomTokens.boardAspectWidth + MobileClassroomTokens.boardControl, max(MobileClassroomTokens.boardMinHeight, geo.size.height - MobileClassroomTokens.stageStrip - MobileClassroomTokens.tabHeight - MobileClassroomTokens.chatMinHeight))
                        let stripHeight = keyboardVisible ? 0 : MobileClassroomTokens.stageStrip
                        ZStack(alignment: .topLeading) {
                            courseware
                                .frame(width: boardWidth, height: boardHeight)
                                .overlay {
                                    if !landscape && keyboardVisible {
                                        Button { dismissKeyboard() } label: {
                                            HStack { EduIcon(EduIcons.description); Text(EduI18n.text("mobileBoardSummary")) }
                                                .frame(maxWidth: .infinity, maxHeight: .infinity).background(EduColors.surfaceLowest)
                                        }.buttonStyle(.plain)
                                    }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if annotationOpen && snapshot.canEditWhiteboard && !videoMainStage {
                                        ScrollView(.vertical, showsIndicators: false) { AnnotationToolbarView(mobile: true) }
                                            .frame(width: MobileClassroomTokens.touch + MobileClassroomTokens.inset, height: boardHeight)
                                    }
                                }
                                .offset(x: landscape ? (boardAreaWidth - boardWidth) / 2 : 0, y: landscape ? (geo.size.height - boardHeight) / 2 : 0)
                                .accessibilityIdentifier("mobile-board")
                                .accessibilityHidden(landscape && panelOpen)
                            videoColumn
                                .frame(width: landscape ? MobileClassroomTokens.landscapeVideoWidth : geo.size.width,
                                    height: landscape ? geo.size.height : MobileClassroomTokens.stageStrip)
                                .offset(x: landscape ? geo.size.width - (videoExpanded ? MobileClassroomTokens.landscapeVideoWidth : 0) : 0, y: landscape ? 0 : boardHeight)
                                .opacity((!landscape || videoExpanded) && !keyboardVisible ? 1 : 0)
                                .allowsHitTesting((!landscape || (videoExpanded && !panelOpen)) && !keyboardVisible)
                                .accessibilityHidden((landscape && (!videoExpanded || panelOpen)) || keyboardVisible)
                            if landscape && !panelOpen && !keyboardVisible {
                                videoToggle
                                    .offset(x: videoExpanded ? geo.size.width - MobileClassroomTokens.landscapeVideoWidth - MobileClassroomTokens.touch + MobileClassroomTokens.gap : geo.size.width - MobileClassroomTokens.touch,
                                        y: (geo.size.height - MobileClassroomTokens.touch) / 2)
                                classroomEntry
                                    .offset(x: max(0, geo.size.width - MobileClassroomTokens.landscapeEntrySize - MobileClassroomTokens.inset),
                                        y: max(0, geo.size.height - MobileClassroomTokens.landscapeEntrySize - MobileClassroomTokens.inset))
                            }
                            if landscape {
                                Button { dismissKeyboard(); panelOpen = false } label: {
                                    Color(hex: MobileClassroomTokens.landscapeStage)
                                        .opacity(Double(MobileClassroomTokens.drawerScrimOpacity))
                                        .frame(width: geo.size.width + insets.leading + insets.trailing,
                                            height: geo.size.height + insets.top + insets.bottom)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .offset(x: -insets.leading, y: -insets.top)
                                .opacity(panelOpen ? 1 : 0).allowsHitTesting(panelOpen).accessibilityHidden(!panelOpen)
                                .accessibilityLabel(EduI18n.text("mobileDismissPanel"))
                                .accessibilityIdentifier("mobile-panel-scrim")
                                .animation(reduceMotion ? nil : .easeOut(duration: MobileClassroomTokens.drawerMotionMs / 1000), value: panelOpen)
                            }
                            discussionPanel
                                .frame(width: panelWidth, height: max(0, landscape ? geo.size.height : geo.size.height - boardHeight - stripHeight))
                                .padding(.top, landscape ? insets.top : 0)
                                .padding(.bottom, landscape ? insets.bottom : 0)
                                .padding(.trailing, landscape ? insets.trailing : 0)
                                .background(EduColors.surfaceLowest)
                                .clipShape(MobileDrawerShape(radius: landscape ? MobileClassroomTokens.landscapeDrawerRadius : 0))
                                .offset(x: landscape ? (panelOpen ? geo.size.width - panelWidth : geo.size.width + insets.trailing) : 0,
                                    y: landscape ? -insets.top : boardHeight + stripHeight)
                                .allowsHitTesting(!landscape || panelOpen).accessibilityHidden(landscape && !panelOpen)
                                .animation(reduceMotion ? nil : .easeOut(duration: MobileClassroomTokens.drawerMotionMs / 1000), value: panelOpen)
                            AnnotationMobilePanelSlot().frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }.padding(.bottom, !landscape && !keyboardVisible ? MobileClassroomTokens.dock : 0)
                if !landscape && !keyboardVisible { dock().frame(maxWidth: .infinity) }
            }
            .padding(.top, insets.top).padding(.bottom, keyboardVisible ? 0 : insets.bottom)
            .padding(.leading, insets.leading).padding(.trailing, insets.trailing)
            .background(landscape ? Color(hex: MobileClassroomTokens.landscapeStage) : EduColors.surfaceLow).clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: MobileClassroomTokens.motionMs / 1000), value: videoExpanded)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onChange(of: landscape) { value in dismissKeyboard(); panelOpen = false; annotationOpen = false; if !value && tab > 2 { tab = 1 } }
        .onChange(of: tab) { _ in dismissKeyboard() }
        .onChange(of: panelOpen) { open in if !open { entryFocused = true } }
    }

    private var videoColumn: some View {
        VStack(spacing: 0) {
            MobileStageStrip(participants: stageParticipants, emptySeatCount: Int(snapshot.classroomView.emptySeatCount),
                vertical: landscape, canManage: snapshot.classroomView.canManageStage, showLive: snapshot.needLive,
                onInvite: { tab = 0; panelOpen = true })
                .overlay { if snapshot.initStatus == .loading && stageParticipants.isEmpty { ClassroomSkeleton(kind: landscape ? .videoColumn : .video) } }
                .padding(.bottom, landscape ? MobileClassroomTokens.landscapeEntrySize + MobileClassroomTokens.inset : 0)
        }.background(landscape ? Color(hex: MobileClassroomTokens.landscapeVideo) : EduColors.surfaceLowest)
            .accessibilityIdentifier("mobile-video-column")
    }

    private var discussionPanel: some View {
        MobileTabPanelView(toolsPanel: toolsPanel, members: snapshot.classroomView.memberDirectory, onStageUsers: snapshot.onStage,
            membersNextCursor: snapshot.membersNextCursor, membersLoading: snapshot.membersLoading,
            onLoadMoreMembers: onLoadMoreMembers, onLoadMemberActions: onLoadMemberActions, onMemberAction: onMemberAction,
            messages: snapshot.messages, currentUserId: snapshot.userId, onSendMessage: onSendMessage,
            sendPermissionDenied: snapshot.permissionDeniedActions.contains("send_message"), selectedTab: tab,
            onTabChange: { tab = $0 }, handRaised: snapshot.handRaised, onToggleHand: onToggleHand, onNotice: onNotice,
            landscape: landscape,
            classroomPanel: { AnyView(ScrollView { VStack(spacing: MobileClassroomTokens.gap) {
                dock(embedded: true)
                Button(EduI18n.text("ariaBack"), action: onBack).frame(minHeight: MobileClassroomTokens.touch)
            }.padding(MobileClassroomTokens.inset) }) },
            settingsPanel: { AnyView(ScrollView { VStack(alignment: .leading, spacing: MobileClassroomTokens.inset) {
                Text(EduI18n.text("mobileMediaDevices")).font(.system(size: MobileClassroomTokens.bodySize))
                dock(embedded: true, mediaOnly: true)
                MobileAction(icon: EduIcons.settings, label: EduI18n.text("mobileSelectDevices"), horizontal: true, action: onOpenDevices)
                MobileAction(icon: EduIcons.settings, label: EduI18n.text("settingsNavGeneral"), horizontal: true, action: onOpenSettings)
            }.padding(MobileClassroomTokens.inset) }) },
            onClose: { dismissKeyboard(); panelOpen = false })
            .overlay {
                if snapshot.initStatus == .loading && ((tab == 1 && snapshot.messages.isEmpty) || (tab == 0 && members.isEmpty)) {
                    ClassroomSkeleton().padding(.top, MobileClassroomTokens.tabHeight)
                }
            }
            .accessibilityIdentifier("mobile-discussion")
    }

    private func dock(embedded: Bool = false, mediaOnly: Bool = false) -> some View {
        MobileClassroomDock(snapshot: snapshot, embedded: embedded, mediaOnly: mediaOnly, onMic: onToggleMicrophone, onCamera: onToggleCamera,
            onHand: onToggleHand, onShare: onToggleScreenShare, onCourseware: onToggleCourseware, onDevices: onOpenDevices,
            onStart: onStartClass, onEnd: onEnd, onWall: onToggleVideoWall,
            onAnnotate: { dismissKeyboard(); panelOpen = false; annotationOpen.toggle() },
            onSettings: { if landscape { tab = 4 } else { onOpenSettings() } })
    }
    private var videoToggle: some View {
        Button { videoExpanded.toggle() } label: {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                EduIcon(videoExpanded ? "chevron_right" : "chevron_left", size: MobileClassroomTokens.actionIcon, tint: Color(hex: MobileClassroomTokens.landscapeControl))
                    .frame(width: MobileClassroomTokens.videoHandleWidth, height: MobileClassroomTokens.touch)
                    .background(Color(hex: MobileClassroomTokens.landscapeVideo))
                    .clipShape(MobileDrawerShape(radius: MobileClassroomTokens.videoHandleRadius))
                if videoExpanded { Color.clear.frame(width: MobileClassroomTokens.gap) }
            }.frame(width: MobileClassroomTokens.touch, height: MobileClassroomTokens.touch).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(EduI18n.text(videoExpanded ? "mobileHideVideos" : "mobileShowVideos"))
            .accessibilityIdentifier("mobile-stage-toggle")
    }
    private var classroomEntry: some View {
        Button { annotationOpen = false; tab = 3; panelOpen = true } label: {
            EduIcon("apps", size: MobileClassroomTokens.actionIcon, tint: EduColors.onPrimary)
                .frame(width: MobileClassroomTokens.landscapeEntrySize, height: MobileClassroomTokens.landscapeEntrySize)
                .background(EduColors.primary, in: Circle())
                .background {
                    Circle().fill(EduColors.primary)
                        .shadow(color: Color(hex: MobileClassroomTokens.landscapeStage).opacity(Double(MobileClassroomTokens.entryShadowOpacity)),
                            radius: MobileClassroomTokens.entryShadowRadius, y: MobileClassroomTokens.entryShadowOffset)
                }
                .overlay {
                    Circle().fill(LinearGradient(colors: [Color(hex: MobileClassroomTokens.surface).opacity(Double(MobileClassroomTokens.entryHighlightOpacity)), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .allowsHitTesting(false)
                }
                .overlay { Circle().strokeBorder(Color(hex: MobileClassroomTokens.surface).opacity(Double(MobileClassroomTokens.entryBorderOpacity)), lineWidth: MobileClassroomTokens.entryStroke).allowsHitTesting(false) }
                .contentShape(Circle())
        }.buttonStyle(MobileClassroomEntryStyle()).accessibilityLabel(EduI18n.text("mobileClassroom"))
            .accessibilityIdentifier("mobile-panel-toggle").accessibilityFocused($entryFocused)
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    @ViewBuilder private var courseware: some View {
        if let sharing = snapshot.screenSharePresenter() {
            ScreenShareStageView(userId: sharing.userId, displayName: sharing.displayName)
        } else if videoMainStage {
            MainVideoStageView(teacher: featuredTeacher, showLiveBadge: snapshot.needLive)
        } else {
            ContentCanvasView(document: document, compact: true, immersive: landscape, onOpenThumbnails: onOpenThumbnails,
                onPrevPage: { document.currentPage = max(1, document.currentPage - 1) },
                onNextPage: { document.currentPage = min(document.totalPages, document.currentPage + 1) }, onFullscreen: onFullscreen)
        }
    }
}

private struct MobileClassroomEntryStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? MobileClassroomTokens.entryPressedScale : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: MobileClassroomTokens.pressMotionMs / 1000), value: configuration.isPressed)
    }
}

/// Only the leading corners are rounded; the trailing edge joins the window edge.
struct MobileDrawerShape: Shape {
    var radius: CGFloat
    func path(in rect: CGRect) -> Path {
        Path(UIBezierPath(roundedRect: rect, byRoundingCorners: [.topLeft, .bottomLeft], cornerRadii: CGSize(width: radius, height: radius)).cgPath)
    }
}
