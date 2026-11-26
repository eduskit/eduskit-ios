import SwiftUI
import UIKit
import DrawsKit
import EduSDK

private enum ChatTokens {
    static let inset: CGFloat = 16
    static let gap: CGFloat = 12
    static let metaGap: CGFloat = 8
    static let controlHeight: CGFloat = 44
    static let bodySize: CGFloat = 14
    static let metaSize: CGFloat = MobileClassroomTokens.metaSize
    static let bubbleWidth: CGFloat = 0.82
    static let emptyHeight: CGFloat = 180
    static let outlineWidth: CGFloat = 1
    static let maxInputLength = 4000
    static let millisecondsPerSecond: Double = 1000
}

struct ClassroomChatView: View {
    let messages: [ClassroomChatMessageView]
    let currentUserId: String
    let onSendMessage: (String) async -> Bool
    var sendPermissionDenied: Bool = false
    var compact: Bool = false
    var folded: Bool = false
    var onNotice: (String) -> Void = { _ in }
    @State private var draft = ""
    @State private var reactionsOpen = false
    @FocusState private var composerFocused: Bool
    @State private var sending = false
    @State private var sendTask: Task<Void, Never>?
    @State private var historyAnchor: String?
    @State private var browsingHistory = false
    @Environment(\.liveUiSnapshot) private var liveSnapshot
    private var readOnly: Bool { liveSnapshot.map { $0.classroomView.runtime.mode != "active" } ?? false }
    @Environment(\.chatHistoryControls) private var history

    private func send() { submit(draft) }

    private func submit(_ submittedDraft: String) {
        let content = submittedDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !sendPermissionDenied, !readOnly, !sending else { return }
        sending = true
        sendTask = Task { @MainActor in
            let success = await onSendMessage(content)
            guard !Task.isCancelled else { return }
            if success {
                if draft == submittedDraft { draft = "" }
                browsingHistory = false
            }
            sending = false
            sendTask = nil
        }
    }

    @ViewBuilder private var historyHeader: some View {
        if history.loading || history.error || history.hasMore {
        Button {
            historyAnchor = messages.first?.id
            browsingHistory = !messages.isEmpty
            history.load()
        } label: {
            HStack(spacing: ChatTokens.metaGap) {
                if history.loading { ProgressView().tint(EduColors.onSurfaceVariant) }
                Text(EduI18n.text(history.loading ? "chatHistoryLoading" : history.error ? "chatHistoryRetry" : history.hasMore ? "chatLoadEarlier" : "chatHistoryEnd"))
                    .font(EduFont.sans(ChatTokens.metaSize))
            }
            .foregroundStyle(history.error ? EduColors.error : EduColors.onSurfaceVariant)
            .padding(.horizontal, ChatTokens.gap)
            .frame(minHeight: ChatTokens.controlHeight)
            .background(EduColors.surfaceLowest, in: RoundedRectangle(cornerRadius: EduDimens.radius2xl))
            .overlay(RoundedRectangle(cornerRadius: EduDimens.radius2xl).stroke(EduColors.outlineVariant, lineWidth: ChatTokens.outlineWidth))
        }
        .buttonStyle(.plain)
        .disabled(!history.ready || history.loading || (!history.hasMore && !history.error))
        .frame(maxWidth: .infinity)
        } else if !messages.isEmpty {
            Text(EduI18n.text("chatHistoryEnd")).font(EduFont.sans(MobileClassroomTokens.metaSize))
                .foregroundStyle(EduColors.onSurfaceVariant).frame(maxWidth: .infinity)
                .frame(height: MobileClassroomTokens.historyCaption)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: MobileClassroomTokens.messageGap) {
                            historyHeader
                            if messages.isEmpty && history.loading {
                                ClassroomSkeleton().frame(height: min(ChatTokens.emptyHeight, max(0, geometry.size.height - ChatTokens.inset * 2)))
                            } else if messages.isEmpty {
                                VStack(spacing: ChatTokens.metaGap) {
                                    if geometry.size.height >= ChatTokens.emptyHeight {
                                        Image(systemName: "bubble.left.and.bubble.right")
                                            .font(.system(size: ChatTokens.controlHeight)).accessibilityHidden(true)
                                            .padding(.bottom, ChatTokens.metaGap)
                                    }
                                    Text(EduI18n.text(history.loading ? "chatHistoryLoading" : history.notice ?? "chatEmpty"))
                                        .font(EduFont.sans(ChatTokens.bodySize, weight: .semibold))
                                }
                                .foregroundStyle(EduColors.onSurfaceVariant)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: geometry.size.height >= ChatTokens.emptyHeight ? ChatTokens.emptyHeight : 0)
                            }
                            ForEach(messages, id: \.id) { message in
                                ChatMessageRow(message: message, isSelf: message.senderId == currentUserId, maxWidth: max(0, geometry.size.width - ChatTokens.inset * 2) * ChatTokens.bubbleWidth)
                                    .id(message.id)
                            }
                        }
                        .padding(ChatTokens.inset)
                    }
                    .accessibilityLabel(EduI18n.text("chatMessageList"))
                    .simultaneousGesture(DragGesture().onChanged { _ in browsingHistory = true })
                    .onAppear { if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                    .onChange(of: history.loading) { loading in
                        if !loading, let id = historyAnchor { proxy.scrollTo(id, anchor: .top); historyAnchor = nil }
                        else if !loading, !browsingHistory, let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                    .onChange(of: messages.last?.id) { id in
                        if !history.loading, !browsingHistory, let id { proxy.scrollTo(id, anchor: .bottom) }
                    }
                    .overlay(alignment: .bottom) {
                        if browsingHistory && !messages.isEmpty {
                            Button {
                                if let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                                browsingHistory = false
                            } label: {
                                Label(EduI18n.text("chatLatest"), systemImage: "arrow.down")
                                    .font(EduFont.sans(ChatTokens.metaSize))
                                    .padding(.horizontal, ChatTokens.gap)
                                    .frame(minHeight: ChatTokens.controlHeight)
                                    .background(EduColors.surfaceLowest, in: Capsule())
                                    .overlay(Capsule().stroke(EduColors.outlineVariant, lineWidth: ChatTokens.outlineWidth))
                            }
                            .buttonStyle(.plain).foregroundStyle(EduColors.onSurface)
                            .padding(ChatTokens.metaGap)
                        }
                    }
                }
            }
            .frame(maxHeight: folded ? 0 : .infinity)
            .clipped()
            Rectangle().fill(EduColors.outlineVariant).frame(height: ChatTokens.outlineWidth)
            if folded {
                Text(EduI18n.text("portraitChatFolded"))
                    .font(EduFont.sans(ChatTokens.bodySize))
                    .foregroundStyle(EduColors.onSurfaceVariant)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if compact && reactionsOpen {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: ChatTokens.metaGap) {
                        ForEach(["portraitQuickHello", "portraitQuickClear", "portraitQuickAgain"], id: \.self) { key in
                            Button(EduI18n.text(key)) { submit(EduI18n.text(key)) }
                                .font(EduFont.sans(ChatTokens.metaSize))
                                .padding(.horizontal, ChatTokens.gap)
                                .padding(.vertical, ChatTokens.metaGap)
                                .background(EduColors.surfaceContainer, in: Capsule())
                        }
                        Button(EduI18n.text("portraitQuickFlower")) { onNotice(EduI18n.text("portraitToastFlower")) }
                            .font(EduFont.sans(ChatTokens.metaSize))
                            .padding(.horizontal, ChatTokens.gap)
                            .padding(.vertical, ChatTokens.metaGap)
                            .background(EduColors.surfaceContainer, in: Capsule())
                    }
                    .padding(.horizontal, ChatTokens.gap)
                }
                HStack(spacing: ChatTokens.metaGap) {
                    ForEach(["👏", "👍", "🙋", "🌸", "✍️"], id: \.self) { symbol in
                        Button(symbol) { draft = String((draft + symbol).prefix(ChatTokens.maxInputLength)) }
                            .padding(.horizontal, ChatTokens.metaGap)
                            .padding(.vertical, 4)
                            .background(EduColors.surfaceLow, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal, ChatTokens.gap)
            }
            HStack(alignment: .bottom, spacing: 4) {
                if compact {
                    Button { composerFocused = false; reactionsOpen.toggle() } label: {
                        Image(systemName: "face.smiling").font(.system(size: 20)).frame(width: 44, height: 44)
                    }.buttonStyle(.plain).foregroundStyle(EduColors.onSurfaceVariant)
                        .accessibilityLabel(EduI18n.text("portraitEmoji"))
                }
                TextField(EduI18n.text(sendPermissionDenied ? "chatPermissionPlaceholder" : "chatInput"), text: $draft)
                    .font(EduFont.sans(ChatTokens.bodySize))
                    .foregroundStyle(EduColors.onSurface)
                    .padding(.horizontal, ChatTokens.gap)
                    .frame(minHeight: ChatTokens.controlHeight)
                    .background(EduColors.surfaceLow, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel(EduI18n.text("chatInputAria"))
                    .focused($composerFocused)
                    .onChange(of: composerFocused) { focused in if focused { reactionsOpen = false } }
                    .submitLabel(.send).onSubmit(send)
                    .disabled(sendPermissionDenied || readOnly)
                    .onChange(of: draft) { value in if value.count > ChatTokens.maxInputLength { draft = String(value.prefix(ChatTokens.maxInputLength)) } }
                Button(action: send) {
                    Text(EduI18n.text(sending ? "chatSending" : "chatSend"))
                        .font(EduFont.sans(ChatTokens.bodySize, weight: .semibold))
                        .padding(.horizontal, ChatTokens.inset)
                        .frame(minHeight: ChatTokens.controlHeight)
                }
                .buttonStyle(.plain)
                .foregroundStyle(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sendPermissionDenied || readOnly || sending ? EduColors.onSurfaceVariant : EduColors.onPrimary)
                .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sendPermissionDenied || readOnly || sending ? EduColors.surfaceContainer : EduColors.primary, in: RoundedRectangle(cornerRadius: EduDimens.radiusXl))
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sendPermissionDenied || readOnly || sending)
            }
            .padding(8)
        }
        .background(EduColors.surfaceLowest, ignoresSafeAreaEdges: [])
        .accentColor(EduColors.primary)
        .onDisappear { sendTask?.cancel(); sendTask = nil; sending = false }
    }
}

private struct ChatMessageRow: View {
    let message: ClassroomChatMessageView
    let isSelf: Bool
    let maxWidth: CGFloat
    var body: some View {
        VStack(alignment: isSelf ? .trailing : .leading, spacing: ChatTokens.metaGap) {
            HStack(alignment: .firstTextBaseline, spacing: ChatTokens.metaGap) {
                Text(isSelf ? EduI18n.text("chatMe") : message.senderDisplayName)
                    .lineLimit(1).truncationMode(.tail).layoutPriority(0)
                if message.sentAt > 0 {
                    Text(Date(timeIntervalSince1970: Double(message.sentAt) / ChatTokens.millisecondsPerSecond), style: .time)
                        .monospacedDigit().fixedSize().layoutPriority(1)
                }
            }
            .font(EduFont.sans(ChatTokens.metaSize)).foregroundStyle(EduColors.onSurfaceVariant)
            .frame(maxWidth: maxWidth, alignment: isSelf ? .trailing : .leading)
            Text(message.content)
                .font(EduFont.sans(ChatTokens.bodySize))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(ChatTokens.gap)
                .foregroundStyle(isSelf ? EduColors.onPrimary : EduColors.onSurface)
                .background(isSelf ? EduColors.primary : EduColors.surfaceLow, in: RoundedRectangle(cornerRadius: MobileClassroomTokens.cardRadius))
                .frame(maxWidth: maxWidth, alignment: isSelf ? .trailing : .leading)
        }
        .frame(maxWidth: .infinity, alignment: isSelf ? .trailing : .leading)
    }
}

struct MeetingSidebarView: View {
    let toolsPanel: () -> AnyView
    let participants: [ClassroomDirectoryMember]
    let stageParticipants: [ClassroomParticipant]
    let messages: [ClassroomChatMessageView]
    let currentUserId: String
    let onSendMessage: (String) async -> Bool
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
    @State private var selectedMember: ClassroomDirectoryMember?
    @State private var selectedActions: [MemberActionAvailability] = []
    @State private var policyLoading = false
    @State private var actionLoading = false

    private var anim: Animation? {
        instant ? nil : .timingCurve(0.4, 0, 0.2, 1, duration: EduMotion.sidebar)
    }

    private let tabs: [(String, String)] = [
        (EduIcons.group, EduI18n.text("tabParticipantsZh")),
        (EduIcons.chat, EduI18n.text("tabChatZh")),
        (EduIcons.ext, EduI18n.text("tools")),
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
                PopupShell(visible: true, onDismiss: { selectedMember = nil }, alignBottom: true, modal: false) {
                MemberActionsSheet(
                    memberName: member.name,
                    avatarUrl: member.avatarUrl,
                    actions: selectedActions,
                    policyLoading: policyLoading,
                    actionLoading: actionLoading,
                    onClose: { selectedMember = nil },
                    onSelect: { action in
                        actionLoading = true
                        onMemberAction(action, member.userId) {
                            actionLoading = false
                            selectedMember = nil
                        }
                    }
                )
                }
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
                                ForEach(participants, id: \.userId) { member in
                                    DirectoryMemberRow(member: member, rowHeight: MobileClassroomTokens.directoryRow,
                                        onSelect: { selectedMember = member; selectedActions = []; policyLoading = true; onLoadMemberActions(member.userId) { selectedActions = $0; policyLoading = false } }, onAction: onMemberAction)
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
                    }
                case 1:
                    ClassroomChatView(
                        messages: messages,
                        currentUserId: currentUserId,
                        onSendMessage: onSendMessage,
                        sendPermissionDenied: sendPermissionDenied
                    )
                default:
                    toolsPanel()
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
            participants: stageParticipants,
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
    static let avatarSize: CGFloat = 46
    static let rowSpacing: CGFloat = 6
    static let padding: CGFloat = FeedbackTokens.padding
    static let outerPadding: CGFloat = FeedbackTokens.inset
    static let cornerRadius: CGFloat = FeedbackTokens.radius
    static let shadowRadius: CGFloat = 24
}

struct MemberActionsSheet: View {
    let memberName: String
    let avatarUrl: String?
    let actions: [MemberActionAvailability]
    var policyLoading: Bool = false
    var actionLoading: Bool
    let onClose: () -> Void
    let onSelect: (String) -> Void

    private var executable: [MemberActionAvailability] {
        actions.filter { $0.available && $0.action != MemberActionTokens.viewPermissions }
    }


    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                RemoteAvatarImage(avatarUrl: avatarUrl)
                    .frame(width: MemberActionsSheetMetrics.avatarSize, height: MemberActionsSheetMetrics.avatarSize)
                    .clipShape(Circle())
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
    var sheet: Bool = false
    var onNotice: (String) -> Void = { _ in }

    @ObservedObject private var host = WhiteboardHost.shared
    @State private var selectedPage = 1
    @State private var jumpText = ""

    private enum Tokens {
        static let gridSpacing: CGFloat = 12
        static let cellHeight: CGFloat = 72
        static let columns = 4
        static let sheetColumns = 3
        static let panelPadding: CGFloat = 20
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
            count: sheet ? Tokens.sheetColumns : Tokens.columns
        )
    }

    private func jump(_ page: Int) {
        guard page >= 1, page <= totalPages else {
            onNotice(EduI18n.text("portraitToastBadPage"))
            return
        }
        let moved = hasCourseware ? WhiteboardHost.shared.gotoStep(page - 1) : WhiteboardHost.shared.gotoBoardIndex(page)
        if moved { onDismiss() }
    }

    private var hasCourseware: Bool { host.coursewarePageCount > 0 }
    private var whiteboardPermissionDenied: Bool {
        host.localEditRestrictionReason == "permission_denied"
    }
    private var totalPages: Int {
        hasCourseware ? max(host.coursewarePageCount, 1) : max(host.boardTotal, 1)
    }

    var body: some View {
        let rows = ceil(CGFloat(totalPages + (hasCourseware ? 0 : 1)) / CGFloat(sheet ? Tokens.sheetColumns : Tokens.columns))
        CoursewarePanelViewport(preferredHeight: rows * (Tokens.cellHeight + Tokens.gridSpacing) + (sheet ? 160 : 100), alignBottom: sheet) {
        VStack(alignment: .leading, spacing: Tokens.gridSpacing) {
            HStack {
                Text(EduI18n.text("thumbnailWhiteboard"))
                    .font(EduFont.sans(Tokens.titleSize, weight: .semibold))
                Spacer()
                Button(action: onDismiss) {
                    EduIcon(EduIcons.close, size: Tokens.iconSize, tint: EduColors.onSurfaceVariant).frame(width: 44, height: 44)
                }
                .buttonStyle(EduPressButtonStyle())
                .accessibilityLabel(EduI18n.text("close"))
            }
            if hasCourseware, !host.coursewareTitle.isEmpty {
                Text(host.coursewareTitle)
                    .font(EduFont.sans(Tokens.labelSize, weight: .medium))
                    .foregroundStyle(EduColors.onSurfaceVariant)
                    .lineLimit(1)
            }
            ScrollView {
            LazyVGrid(columns: columns, spacing: Tokens.gridSpacing) {
                ForEach(1...totalPages, id: \.self) { page in
                    let selected = page == (sheet ? selectedPage : host.boardIndex)
                    let url = host.coursewareThumbUrls.indices.contains(page - 1)
                        ? host.coursewareThumbUrls[page - 1]
                        : ""
                    Button {
                        if sheet { selectedPage = page } else { jump(page) }
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
                    .accessibilityLabel(EduI18n.text(selected ? "thumbnailPageActive" : "thumbnailPage", ["page": page]))
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
            }.frame(maxHeight: .infinity).clipped()
                .accessibilityElement(children: .contain)
                .accessibilityLabel(EduI18n.text("thumbnailWhiteboard"))
                .accessibilityIdentifier("thumbnail-grid")
            if sheet {
                HStack {
                    TextField(EduI18n.text("portraitJumpLabel"), text: $jumpText)
                        .keyboardType(.numberPad).frame(minHeight: 44)
                        .disabled(whiteboardPermissionDenied)
                    Button(EduI18n.text("portraitJumpAction")) {
                        jump(Int(jumpText) ?? selectedPage)
                    }.frame(minWidth: 44, minHeight: 44)
                        .disabled(whiteboardPermissionDenied)
                }
            }
        }
        .padding(Tokens.panelPadding)
        .accessibilityIdentifier("thumbnail-panel")
        }
        .onAppear {
            selectedPage = host.boardIndex
            WhiteboardHost.shared.refreshCourseware()
        }
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
    @ObservedObject var controller: ClassroomController
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
                    case 0: continuationPanel
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

    private var continuationPanel: some View {
        let view = controller.snapshot.continuation?.settings
        let ready = view != nil && (view?.storage == "ready" || view?.storage == "saving")
        let media = view?.settings.media
        return VStack(alignment: .leading, spacing: 12) {
            Text(EduI18n.text(continuationStatusKey(view)))
                .font(EduFont.sans(13))
                .foregroundStyle(EduColors.secondary)
            continuationToggle("continuationAutoWindow", media?.autoWindow == true, ready) {
                controller.updateContinuationPreference("auto_window", enabled: $0)
            }
            continuationToggle("continuationBackgroundAudio", media?.backgroundAudio == true, ready) {
                controller.updateContinuationPreference("background_audio", enabled: $0)
            }
            continuationToggle("continuationBackgroundMicrophone", media?.backgroundMicrophone == true, ready) {
                controller.updateContinuationPreference("background_microphone", enabled: $0)
            }
            Text(EduI18n.text("continuationWindowCloseSetting"))
                .font(EduFont.sans(14, weight: .semibold))
            ForEach(Array([
                (nil as String?, "continuationAskEveryTime"),
                ("continue", "continuationCloseContinue"),
                ("leave", "continuationCloseLeave"),
            ].enumerated()), id: \.offset) { _, item in
                let selected = view?.settings.windowClose == item.0
                Button {
                    controller.updateContinuationPreference("window_close", choice: item.0)
                } label: {
                    Text(EduI18n.text(item.1))
                        .font(EduFont.sans(14))
                        .foregroundStyle(selected ? EduColors.onPrimary : EduColors.onSurface)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(selected ? EduColors.primary : EduColors.chipBg)
                        .clipShape(RoundedRectangle(cornerRadius: EduDimens.radiusLg))
                }
                .buttonStyle(EduPressButtonStyle())
                .disabled(!ready)
            }
            Text(EduI18n.text("continuationMobileSettingsNote"))
                .font(EduFont.sans(13))
                .foregroundStyle(EduColors.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func continuationStatusKey(_ view: ContinuationSettingsView?) -> String {
        guard let view else { return "continuationSettingsUnavailable" }
        switch view.storage {
        case "failed": return "continuationSettingsFailed"
        case "loading": return "appLoading"
        case "saving": return "continuationSettingsSaving"
        default: return "continuationSettingsSaved"
        }
    }

    private func continuationToggle(_ key: String, _ checked: Bool, _ enabled: Bool, change: @escaping (Bool) -> Void) -> some View {
        Toggle(isOn: Binding(get: { checked }, set: change)) {
            Text(EduI18n.text(key)).font(EduFont.sans(14))
        }
        .disabled(!enabled)
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
