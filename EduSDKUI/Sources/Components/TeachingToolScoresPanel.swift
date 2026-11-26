import SwiftUI

@MainActor
struct TeachingToolScoresPanel: View {
    let card: TeachingToolCard
    let scores: TeachingToolScores
    @ObservedObject var controller: ClassroomController
    @State private var period = ""
    @State private var mode = "ledger"
    @State private var scope = "default"
    @State private var target = ""
    @State private var rank = "user"
    private var directory: TeachingToolStudentDirectory? { controller.toolsView?.studentDirectory }
    private var periodIds: [String] { scores.periods.map(\.periodId) + (card.roundId.map { [$0] } ?? []) }
    private var targetIds: [String] { scope == "user" ? directory?.students.map(\.userId) ?? [] : card.scoreGroups.map(\.groupId) }
    var body: some View {
        VStack(alignment: .leading) {
            if scores.canReadPeriods {
                Button(EduI18n.text("tool_scorePeriods")) { controller.loadToolScorePeriods(card) }
                if let cursor = scores.periodsCursor { Button(EduI18n.text("tool_earlierScorePeriods")) { controller.loadToolScorePeriods(card, cursor: cursor) } }
            }
            if scores.canReadLedger { queryForm }
            ForEach(scores.pages.filter { page in
                let query = page.query
                return query.periodId == period && query.view == mode && query.targetKind == (mode == "leaderboard" ? rank : scope == "default" ? nil : scope) && query.targetId == (mode == "leaderboard" || scope == "default" ? nil : target)
            }) { page in
                if (page.view == "ledger" && scores.canReadLedger) || (page.view == "leaderboard" && scores.canReadRank) {
                    TeachingToolScorePagePanel(card: card, scores: scores, page: page, directory: directory, controller: controller)
                }
            }
        }.onAppear { period = card.roundId ?? scores.periods.first?.periodId ?? "" }
            .onChange(of: card.roundId) { next in period = next ?? scores.periods.first?.periodId ?? "" }
            .onChange(of: periodIds) { ids in if !ids.contains(period) { period = ids.first ?? "" } }
            .onChange(of: card.scoreGroups.map(\.groupId)) { ids in if scope == "group" && ids.isEmpty { scope = "default"; target = "" } }
            .onChange(of: targetIds) { ids in if !ids.contains(target) { target = "" } }
            .onChange(of: scores.canReadAll) { allowed in if !allowed && scope == "user" { scope = "default"; target = "" } }
            .onChange(of: scores.canReadRank) { allowed in if !allowed { mode = "ledger" } }
    }
    private var queryForm: some View {
        VStack(alignment: .leading) {
            Picker(EduI18n.text("tool_scorePeriod"), selection: $period) {
                Text(EduI18n.text("tool_scorePeriod")).tag("")
                if let current = card.roundId, !scores.periods.contains(where: { $0.periodId == current }) { Text(EduI18n.text("tool_scorePeriodActive")).tag(current) }
                ForEach(scores.periods) { Text($0.ordinal + " · " + $0.startedAt).tag($0.periodId) }
            }
            Picker(EduI18n.text("tool_scoreLedger"), selection: $mode) {
                Text(EduI18n.text("tool_scoreLedger")).tag("ledger")
                if scores.canReadRank { Text(EduI18n.text("tool_scoreLeaderboard")).tag("leaderboard") }
            }
            if mode == "ledger" {
                Picker(EduI18n.text("tool_scoreTarget"), selection: $scope) {
                    Text(EduI18n.text(scores.canReadAll ? "tool_allScores" : "tool_myScore")).tag("default")
                    if scores.canReadAll { Text(EduI18n.text("tool_scoreUser")).tag("user") }
                    if !card.scoreGroups.isEmpty { Text(EduI18n.text("tool_scoreGroup")).tag("group") }
                }.onChange(of: scope) { _ in target = "" }
                if scope != "default" {
                    Picker(EduI18n.text("tool_scoreTarget"), selection: $target) {
                        Text(EduI18n.text(scope == "user" ? "tool_selectStudent" : "tool_selectGroup")).tag("")
                        if scope == "user" { ForEach(directory?.students ?? []) { Text($0.displayName).tag($0.userId) } }
                        else { ForEach(card.scoreGroups) { Text($0.name).tag($0.groupId) } }
                    }
                    if scope == "user", let directory {
                        Button(EduI18n.text("tool_refresh")) { controller.loadToolStudents() }
                        if let cursor = directory.nextCursor { Button(EduI18n.text("tool_moreStudents")) { controller.loadToolStudents(cursor: cursor) } }
                    }
                }
            } else {
                Picker(EduI18n.text("tool_scoreTarget"), selection: $rank) {
                    Text(EduI18n.text("tool_scoreUser")).tag("user"); Text(EduI18n.text("tool_scoreGroup")).tag("group")
                }
            }
            Button(EduI18n.text("tool_refresh")) {
                controller.loadToolScores(card, periodId: period, view: mode, kind: mode == "leaderboard" ? rank : scope == "default" ? nil : scope, id: mode == "leaderboard" || scope == "default" ? nil : target)
            }.disabled(!periodIds.contains(period) || (mode == "ledger" && scope != "default" && !targetIds.contains(target)))
        }
    }
}
@MainActor
private struct TeachingToolScorePagePanel: View {
    let card: TeachingToolCard; let scores: TeachingToolScores; let page: TeachingToolScorePage
    let directory: TeachingToolStudentDirectory?
    @ObservedObject var controller: ClassroomController
    private var periodLabel: String {
        if let period = scores.periods.first(where: { $0.periodId == page.periodId }) { return period.ordinal + " · " + period.startedAt }
        return EduI18n.text(page.periodId == card.roundId ? "tool_scorePeriodActive" : "tool_scorePeriod")
    }
    private var targetLabel: String {
        if let id = page.targetId {
            return page.targetKind == "user" ? directory?.students.first(where: { $0.userId == id })?.displayName ?? page.entries.first?.entry.displayName ?? EduI18n.text("tool_scoreTarget") : card.scoreGroups.first(where: { $0.groupId == id })?.name ?? page.entries.first?.entry.displayName ?? EduI18n.text("tool_scoreTarget")
        }
        return EduI18n.text(page.view == "leaderboard" ? page.targetKind == "user" ? "tool_scoreUser" : "tool_scoreGroup" : scores.canReadAll ? "tool_allScores" : "tool_myScore")
    }
    var body: some View {
        VStack(alignment: .leading) {
            Text(EduI18n.text(page.view == "ledger" ? "tool_scoreLedger" : "tool_scoreLeaderboard")).font(.headline)
            Text(periodLabel); Text(targetLabel)
            if let balance = page.balance { Text(EduI18n.text("tool_scoreBalance") + " " + balance) }
            ForEach(page.entries) { prepared in
                let entry = prepared.entry
                Text(entry.displayName + " · " + prepared.deltaText); Text(entry.reason)
                Text(EduI18n.text("tool_scoreBalanceAfter") + " " + entry.balanceAfter + " · " + entry.createdAt)
                if entry.origin == "automatic" || entry.origin == "reversal" { Text(EduI18n.text(entry.origin == "automatic" ? "tool_scoreAutomatic" : "tool_scoreReversal")) }
                if entry.reversed { Text(EduI18n.text("tool_scoreReversed")) }
                if card.canManageScores && prepared.canReverse {
                    TeachingToolScoreReversal(card: card, entryId: entry.id, controller: controller).id(card.revision + ":" + page.id + ":" + entry.id)
                }
            }
            ForEach(page.rows) { Text($0.rank + " · " + $0.displayName + " · " + $0.balance) }
            if let cursor = page.nextCursor {
                Button(EduI18n.text("tool_nextScorePage")) {
                    let query = page.query
                    controller.loadToolScores(card, periodId: query.periodId, view: query.view, kind: query.targetKind, id: query.targetId, cursor: cursor, limit: query.limit)
                }
            }
        }
    }
}
@MainActor
private struct TeachingToolScoreReversal: View {
    let card: TeachingToolCard; let entryId: String
    @ObservedObject var controller: ClassroomController
    @State private var reason = ""
    var body: some View {
        TextField(EduI18n.text("tool_reversalReason"), text: $reason).disabled(controller.toolMutationPending(card.sessionId))
        Button(EduI18n.text("tool_reverseScore")) { controller.reverseToolScore(card, entryId: entryId, reason: reason) }
            .disabled(controller.toolMutationPending(card.sessionId) || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}
