import SwiftUI

@MainActor
struct TeachingToolStatusCard: View {
    let card: TeachingToolCard
    private var color: Color { switch card.statusColor { case "red": return .red; case "yellow": return .yellow; case "green": return .green; default: return .clear } }
    var body: some View {
        HStack {
            Circle().fill(color).frame(width: 24, height: 24)
            VStack(alignment: .leading) { Text(EduI18n.text("tool_color_" + (card.statusColor ?? ""))); Text(EduI18n.text("tool_work_" + (card.workMode ?? ""))) }
        }
    }
}
@MainActor
struct TeachingToolGroupsPanel: View {
    let card: TeachingToolCard
    @ObservedObject var controller: ClassroomController
    var body: some View {
        VStack(alignment: .leading) {
            if card.groups.isEmpty { Text(EduI18n.text("tool_groupsNotGenerated")) }
            else if !card.canReadDefinition && card.ownGroupId == nil { Text(EduI18n.text("tool_notGrouped")) }
            ForEach(card.groups) { group in
                VStack(alignment: .leading) {
                    Text(group.name).font(.headline)
                    if card.ownGroupId == group.id { Text(EduI18n.text("tool_myGroup")) }
                    ForEach(group.members) { member in Text(member.displayName + (member.id == group.leaderId ? " · " + EduI18n.text("tool_leader") : "")) }
                    if card.canManageGroups {
                        TeachingToolGroupEdit(card: card, group: group, controller: controller).disabled(controller.toolMutationPending(card.sessionId)).id(card.sessionId + ":" + card.revision + ":" + (card.roundId ?? "") + ":" + group.id)
                    }
                }
            }
            if card.canManageGroups {
                TeachingToolGroupTransfers(card: card, controller: controller).disabled(controller.toolMutationPending(card.sessionId)).id(card.sessionId + ":" + card.revision + ":" + (card.roundId ?? ""))
            }
        }
    }
}
@MainActor
private struct TeachingToolGroupEdit: View {
    let card: TeachingToolCard; let group: TeachingToolGroup
    @ObservedObject var controller: ClassroomController
    @State private var name: String
    @State private var leader: String
    init(card: TeachingToolCard, group: TeachingToolGroup, controller: ClassroomController) {
        self.card = card; self.group = group; self.controller = controller
        _name = State(initialValue: group.name); _leader = State(initialValue: group.leaderId ?? "")
    }
    var body: some View {
        VStack(alignment: .leading) {
            TextField(EduI18n.text("tool_groupName"), text: $name)
            Button(EduI18n.text("tool_renameGroup")) { controller.manageToolGroup(card, action: "rename_group", groupId: group.id, name: name) }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Picker(EduI18n.text("tool_leader"), selection: $leader) {
                Text(EduI18n.text("tool_noLeader")).tag("")
                ForEach(group.members) { Text($0.displayName).tag($0.id) }
            }
            Button(EduI18n.text("tool_setLeader")) { controller.manageToolGroup(card, action: "set_group_leader", groupId: group.id, first: leader.isEmpty ? nil : leader) }
            Button(EduI18n.text("tool_clearLeader")) { controller.manageToolGroup(card, action: "set_group_leader", groupId: group.id) }
        }
    }
}
@MainActor
private struct TeachingToolGroupTransfers: View {
    let card: TeachingToolCard
    @ObservedObject var controller: ClassroomController
    @State private var first = ""; @State private var second = ""; @State private var target = ""
    private func contains(_ id: String) -> Bool { card.groupMembers.contains { $0.id == id } }
    var body: some View {
        VStack(alignment: .leading) {
            Picker(EduI18n.text("tool_firstStudent"), selection: $first) {
                Text(EduI18n.text("tool_selectStudent")).tag(""); ForEach(card.groupMembers) { Text($0.displayName).tag($0.id) }
            }
            Picker(EduI18n.text("tool_targetGroup"), selection: $target) {
                Text(EduI18n.text("tool_selectGroup")).tag(""); ForEach(card.groups) { Text($0.name).tag($0.id) }
            }
            Button(EduI18n.text("tool_moveMember")) { controller.manageToolGroup(card, action: "move_member", groupId: target, first: first) }
                .disabled(!contains(first) || !card.groups.contains(where: { $0.id == target }))
            Picker(EduI18n.text("tool_secondStudent"), selection: $second) {
                Text(EduI18n.text("tool_selectStudent")).tag(""); ForEach(card.groupMembers) { Text($0.displayName).tag($0.id) }
            }
            Button(EduI18n.text("tool_swapMembers")) { controller.manageToolGroup(card, action: "swap_members", first: first, second: second) }
                .disabled(!contains(first) || !contains(second) || first == second)
        }
    }
}
