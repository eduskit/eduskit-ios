import SwiftUI
import EduSDK

struct MobileTabPanelView: View {
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
    var selectedTab: Int = 1
    var onTabChange: ((Int) -> Void)? = nil
    var chatUnread: Bool = false
    var handRaised: Bool = false
    var onToggleHand: () -> Void = {}
    var chatFolded: Bool = false
    var onNotice: (String) -> Void = { _ in }

    var landscape = false
    var classroomPanel: () -> AnyView = { AnyView(EmptyView()) }
    var settingsPanel: () -> AnyView = { AnyView(EmptyView()) }
    var onClose: () -> Void = {}
    @State private var tab = 1
    @State private var selectedMember: ClassroomParticipant?
    @State private var selectedActions: [MemberActionAvailability] = []
    @State private var policyLoading = false
    @State private var actionLoading = false
    private var labels: [String] { ["tabParticipantsZh", "tabChatZh", "tabToolsZh", "mobileClassroomTab", "settingsTitle"].map { EduI18n.text($0) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(landscape ? [3, 1, 0, 2, 4] : [1, 0, 2], id: \.self) { i in
                    let label = labels[i]
                    let active = tab == i
                    Button {
                        tab = i
                        onTabChange?(i)
                    } label: {
                        VStack(spacing: 0) {
                            Text(label).lineLimit(1)
                                .font(EduFont.sans(landscape ? MobileClassroomTokens.captionSize : MobileClassroomTokens.bodySize, weight: active ? .bold : .medium))
                                .foregroundStyle(active ? EduColors.primary : EduColors.onSurfaceVariant)
                                .overlay(alignment: .topTrailing) {
                                    if i == 1 && chatUnread {
                                        Circle().fill(EduColors.unread).frame(width: PortraitTokens.unreadDot, height: PortraitTokens.unreadDot)
                                    }
                                }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: MobileClassroomTokens.tabHeight - 8)
                        .padding(4)
                        .overlay(alignment: .bottom) { if active { Capsule().fill(EduColors.primary).frame(width: 24, height: 2) } }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(EduPressButtonStyle())
                }
                if landscape { MobileAction(icon: "chevron_right", label: EduI18n.text("close"), iconOnly: true, action: onClose) }
            }
            .frame(height: MobileClassroomTokens.tabHeight)
            .background(EduColors.surface, ignoresSafeAreaEdges: [])
            .overlay(alignment: .bottom) {
                Rectangle().fill(EduColors.surfaceVariant).frame(height: 1)
            }

            ZStack {
                ClassroomChatView(messages: messages, currentUserId: currentUserId, onSendMessage: onSendMessage,
                    sendPermissionDenied: sendPermissionDenied, compact: true, folded: chatFolded, onNotice: onNotice)
                    .accessibilityElement(children: tab == 1 ? .contain : .ignore)
                    .opacity(tab == 1 ? 1 : 0).allowsHitTesting(tab == 1).accessibilityHidden(tab != 1)
                memberDirectoryList
                    .accessibilityElement(children: tab == 0 ? .contain : .ignore)
                    .opacity(tab == 0 ? 1 : 0).allowsHitTesting(tab == 0).accessibilityHidden(tab != 0)
                if tab == 3 { classroomPanel() }
                if tab == 4 { settingsPanel() }
                if tab == 2 { toolsPanel().frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .background(EduColors.surfaceLowest, ignoresSafeAreaEdges: [])
        }
        .onAppear { tab = selectedTab }
        .onChange(of: selectedTab) { tab = $0 }
        .overlay(alignment: .bottom) {
            if let member = selectedMember {
                MemberActionsSheet(
                    memberName: member.displayName,
                    avatarUrl: member.avatarUrl,
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

    @ViewBuilder
    private var memberDirectoryList: some View {
        if members.isEmpty && membersLoading {
            ClassroomSkeleton()
        } else if members.isEmpty {
            Text(EduI18n.text("emptyParticipants")).foregroundStyle(EduColors.onSurfaceVariant)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(members, id: \.userId) { member in
                        DirectoryMemberRow(member: member, rowHeight: landscape ? MobileClassroomTokens.directoryRowLandscape : MobileClassroomTokens.directoryRowPortrait,
                            onSelect: { selectedMember = participant(member); selectedActions = []; policyLoading = true; onLoadMemberActions(member.userId) { selectedActions = $0; policyLoading = false } }, onAction: onMemberAction)
                    }
                    if membersNextCursor != nil || membersLoading {
                        Text(EduI18n.text(membersLoading ? "membersLoadingMore" : "membersLoadMore"))
                            .font(EduFont.sans(12))
                            .foregroundStyle(EduColors.onSurfaceVariant)
                            .frame(maxWidth: .infinity)
                            .onAppear {
                                if tab == 0 && membersNextCursor != nil && !membersLoading {
                                    onLoadMoreMembers()
                                }
                            }
                    }
                }
            }
        }
    }


}

private func participant(_ member: ClassroomDirectoryMember) -> ClassroomParticipant {
    ClassroomParticipant(id: member.userId, displayName: member.name, roleLabel: EduI18n.text(member.roleKey), avatarUrl: member.avatarUrl, onStage: member.onStage)
}


/// 竖屏底栏尺寸 / 间距 token（禁止魔法字面量散落）。
