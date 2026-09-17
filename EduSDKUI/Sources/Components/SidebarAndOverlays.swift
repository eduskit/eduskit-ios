import SwiftUI
import UIKit
import DrawsKit
import EduSDK

struct ClassroomChatView: View {
    let messages: [ImMessage]
    let currentUserId: String
    let onSendMessage: (String) -> Void
    var sendPermissionDenied: Bool = false
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty {
                VStack(spacing: 6) {
                    Text(EduI18n.text("chatEmpty"))
                    Text(EduI18n.text("chatEmptyHint")).font(EduFont.sans(12))
                }
                .foregroundStyle(EduColors.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(messages, id: \.id) { message in
                            VStack(alignment: message.senderId == currentUserId ? .trailing : .leading, spacing: 4) {
                                Text(message.senderId == currentUserId ? EduI18n.text("chatMe") : message.senderId)
                                    .font(EduFont.sans(11))
                                    .foregroundStyle(EduColors.onSurfaceVariant)
                                Text(message.content)
                                    .padding(8)
                                    .background(EduColors.surfaceLow, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .frame(maxWidth: .infinity, alignment: message.senderId == currentUserId ? .trailing : .leading)
                        }
                    }
                    .padding(12)
                }
            }
            HStack(spacing: 8) {
                TextField(EduI18n.text(sendPermissionDenied ? "chatPermissionPlaceholder" : "chatInput"), text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .disabled(sendPermissionDenied)
                Button(EduI18n.text(sendPermissionDenied ? "permissionUnavailableShort" : "chatSend")) {
                    let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft = ""
                    onSendMessage(content)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sendPermissionDenied)
            }
            .padding(8)
        }
    }
}

struct MeetingSidebarView: View {
    let participants: [ClassroomParticipant]
    let messages: [ImMessage]
    let currentUserId: String
    let onSendMessage: (String) -> Void
    var sendPermissionDenied: Bool = false
    var membersNextCursor: String? = nil
    var membersLoading: Bool = false
    var onLoadMoreMembers: () -> Void = {}
    var onLoadMemberActions: (String, @escaping ([MemberActionAvailability]) -> Void) -> Void = { _, callback in callback([]) }
    var onMemberAction: (String, String, @escaping () -> Void) -> Void = { _, _, done in done() }
    let videoLayout: VideoLayout
    let videoWallOpen: Bool
    @Binding var collapsed: Bool
    var instant: Bool = false
    var flipClip: Bool = false
    var namespace: Namespace.ID? = nil
    var showLiveBadge: Bool = false

    @State private var tab = 0
    @State private var selectedMember: ClassroomParticipant?
    @State private var selectedActions: [MemberActionAvailability] = []
    @State private var policyLoading = false
    @State private var actionLoading = false
    private var onStage: [ClassroomParticipant] { participants.filter(\.onStage) }
    private var audience: [ClassroomParticipant] { participants.filter { !$0.onStage } }

    private var anim: Animation? {
        instant ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.sidebar)
    }

    private let tabs: [(String, String)] = [
        (EduIcons.group, EduI18n.text("tabParticipantsZh")),
        (EduIcons.chat, EduI18n.text("tabChatZh")),
        (EduIcons.ext, EduI18n.text("activity")),
    ]

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                panel
                    .frame(width: collapsed ? 0 : EduDimens.sidebarWidth)
                    .opacity(collapsed ? 0 : 1)
                    .offset(x: collapsed ? 12 : 0)
                    .clipped()
            }
            .frame(width: (collapsed ? 0 : EduDimens.sidebarWidth) + 28)

            // Edge half-capsule toggle (28×48), vertically centered on left of panel
            Button {
                withAnimation(anim) { collapsed.toggle() }
            } label: {
                let shape = EduRoundedCorners(topLeading: 12, bottomLeading: 12, bottomTrailing: 0, topTrailing: 0)
                EduIcon(
                    collapsed ? EduIcons.chevronLeft : EduIcons.chevronRight,
                    size: 18,
                    tint: EduColors.onSurfaceVariant
                )
                .frame(width: 28, height: 48)
                .background(EduColors.surfaceLowest)
                .clipShape(shape)
                .overlay(shape.stroke(EduColors.surfaceLow, lineWidth: 1))
                .eduShadow(.soft)
            }
            .buttonStyle(EduPressButtonStyle())
            .frame(maxHeight: .infinity, alignment: .center)
        }
        .animation(anim, value: collapsed)
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

    private var panel: some View {
        VStack(spacing: 0) {
            if videoLayout == .rightTop && !videoWallOpen {
                stripSlot
            }

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { i, item in
                    let active = tab == i
                    let fillWhenActive = i == 0
                    Button { tab = i } label: {
                        VStack(spacing: 8) {
                            EduIcon(
                                item.0,
                                size: 20,
                                filled: active && fillWhenActive,
                                tint: active ? EduColors.primary : EduColors.onSurfaceVariant
                            )
                            Text(item.1)
                                .font(EduFont.sans(12, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(active ? EduColors.primary : EduColors.onSurfaceVariant)
                            Rectangle()
                                .fill(active ? EduColors.primary : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(active ? EduColors.surface : Color.clear)
                    }
                    .buttonStyle(EduPressButtonStyle())
                }
            }
            .background(EduColors.surfaceLow.opacity(0.3))

            Rectangle()
                .fill(EduColors.surfaceLow)
                .frame(height: 1)

            Group {
                switch tab {
                case 0:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if participants.isEmpty {
                                placeholder(EduI18n.text("emptyParticipants"))
                            } else {
                                if !onStage.isEmpty {
                                    section(EduI18n.text("sectionOnStage"))
                                    ForEach(onStage) { member in
                                        ParticipantListItemView(participant: member) {
                                            selectedMember = member
                                            selectedActions = []
                                            policyLoading = true
                                            onLoadMemberActions(member.id) { selectedActions = $0; policyLoading = false }
                                        }
                                    }
                                }
                                if !audience.isEmpty {
                                    if !onStage.isEmpty {
                                        Spacer().frame(height: 32)
                                    }
                                    section(EduI18n.text("sectionInAudience"))
                                    ForEach(audience) { member in
                                        ParticipantListItemView(participant: member) {
                                            selectedMember = member
                                            selectedActions = []
                                            policyLoading = true
                                            onLoadMemberActions(member.id) { selectedActions = $0; policyLoading = false }
                                        }
                                    }
                                }
                                if membersNextCursor != nil || membersLoading {
                                    placeholder(
                                        EduI18n.text(membersLoading ? "membersLoadingMore" : "membersLoadMore")
                                    )
                                    .onAppear {
                                        if membersNextCursor != nil && !membersLoading {
                                            onLoadMoreMembers()
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                case 1:
                    ClassroomChatView(
                        messages: messages,
                        currentUserId: currentUserId,
                        onSendMessage: onSendMessage,
                        sendPermissionDenied: sendPermissionDenied
                    )
                default:
                    placeholder(EduI18n.text("activitiesPlaceholder"))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if videoLayout == .rightBottom && !videoWallOpen {
                stripSlot
            }
        }
        .frame(width: EduDimens.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(EduColors.surfaceLowest)
        .overlay(alignment: .leading) {
            Rectangle().fill(EduColors.outlineVariant.opacity(0.35)).frame(width: 1)
        }
        .modifier(FlipClipModifier(enabled: flipClip))
    }

    static func bindsStripVideo(collapsed: Bool) -> Bool {
        !collapsed
    }

    @ViewBuilder
    private var stripSlot: some View {
        ParticipantStripView(
            participants: onStage,
            vertical: true,
            namespace: namespace,
            bindVideo: Self.bindsStripVideo(collapsed: collapsed),
            showLiveBadge: showLiveBadge
        )
            .frame(height: EduDimens.sidebarStripHeight)
            .padding(.horizontal, 8)
            .clipped()
    }

    private func section(_ title: String) -> some View {
        // Web `.edu-plist__label` — 11/600/0.1em/on-surface-variant.
        Text(title)
            .font(EduFont.sans(11, weight: .semibold))
            .tracking(1.1)
            .foregroundStyle(EduColors.onSurfaceVariant)
            .padding(.vertical, 8)
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .font(EduFont.sans(14))
            .foregroundStyle(EduColors.onSurfaceVariant)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(32)
    }
}

private struct FlipClipModifier: ViewModifier {
    var enabled: Bool
    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.clipped()
        } else {
            content
        }
    }
}

public struct MemberActionAvailability: Hashable {
    public let action: String
    public let available: Bool
    public let reason: String?

    public init(action: String, available: Bool, reason: String?) {
        self.action = action
        self.available = available
        self.reason = reason
    }
}

enum MemberActionTokens {
    static let viewPermissions = "view_permissions"
}

private enum MemberActionsSheetMetrics {
    static let rowSpacing: CGFloat = 6
    static let padding: CGFloat = 18
    static let outerPadding: CGFloat = 16
    static let cornerRadius: CGFloat = 20
    static let shadowRadius: CGFloat = 24
}

struct MemberActionsSheet: View {
    let memberName: String
    let actions: [MemberActionAvailability]
    var policyLoading: Bool = false
    var actionLoading: Bool
    let onClose: () -> Void
    let onSelect: (String) -> Void

    private var executable: [MemberActionAvailability] {
        actions.filter { $0.available && $0.action != MemberActionTokens.viewPermissions }
    }

    private var initials: String {
        memberName.split(whereSeparator: { $0 == " " || $0 == "　" })
            .prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(initials.isEmpty ? "?" : initials)
                    .font(EduFont.sans(14, weight: .bold))
                    .foregroundStyle(EduColors.primary)
                    .frame(width: 46, height: 46)
                    .background(EduColors.surfaceHigh, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(memberName).font(EduFont.sans(16, weight: .bold))
                }
                Spacer()
                Button(action: onClose) {
                    EduIcon(EduIcons.close, size: 20, tint: EduColors.onSurfaceVariant)
                        .frame(width: 34, height: 34)
                        .background(EduColors.surfaceLow, in: Circle())
                }
                .buttonStyle(EduPressButtonStyle())
            }
            .padding(.bottom, 16)

            Rectangle().fill(EduColors.surfaceLow).frame(height: 1)

            if policyLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else if executable.isEmpty {
                VStack(spacing: 8) {
                    EduIcon("verified_user", size: 26, tint: EduColors.primary)
                    Text(EduI18n.text("memberActionsEmpty"))
                        .font(EduFont.sans(14, weight: .semibold))
                    Text(EduI18n.text("memberActionsNoPermission"))
                        .font(EduFont.sans(12))
                        .foregroundStyle(EduColors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: MemberActionsSheetMetrics.rowSpacing),
                              GridItem(.flexible(), spacing: MemberActionsSheetMetrics.rowSpacing)],
                    spacing: MemberActionsSheetMetrics.rowSpacing
                ) {
                    ForEach(executable, id: \.action) { item in
                        Button {
                            onSelect(item.action)
                        } label: {
                            HStack(spacing: 11) {
                                EduIcon(memberActionIcon(item.action), size: 19,
                                        tint: memberActionIsDestructive(item.action) ? EduColors.error : EduColors.primary)
                                    .frame(width: 20)
                                Text(memberActionLabel(item.action))
                                    .font(EduFont.sans(13, weight: .semibold))
                                    .foregroundStyle(memberActionIsDestructive(item.action) ? EduColors.error : EduColors.onSurface)
                                Spacer()
                                EduIcon(EduIcons.chevronRight, size: 17, tint: EduColors.onSurfaceVariant)
                            }
                            .padding(.horizontal, 12)
                            .frame(minHeight: 44)
                            .frame(maxWidth: .infinity)
                            .background(
                                memberActionIsDestructive(item.action)
                                    ? EduColors.error.opacity(0.07)
                                    : EduColors.surfaceLow,
                                in: RoundedRectangle(cornerRadius: 11)
                            )
                        }
                        .buttonStyle(EduPressButtonStyle())
                        .disabled(actionLoading)
                    }
                }
                .padding(.top, 14)
            }

            if actionLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(EduI18n.text("memberActionsWorking"))
                        .font(EduFont.sans(12))
                        .foregroundStyle(EduColors.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            }
        }
        .padding(MemberActionsSheetMetrics.padding)
        .background(EduColors.surface, in: RoundedRectangle(cornerRadius: MemberActionsSheetMetrics.cornerRadius))
        .shadow(radius: MemberActionsSheetMetrics.shadowRadius)
        .padding(MemberActionsSheetMetrics.outerPadding)
    }
}

private func memberActionIcon(_ action: String) -> String {
    if action.contains("microphone") { return EduIcons.mic }
    if action.contains("camera") { return EduIcons.videocam }
    if action.contains("chat") { return EduIcons.chat }
    if action.contains("whiteboard") { return EduIcons.edit }
    if action.contains("screen_share") { return EduIcons.screenShare }
    if action.contains("raise_hand") { return "front_hand" }
    return "podium"
}

private func memberActionIsDestructive(_ action: String) -> Bool {
    ["remove_from_stage", "reject_raise_hand", "mute_microphone", "mute_camera",
     "revoke_microphone", "revoke_camera", "mute_chat", "revoke_whiteboard",
     "revoke_screen_share"].contains(action)
}

func memberActionLabel(_ action: String) -> String {
    let map: [String: String] = [
        "invite_on_stage": "memberActionInviteOnStage", "remove_from_stage": "memberActionRemoveFromStage",
        "approve_raise_hand": "memberActionApproveRaiseHand", "reject_raise_hand": "memberActionRejectRaiseHand",
        "mute_microphone": "memberActionMuteMicrophone", "mute_camera": "memberActionMuteCamera",
        "prompt_open_microphone": "memberActionPromptOpenMicrophone", "prompt_open_camera": "memberActionPromptOpenCamera",
        "grant_microphone": "memberActionGrantMicrophone", "revoke_microphone": "memberActionRevokeMicrophone",
        "grant_camera": "memberActionGrantCamera", "revoke_camera": "memberActionRevokeCamera",
        "mute_chat": "memberActionMuteChat", "unmute_chat": "memberActionUnmuteChat",
        "grant_whiteboard": "memberActionGrantWhiteboard", "revoke_whiteboard": "memberActionRevokeWhiteboard",
        "grant_screen_share": "memberActionGrantScreenShare", "revoke_screen_share": "memberActionRevokeScreenShare",
    ]
    return EduI18n.text(map[action] ?? action)
}

// MARK: - Modal enter transition (opacity + offset y:12 + scale 0.96)

struct EduModalEnterModifier: ViewModifier {
    var visible: Bool

    func body(content: Content) -> some View {
        content
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 12)
            .scaleEffect(visible ? 1 : 0.96)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.modal), value: visible)
    }
}

extension View {
    func eduModalEnter(visible: Bool) -> some View {
        modifier(EduModalEnterModifier(visible: visible))
    }
}

struct ModalScrimHost<Content: View>: View {
    let visible: Bool
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        if visible {
            ZStack {
                // L2.6 scrim: onSurface 40% mix + tiered blur backdrop.
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(EduTint.onSurface40)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)
                    .transition(.opacity)
                content()
                    .eduModalEnter(visible: true)
            }
            .transition(.opacity)
            .animation(.timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.modal), value: visible)
        }
    }
}

struct VideoWallView: View {
    let participants: [ClassroomParticipant]
    var namespace: Namespace.ID? = nil
    var onClose: () -> Void
    var showLiveBadge: Bool = false

    private let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(EduTint.onSurface40)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
            VStack(spacing: 0) {
                HStack {
                    Text(EduI18n.text("videoWallTitle"))
                        .font(EduFont.sans(18, weight: .semibold))
                    Spacer()
                    Button(action: onClose) {
                        EduIcon(EduIcons.close, size: 22, tint: EduColors.onSurfaceVariant)
                    }
                    .buttonStyle(EduPressButtonStyle())
                }
                .padding(16)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(participants) { p in
                            if let namespace {
                                ParticipantVideoTile(participant: p, showLiveBadge: showLiveBadge)
                                    .matchedGeometryEffect(id: p.id, in: namespace)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ParticipantVideoTile(participant: p, showLiveBadge: showLiveBadge).frame(maxWidth: .infinity)
                            }
                        }
                    }
                    .padding(16)
                }
            }
            .eduGlass(cornerRadius: EduDimens.radius2xl, borderColor: EduColors.surfaceLow, tier: .level3)
            .padding(24)
        }
    }
}

/// 白板缩略：有课件时用 `getThumbnailImages` 预览并 `gotoStep`；
/// 无课件时按 board 页码网格 + `gotoBoardIndex`，末尾 `+` 新增 board。
/// 与 Android `ThumbnailPopover` 对齐。
struct ThumbnailPopoverView: View {
    var onDismiss: () -> Void

    @ObservedObject private var host = WhiteboardHost.shared

    private enum Tokens {
        static let gridSpacing: CGFloat = 12
        static let cellHeight: CGFloat = 72
        static let columns = 4
        static let panelPadding: CGFloat = 20
        static let outerPadding: CGFloat = 40
        static let iconSize: CGFloat = 22
        static let titleSize: CGFloat = 18
        static let labelSize: CGFloat = 14
        static let borderSelected: CGFloat = 2
        static let borderIdle: CGFloat = 1
        /// 与 Android ThumbnailPopoverTokens.RasterMaxEdgePx 对齐
        static let rasterMaxEdgePx: UInt32 = 320
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Tokens.gridSpacing),
            count: Tokens.columns
        )
    }

    private var hasCourseware: Bool { host.coursewarePageCount > 0 }
    private var whiteboardPermissionDenied: Bool {
        host.localEditRestrictionReason == "permission_denied"
    }
    private var totalPages: Int {
        hasCourseware ? max(host.coursewarePageCount, 1) : max(host.boardTotal, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.gridSpacing) {
            HStack {
                Text(EduI18n.text("thumbnailWhiteboard"))
                    .font(EduFont.sans(Tokens.titleSize, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    EduIcon(EduIcons.close, size: Tokens.iconSize, tint: EduColors.onSurfaceVariant)
                }
                .buttonStyle(EduPressButtonStyle())
            }
            if hasCourseware, !host.coursewareTitle.isEmpty {
                Text(host.coursewareTitle)
                    .font(EduFont.sans(Tokens.labelSize, weight: .medium))
                    .foregroundStyle(EduColors.onSurfaceVariant)
                    .lineLimit(1)
            }
            LazyVGrid(columns: columns, spacing: Tokens.gridSpacing) {
                ForEach(1...totalPages, id: \.self) { page in
                    let selected = page == host.boardIndex
                    let url = host.coursewareThumbUrls.indices.contains(page - 1)
                        ? host.coursewareThumbUrls[page - 1]
                        : ""
                    Button {
                        if hasCourseware {
                            guard WhiteboardHost.shared.gotoStep(page - 1) else { return }
                        } else {
                            guard WhiteboardHost.shared.gotoBoardIndex(page) else { return }
                        }
                        onDismiss()
                    } label: {
                        ZStack {
                            if url.isEmpty {
                                Text("\(page)")
                                    .font(EduFont.sans(Tokens.labelSize, weight: .semibold))
                            } else {
                                CoursewareThumbImageView(
                                    url: url,
                                    fallbackLabel: "\(page)",
                                    labelSize: Tokens.labelSize,
                                    rasterMaxEdgePx: Tokens.rasterMaxEdgePx
                                )
                            }
                        }
                        .frame(height: Tokens.cellHeight)
                        .frame(maxWidth: .infinity)
                        .background(EduColors.surfaceLow)
                        .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
                        .overlay(
                            RoundedRectangle(cornerRadius: EduDimens.radiusLg)
                                .stroke(
                                    selected ? EduColors.primary : EduColors.outlineVariant,
                                    lineWidth: selected ? Tokens.borderSelected : Tokens.borderIdle
                                )
                        )
                    }
                    .buttonStyle(EduPressButtonStyle())
                    .disabled(whiteboardPermissionDenied)
                }
                if !hasCourseware {
                    Button {
                        guard WhiteboardHost.shared.addBoard() != nil else { return }
                        onDismiss()
                    } label: {
                        EduIcon(EduIcons.add, size: Tokens.iconSize, tint: EduColors.onSurfaceVariant)
                            .frame(height: Tokens.cellHeight)
                            .frame(maxWidth: .infinity)
                            .background(EduColors.surfaceLow)
                            .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
                            .overlay(
                                RoundedRectangle(cornerRadius: EduDimens.radiusLg)
                                    .stroke(EduColors.outlineVariant, lineWidth: Tokens.borderIdle)
                            )
                    }
                    .buttonStyle(EduPressButtonStyle())
                    .disabled(whiteboardPermissionDenied)
                    .accessibilityLabel(Text(EduI18n.text("ariaAddWhiteboard")))
                }
            }
        }
        .padding(Tokens.panelPadding)
        .eduGlass(cornerRadius: EduDimens.radius2xl, borderColor: EduColors.surfaceLow, tier: .soft)
        .padding(Tokens.outerPadding)
        .onAppear { WhiteboardHost.shared.refreshCourseware() }
    }
}

/// 课件缩略图：栅格直接解码；SVG 经 `NativeEngine.rasterizeCoursewareSvg`（与白板/Android 同源）。
private struct CoursewareThumbImageView: View {
    let url: String
    let fallbackLabel: String
    let labelSize: CGFloat
    let rasterMaxEdgePx: UInt32

    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(4)
            } else {
                Text(fallbackLabel)
                    .font(EduFont.sans(labelSize, weight: .semibold))
            }
        }
        .task(id: url) {
            image = nil
            image = await Self.loadThumb(url: url, maxEdge: rasterMaxEdgePx)
        }
    }

    private static func isSvgThumbUrl(_ url: String) -> Bool {
        let path = url.split(separator: "?").first.map(String.init)?.lowercased() ?? ""
        return path.hasSuffix(".svg")
    }

    private static func loadThumb(url: String, maxEdge: UInt32) async -> UIImage? {
        guard let remote = URL(string: url) else { return nil }
        do {
            let (data, response) = try await URLSession.shared.data(from: remote)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                NSLog("[ThumbnailPopover] thumb HTTP %d url=%@", http.statusCode, url)
                return nil
            }
            if isSvgThumbUrl(url) {
                guard let png = NativeEngine.rasterizeCoursewareSvg(
                    data,
                    width: maxEdge,
                    height: maxEdge
                ) else {
                    NSLog("[ThumbnailPopover] svg rasterize failed url=%@", url)
                    return nil
                }
                return UIImage(data: png)
            }
            return UIImage(data: data)
        } catch {
            NSLog("[ThumbnailPopover] thumb load failed: %@ url=%@", error.localizedDescription, url)
            return nil
        }
    }
}

struct SettingsModalView: View {
    var onDismiss: () -> Void
    var onCheckDevices: () -> Void = {}
    @State private var tab = 1
    @State private var cameraId = DemoData.cameraDevices[0].id
    @State private var resolution = "720p"
    @State private var micId = DemoData.micDevices[0].id
    @State private var speakerId = DemoData.speakerDevices[0].id

    private let tabs: [(String, String)] = [
        (EduIcons.settings, EduI18n.text("settingsGeneral")),
        (EduIcons.videocam, EduI18n.text("settingsVideo")),
        (EduIcons.volumeUp, EduI18n.text("settingsAudio")),
        (EduIcons.ext, EduI18n.text("settingsBackground")),
        (EduIcons.ext, EduI18n.text("settingsEffects")),
        (EduIcons.ext, EduI18n.text("settingsStatistics")),
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(EduI18n.text("ariaSettings"))
                    .font(EduFont.sans(18, weight: .semibold))
                    .padding(.bottom, 12)
                ForEach(Array(tabs.enumerated()), id: \.offset) { i, item in
                    let active = tab == i
                    Button { tab = i } label: {
                        HStack(spacing: 8) {
                            EduIcon(
                                item.0,
                                size: 18,
                                tint: active ? EduColors.onPrimary : EduColors.onSurfaceVariant
                            )
                            Text(item.1)
                                .font(EduFont.sans(14))
                        }
                        .foregroundStyle(active ? EduColors.onPrimary : EduColors.onSurface)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(active ? EduColors.primary : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
                    }
                    .buttonStyle(EduPressButtonStyle())
                }
                Spacer()
            }
            .padding(16)
            .frame(width: 200)
            .background(EduColors.surfaceLow)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(panelTitle)
                        .font(EduFont.sans(18, weight: .semibold))
                    Spacer()
                    Button(action: onDismiss) {
                        EduIcon(EduIcons.close, size: 22, tint: EduColors.onSurfaceVariant)
                    }
                    .buttonStyle(EduPressButtonStyle())
                }
                ScrollView {
                    switch tab {
                    case 1: videoPanel
                    case 2: audioPanel
                    default:
                        Text(EduI18n.text("settingsComingSoonShort")).foregroundStyle(EduColors.secondary)
                    }
                }
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Text(EduI18n.text("settingsDoneShort"))
                            .font(EduFont.sans(14, weight: .semibold))
                            .foregroundStyle(EduColors.onPrimary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(EduColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
                    }
                    .buttonStyle(EduPressButtonStyle())
                }
            }
            .padding(20)
        }
        .frame(width: 720, height: 560)
        .eduGlass(cornerRadius: EduDimens.radius2xl, borderColor: EduColors.surfaceLow, tier: .soft)
    }

    private var panelTitle: String {
        switch tab {
        case 1: return EduI18n.text("settingsVideoSettings")
        case 2: return EduI18n.text("settingsAudioSettings")
        default: return tabs[tab].1
        }
    }

    private var videoPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(EduI18n.text("settingsPreviewPlaceholder")).font(EduFont.sans(14, weight: .semibold))
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: EduDimens.radiusXl)
                    .fill(EduColors.surfaceContainer)
                    .frame(height: 180)
                Text(EduI18n.text("settingsYou")).padding(12)
            }
            Text(EduI18n.text("settingsCameraDeviceShort")).font(EduFont.sans(14, weight: .semibold))
            ForEach(DemoData.cameraDevices) { d in
                deviceRow(d.label, selected: d.id == cameraId) { cameraId = d.id }
            }
            Text(EduI18n.text("settingsResolutionShort")).font(EduFont.sans(14, weight: .semibold))
            HStack {
                ForEach(["720p", "1080p"], id: \.self) { r in
                    Button { resolution = r } label: {
                        Text(r)
                            .foregroundStyle(resolution == r ? EduColors.onPrimary : EduColors.onSurface)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(resolution == r ? EduColors.primary : EduColors.chipBg)
                            .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
                    }
                    .buttonStyle(EduPressButtonStyle())
                }
            }
            Button(EduI18n.text("settingsCheckDevices"), action: onCheckDevices)
                .font(EduFont.sans(14, weight: .semibold))
                .foregroundStyle(EduColors.onSurface)
        }
    }

    private var audioPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(EduI18n.text("settingsMicrophoneShort")).font(EduFont.sans(14, weight: .semibold))
            ForEach(DemoData.micDevices) { d in
                deviceRow(d.label, selected: d.id == micId) { micId = d.id }
            }
            Text(EduI18n.text("settingsSpeakerShort")).font(EduFont.sans(14, weight: .semibold))
            ForEach(DemoData.speakerDevices) { d in
                deviceRow(d.label, selected: d.id == speakerId) { speakerId = d.id }
            }
            Button(EduI18n.text("settingsCheckDevices"), action: onCheckDevices)
                .font(EduFont.sans(14, weight: .semibold))
                .foregroundStyle(EduColors.onSurface)
        }
    }

    private func deviceRow(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .foregroundStyle(selected ? EduColors.onPrimary : EduColors.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(selected ? EduColors.primary : EduColors.chipBg)
                .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
        }
        .buttonStyle(EduPressButtonStyle())
    }
}
