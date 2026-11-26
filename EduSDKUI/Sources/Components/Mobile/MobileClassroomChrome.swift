import SwiftUI
import EduSDK

struct MobileAction: View {
    let icon: String
    let label: String
    var active = false
    var enabled = true
    var iconOnly = false
    var horizontal = false
    var dockStyle = false
    var muted = false
    var action: () -> Void
    @State private var tooltip = false
    @Environment(\.verticalSizeClass) private var sizeClass
    var body: some View {
        Button(action: { tooltip = false; action() }) {
            Group {
                if horizontal { HStack(spacing: 6) { actionLabel } }
                else { VStack(spacing: 2) { actionLabel } }
            }
            .foregroundStyle(active ? EduColors.primary : EduColors.onSurfaceVariant)
            .frame(maxWidth: dockStyle ? .infinity : nil, maxHeight: dockStyle ? .infinity : nil)
            .frame(minWidth: MobileClassroomTokens.touch, minHeight: MobileClassroomTokens.touch)
            .padding(.horizontal, dockStyle ? 6 : 0)
            .padding(.vertical, dockStyle ? 3 : 0)
            .background(dockStyle ? (active ? EduColors.primarySoft : EduColors.surfaceContainer) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: iconOnly ? MobileClassroomTokens.touch : .infinity)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityLabel(label)
        .highPriorityGesture(LongPressGesture(minimumDuration: FeedbackTokens.tooltipDelayMs / 1000).onEnded { _ in tooltip = true })
        .eduTooltip(label, isPresented: $tooltip)
        .onChange(of: sizeClass) { _ in tooltip = false }
        .onDisappear { tooltip = false }
    }
    @ViewBuilder private var actionLabel: some View {
        EduIcon(icon, size: MobileClassroomTokens.actionIcon, tint: muted ? EduColors.error : active ? EduColors.primary : EduColors.onSurfaceVariant)
            .frame(width: iconOnly ? MobileClassroomTokens.actionIcon : MobileClassroomTokens.actionSurface,
                   height: iconOnly ? MobileClassroomTokens.actionIcon : MobileClassroomTokens.actionSurface)

        if !iconOnly { Text(label).font(EduFont.sans(MobileClassroomTokens.metaSize)).lineLimit(1) }
    }

}

struct MobileClassroomHeader: View {
    let snapshot: UiSnapshot
    let title: String
    let elapsed: String
    let landscape: Bool
    var onBack: () -> Void
    var onDevices: () -> Void
    var onPanel: () -> Void
    var body: some View {
        HStack(spacing: 4) {
            MobileAction(icon: EduIcons.arrowBack, label: EduI18n.text("portraitLeave"), iconOnly: true, action: onBack)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(EduColors.onSurface).lineLimit(1)
                HStack(spacing: 8) {
                    Text(snapshot.badgeText).foregroundStyle(EduColors.primary)
                        .padding(.horizontal, 6).frame(height: MobileClassroomTokens.statusHeight)
                        .background(EduColors.primarySoft, in: Capsule()).fixedSize()
                    if snapshot.timerMode != .hidden { Text(elapsed).monospacedDigit() }
                }.font(.system(size: MobileClassroomTokens.metaSize)).foregroundStyle(EduColors.onSurfaceVariant).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            MobileAction(icon: EduIcons.settings, label: EduI18n.text("mobileDevices"), iconOnly: true, action: onDevices)
            if landscape { MobileAction(icon: EduIcons.chat, label: EduI18n.text("tabChatZh"), iconOnly: true, action: onPanel) }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .frame(height: landscape ? MobileClassroomTokens.landscapeHeader : MobileClassroomTokens.header)
        .background(EduColors.surfaceLowest)
    }
}

struct MobileStageStrip: View {
    let participants: [ClassroomParticipant]
    let emptySeatCount: Int
    let vertical: Bool
    let canManage: Bool
    let showLive: Bool
    var onInvite: () -> Void
    var body: some View {
        GeometryReader { geo in
            let width = vertical ? max(0, geo.size.width - MobileClassroomTokens.gap * 2) : MobileClassroomTokens.stageWidth
            let height = width * MobileClassroomTokens.boardAspectHeight / MobileClassroomTokens.boardAspectWidth
            let count = participants.count + emptySeatCount
            ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                ZStack(alignment: .topLeading) {
                    ForEach(Array(participants.enumerated()), id: \.element.id) { index, person in
                        ParticipantVideoTile(participant: person, compact: true, showLiveBadge: showLive, fixedWidth: width)
                            .frame(width: width, height: height)
                            .offset(x: vertical ? 0 : CGFloat(index) * (width + 8), y: vertical ? CGFloat(index) * (height + 8) : 0)
                    }
                    ForEach(0..<emptySeatCount, id: \.self) { index in
                        Button(action: onInvite) {
                            VStack(spacing: 4) {
                                EduIcon("person_add", size: 24, tint: EduColors.onSurfaceVariant)
                                Text(EduI18n.text("stitchEmptySeat")).font(.system(size: 12)).foregroundStyle(EduColors.onSurfaceVariant)
                            }.frame(width: width, height: height)
                                .background(EduColors.surfaceLow, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(!canManage)
                            .offset(x: vertical ? 0 : CGFloat(participants.count + index) * (width + 8), y: vertical ? CGFloat(participants.count + index) * (height + 8) : 0)
                    }
                }.frame(width: vertical ? width : max(0, CGFloat(count) * (width + 8) - 8), height: vertical ? max(0, CGFloat(count) * (height + 8) - 8) : height, alignment: .topLeading)
                    .padding(.horizontal, vertical ? MobileClassroomTokens.gap : MobileClassroomTokens.inset).padding(.vertical, MobileClassroomTokens.gap)
            }.background(vertical ? Color(hex: MobileClassroomTokens.landscapeVideo) : EduColors.surfaceLowest, ignoresSafeAreaEdges: [])
                .overlay {
                    if count == 0 {
                        VStack(spacing: MobileClassroomTokens.gap) {
                            EduIcon("videocam_off", tint: vertical ? Color(hex: MobileClassroomTokens.landscapeControl) : EduColors.onSurfaceVariant)
                            Text(EduI18n.text("stageEmpty")).font(.system(size: MobileClassroomTokens.captionSize))
                        }.foregroundStyle(vertical ? Color(hex: MobileClassroomTokens.landscapeControl) : EduColors.onSurfaceVariant)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
        }
    }
}

struct MobileClassroomDock: View {
    let snapshot: UiSnapshot
    var embedded = false
    var mediaOnly = false
    var onMic: () -> Void
    var onCamera: () -> Void
    var onHand: () -> Void
    var onShare: () -> Void
    var onCourseware: () -> Void
    var onDevices: () -> Void
    var onStart: () -> Void
    var onEnd: () -> Void
    var onWall: () -> Void
    var onAnnotate: () -> Void
    var onSettings: () -> Void
    @State private var more = false
    private var mic: ToolbarEntry { snapshot.toolbarEntries.entry("use_microphone") }
    private var camera: ToolbarEntry { snapshot.toolbarEntries.entry("use_camera") }
    private var onStage: Bool { snapshot.onStage.contains { $0.userId == snapshot.userId } }
    private var hand: ToolbarEntry { snapshot.toolbarEntries.entry(onStage || snapshot.handRaised ? "manage_own_stage" : "raise_hand") }
    var body: some View {
        Group {
            if embedded {
                VStack(spacing: MobileClassroomTokens.gap) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: mediaOnly ? 2 : 3), spacing: MobileClassroomTokens.gap) {
                        primaryActions
                        if !mediaOnly { additionalActions }
                    }
                    if !mediaOnly { leaveAction }
                }
            } else {
                HStack(spacing: MobileClassroomTokens.gap) { primaryActions }
                    .padding(.horizontal, MobileClassroomTokens.gap)
                    .frame(height: MobileClassroomTokens.dock)
                    .background(EduColors.surfaceLowest)
            }
        }
        .sheet(isPresented: $more) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileClassroomTokens.inset) {
                    HStack {
                        Text(EduI18n.text("mobileMore")).font(.system(size: MobileClassroomTokens.titleSize, weight: .semibold))
                        Spacer()
                        MobileAction(icon: EduIcons.close, label: EduI18n.text("close"), iconOnly: true) { more = false }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: MobileClassroomTokens.sheetActionWidth))], spacing: MobileClassroomTokens.inset) { additionalActions }
                    leaveAction
                }.padding(MobileClassroomTokens.inset)
            }.background(EduColors.surfaceLowest).modifier(MobileSheetPresentation())
        }
    }
    @ViewBuilder private var primaryActions: some View {
        if mic.visible || !snapshot.audioMuted {
            action(icon: snapshot.audioMuted ? EduIcons.micOff : EduIcons.mic, label: "controlMic", active: !snapshot.audioMuted,
                enabled: (!mic.disabled || !snapshot.audioMuted) && !snapshot.busy, muted: snapshot.audioMuted, run: onMic)
        }
        if camera.visible || !snapshot.videoMuted {
            action(icon: snapshot.videoMuted ? EduIcons.videocamOff : EduIcons.videocam, label: "controlCamera", active: !snapshot.videoMuted,
                enabled: (!camera.disabled || !snapshot.videoMuted) && !snapshot.busy, muted: snapshot.videoMuted, run: onCamera)
        }
        if !mediaOnly {
            if snapshot.toolbarEntries.entry("start_class").visible && snapshot.lifecycleStatus == .notStarted {
                action(icon: "play_arrow", label: "mobileStart", active: true, enabled: !snapshot.busy && !snapshot.toolbarEntries.entry("start_class").disabled, run: onStart)
            } else if hand.visible {
                action(icon: onStage ? "vertical_align_bottom" : EduIcons.frontHand,
                    label: onStage ? "mobileStepDown" : snapshot.handRaised ? "mobileCancelHand" : "controlRaiseHand",
                    active: snapshot.handRaised, enabled: !hand.disabled && !snapshot.busy, run: onHand)
            }
            if !embedded { action(icon: "more_horiz", label: "mobileMore", active: more) { more = true } }
        }
    }
    @ViewBuilder private var additionalActions: some View {
        if snapshot.canEditWhiteboard { action(icon: EduIcons.edit, label: "mobileAnnotate") { more = false; onAnnotate() } }
        if snapshot.toolbarEntries.entry("operate_courseware").visible {
            action(icon: EduIcons.description, label: "controlSlides", enabled: !snapshot.toolbarEntries.entry("operate_courseware").disabled) { more = false; onCourseware() }
        }
        if snapshot.toolbarEntries.entry("share_screen").visible || snapshot.localScreenSharing {
            action(icon: EduIcons.screenShare, label: "controlShare", enabled: !snapshot.toolbarEntries.entry("share_screen").disabled || snapshot.localScreenSharing) { more = false; onShare() }
        }
        action(icon: EduIcons.settings, label: "mobileDevices") { more = false; onDevices() }
        action(icon: EduIcons.gridView, label: "controlVideoWall") { more = false; onWall() }
        action(icon: EduIcons.settings, label: "ariaSettings") { more = false; onSettings() }
    }
    private var leaveAction: some View {
        Button { more = false; onEnd() } label: {
            Text(EduI18n.text(snapshot.canEndClass ? "portraitEnd" : "portraitLeave"))
                .foregroundStyle(EduColors.error).frame(maxWidth: .infinity, minHeight: MobileClassroomTokens.touch)
        }.disabled(snapshot.busy)
    }
    private func action(icon: String, label: String, active: Bool = false, enabled: Bool = true, muted: Bool = false, run: @escaping () -> Void) -> some View {
        MobileAction(icon: icon, label: EduI18n.text(label), active: active, enabled: enabled, dockStyle: embedded, muted: muted, action: run)
            .frame(maxWidth: .infinity).frame(height: embedded ? MobileClassroomTokens.landscapeActionHeight : MobileClassroomTokens.touch)
    }
}

private struct MobileSheetPresentation: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.height(280), .large]).presentationDragIndicator(.visible)
        } else { content }
    }
}
