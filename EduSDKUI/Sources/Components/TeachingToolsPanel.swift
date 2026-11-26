import SwiftUI
import EduSDK

@MainActor
private struct TeachingToolSessionPanel: View {
    @ObservedObject var controller: ClassroomController
    let kind: String
    var portrait: Bool = false
    var onNotice: (String) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading) {
            Button(EduI18n.text("tool_refresh")) { controller.loadTools() }
            Button(EduI18n.text("tool_history")) { controller.loadToolHistory() }
            if let frame = controller.toolsView {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(frame.operations) { operation in
                            VStack(alignment: .leading) {
                                Text(EduI18n.text("tool_operation_" + operation.operation) + " · " + EduI18n.text("tool_operation_" + operation.status))
                                if let error = operation.error { Text(error.message) }
                                if operation.canResolve { Button(EduI18n.text("tool_operation_resolve")) { controller.resolveTool(operation.requestId) } }
                                if operation.canRetry { Button(EduI18n.text("tool_operation_retry")) { controller.retryTool(operation.requestId) } }
                            }
                        }
                        if frame.canCreate { TeachingToolCreationForm(availableKinds: [kind], scoreTargets: frame.scoreTargets, controller: controller) }
                        if frame.cards.isEmpty { Text(EduI18n.text("tool_empty")) }
                        if let history = frame.history {
                            Text(EduI18n.text("tool_history")).font(.headline)
                            ForEach(history.items, id: \.item.sessionId) { entry in
                                VStack(alignment: .leading) {
                                    Text(entry.item.title)
                                    Text(EduI18n.text("tool_kind_" + entry.item.kind))
                                    Text(entry.item.lastUsedAt)
                                    Button(EduI18n.text("tool_results")) { controller.loadToolHistoryDetail(sessionId: entry.item.sessionId, revision: entry.item.lastUsedRevision) }
                                    Button(EduI18n.text("tool_historyVersions")) { controller.loadToolHistoryVersions(sessionId: entry.item.sessionId) }
                                    TeachingToolHistoryVersionsPanel(pages: frame.historyVersions.filter { $0.sessionId == entry.item.sessionId }, controller: controller)
                                }
                            }
                            if let cursor = history.nextCursor { Button(EduI18n.text("tool_nextHistoryPage")) { controller.loadToolHistory(cursor: cursor) } }
                        }
                        ForEach(frame.historyDetails) { detail in TeachingToolCardPanel(card: detail.card, controller: controller, recordedAt: detail.recordedAt) }
                        ForEach(frame.cards.filter { $0.kind == kind }) { card in TeachingToolCardPanel(card: card, controller: controller) }
                        if let cursor = frame.nextCursor {
                            Button(EduI18n.text("tool_loadMore")) { controller.loadTools(cursor: cursor) }
                        }
                    }.padding(12)
                }
            } else { Text(EduI18n.text("tool_loading")) }
        }.onAppear { controller.loadTools() }
    }
}
@MainActor
private struct TeachingToolCardPanel: View {
    let card: TeachingToolCard
    @ObservedObject var controller: ClassroomController
    var recordedAt: String? = nil
    @State private var parameter = ""
    @State private var wantsEdit = false
    @State private var editing: TeachingToolEdit?
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title).font(.headline)
            if let recordedAt { Text(recordedAt) }
            Text(EduI18n.text("tool_status_" + card.status))
            if let clock = card.clock { Text(clock).font(.title).monospacedDigit() }
            if card.awaiting { Text(EduI18n.text("tool_awaiting")) }
            if let random = card.random { TeachingToolRandomResult(frame: random) }
            ForEach(Array(card.laps.enumerated()), id: \.offset) { index, lap in Text("\(index + 1) · \(lap.0) · \(lap.1)") }
            if card.controls.contains("adjust") || card.controls.contains("lap") {
                TextField(EduI18n.text(card.controls.contains("lap") ? "tool_lapLabel" : "tool_adjustSeconds"), text: $parameter).disabled(controller.toolMutationPending(card.sessionId))
            }
            ForEach(card.controls, id: \.self) { action in
                Button(EduI18n.text("tool_action_" + action)) { controller.controlTool(card, action: action, parameter: parameter) }.disabled(controller.toolMutationPending(card.sessionId))
            }
            if card.canEditDraft {
                if let editing {
                    TeachingToolCreationForm(availableKinds: [card.kind], scoreTargets: controller.toolsView?.scoreTargets ?? [], controller: controller,
                        edit: editing, currentRevision: card.revision, onClose: { self.editing = nil; wantsEdit = false })
                } else {
                    Button(EduI18n.text(wantsEdit ? "tool_refresh" : "tool_editDraft")) {
                        wantsEdit = true
                        if card.edit?.revision == card.revision { editing = card.edit }
                        controller.loadToolDefinition(card)
                    }
                    if wantsEdit {
                        Text(EduI18n.text("tool_loading"))
                        Button(EduI18n.text("tool_back")) { wantsEdit = false }
                    }
                }
            }
            if card.kind == "groups" { TeachingToolGroupsPanel(card: card, controller: controller) }
            if card.statusColor != nil { TeachingToolStatusCard(card: card) }
            if let scores = card.scores { TeachingToolScoresPanel(card: card, scores: scores, controller: controller) }
            if card.canManageScores {
                TeachingToolAwardPanel(card: card, directory: controller.toolsView?.studentDirectory, controller: controller)
                    .id(card.sessionId + ":" + card.revision + ":" + (card.roundId ?? ""))
            }
            if card.canExport { TeachingToolExportsPanel(card:card,controller:controller) }
            if card.canReadResults { Button(EduI18n.text("tool_results")) { controller.loadToolResults(card) } }
            if let result = card.roundResults { TeachingToolResultsPanel(card: card, result: result, controller: controller) }
            if card.canReadOwn { Button(EduI18n.text("tool_myReceipt")) { controller.loadToolOwn(card) } }
            if recordedAt != nil {
                if let prompt = card.input?.prompt { Text(prompt) }; if let answer = card.ownAnswerText { Text(answer) }
                if let score = card.ownScore { Text(EduI18n.text("tool_points") + " \(score)") }; if let feedback = card.ownFeedback { Text(feedback) }
            }
            if recordedAt == nil, let input = card.input {
                TeachingToolAnswerPanel(card: card, input: input, controller: controller)
                    .id((card.roundId ?? card.sessionId) + ":" + (card.ownRevision ?? "none"))
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08)).cornerRadius(10)
            .onChange(of: card.edit?.revision) { _ in
                if wantsEdit && editing == nil && card.edit?.revision == card.revision { editing = card.edit }
            }
            .onChange(of: card.canEditDraft) { allowed in if !allowed { wantsEdit = false; editing = nil } }
    }
}
@MainActor
private struct TeachingToolAnswerPanel: View {
    let card: TeachingToolCard
    let input: TeachingToolInput
    @ObservedObject var controller: ClassroomController
    @State private var selection: [String]
    @State private var text: String
    init(card: TeachingToolCard, input: TeachingToolInput, controller: ClassroomController) {
        self.card = card; self.input = input; self.controller = controller
        _selection = State(initialValue: card.initialSelection); _text = State(initialValue: card.initialText)
    }
    var body: some View {
        VStack(alignment: .leading) {
            if input.type != "buzz" { Text(input.prompt) }
            ForEach(input.options ?? []) { option in
                Button {
                    if input.type == "single_choice" { selection = [option.id] }
                    else if selection.contains(option.id) { selection.removeAll { $0 == option.id } }
                    else { selection.append(option.id) }
                } label: { Label(option.label, systemImage: selection.contains(option.id) ? "checkmark.circle.fill" : "circle") }
                    .disabled(!card.canSubmit || controller.toolMutationPending(card.sessionId))
            }
            if input.type == "text" || input.type == "words" { TextEditor(text: $text).frame(minHeight: 64).disabled(!card.canSubmit || controller.toolMutationPending(card.sessionId)) }
            if card.canSubmit {
                Button(EduI18n.text(input.type == "buzz" ? "tool_buzz" : card.ownRevision == nil ? "tool_submit" : "tool_replaceAnswer")) {
                    controller.submitTool(card, selection: selection, text: text)
                }.disabled(controller.toolMutationPending(card.sessionId))
            }
            if card.ownRevision != nil { Text(EduI18n.text("tool_received")) }
        }
    }
}

@MainActor
private struct TeachingToolResultsPanel: View {
    let card: TeachingToolCard
    let result: TeachingToolResults
    @ObservedObject var controller: ClassroomController
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = result.quizSummary {
                Text(EduI18n.text("tool_quizSummary"))
                Text(EduI18n.text("tool_quizProgress") + " \(summary.startedQuestionCount) / \(summary.questionCount)")
                Text(EduI18n.text("tool_responseRate") + (summary.eligibleAnswerCount == 0 ? " — · " : " \(summary.submittedAnswerCount) / \(summary.eligibleAnswerCount) · ") + EduI18n.text("tool_correctRate") + (summary.gradedAnswerCount == 0 ? " —" : " \(summary.correctAnswerCount) / \(summary.gradedAnswerCount)"))
                Text(EduI18n.text("tool_unanswered") + " \(summary.unansweredAnswerCount) · " + EduI18n.text("tool_pending") + " \(summary.pendingAnswerCount)")
                ForEach(summary.members) { member in
                    Text(member.displayName + " · " + EduI18n.text("tool_received") + " \(member.submittedCount) / \(member.eligibleQuestionCount)")
                    Text(EduI18n.text("tool_earnedPoints") + " \(member.earnedPoints) / \(member.maxPoints) · " + EduI18n.text("tool_pending") + " \(member.pendingCount)")
                    if let finalScore = member.finalScore { Text(EduI18n.text("tool_finalScore") + " \(finalScore) / \(member.maxPoints)") }
                }
                if let cursor = summary.nextCursor { Button(EduI18n.text("tool_quizMembersMore")) {controller.loadToolResults(card,cursor:cursor)} }
            }
            Text(EduI18n.text("tool_received") + " \(result.submitted) / \(result.eligible) · " + EduI18n.text("tool_unanswered") + " \(result.unanswered)")
            if let correct = result.correct { Text(EduI18n.text("tool_correct") + " \(correct)") }
            if let pending = result.pending { Text(EduI18n.text("tool_pending") + " \(pending)") }
            ForEach(Array(result.optionCounts.enumerated()), id: \.offset) { _, row in Text("\(row.0) · \(row.1)") }
            if card.kind == "poll" { Text(EduI18n.text("tool_denominator") + " \(result.denominator)") }
            ForEach(Array(result.winners.enumerated()), id: \.offset) { _, row in Text("\(row.1) · \(row.0)") }
            ForEach(result.words) { word in
                Text("\(word.word) · \(word.count)")
                if card.canManageTerms { Button(EduI18n.text("tool_hideWord")) { controller.controlTool(card, action: "hide_term", parameter: word.key) }.disabled(controller.toolMutationPending(card.sessionId)) }
            }
            if card.canManageTerms { ForEach(result.hiddenWords) { word in
                Text("\(word.word) · \(word.count)")
                Button(EduI18n.text("tool_restoreWord")) { controller.controlTool(card, action: "restore_term", parameter: word.key) }.disabled(controller.toolMutationPending(card.sessionId))
            } }
            if let answer = result.answerText { Text(EduI18n.text("tool_correctAnswer") + ": " + answer) }
            if let explanation = result.explanation { Text(explanation) }
            ForEach(result.submissions) { submission in
                VStack(alignment: .leading) {
                    Text(submission.userId)
                    if let answer = submission.answerText { Text(answer) }
                    if let score = submission.score { Text(EduI18n.text("tool_points") + " \(score)") }
                    if card.canReview {
                        TeachingToolReviewForm(card: card, submission: submission, controller: controller)
                            .id((card.roundId ?? "") + ":" + submission.userId + ":" + submission.revision)
                    }
                }
            }
            if let cursor = result.nextCursor { Button(EduI18n.text("tool_nextPage")) { controller.loadToolResults(card, cursor: cursor) } }
        }
    }
}
@MainActor
private struct TeachingToolReviewForm: View {
    let card: TeachingToolCard
    let submission: TeachingToolSubmission
    @ObservedObject var controller: ClassroomController
    @State private var score: String
    @State private var feedback: String
    init(card: TeachingToolCard, submission: TeachingToolSubmission, controller: ClassroomController) {
        self.card = card; self.submission = submission; self.controller = controller
        _score = State(initialValue: submission.score.map(String.init) ?? "")
        _feedback = State(initialValue: submission.feedback ?? "")
    }
    var body: some View {
        VStack(alignment: .leading) {
            TextField(EduI18n.text("tool_points"), text: $score)
            TextField(EduI18n.text("tool_feedback"), text: $feedback)
            Button(EduI18n.text("tool_review")) { controller.reviewTool(card, submission: submission, score: score, feedback: feedback) }
        }.disabled(controller.toolMutationPending(card.sessionId))
    }
}

@MainActor
private struct TeachingToolAwardPanel: View {
    let card: TeachingToolCard
    let directory: TeachingToolStudentDirectory?
    @ObservedObject var controller: ClassroomController
    @State private var kind = "user"
    @State private var target = ""
    @State private var delta = "1"
    @State private var reason = ""
    private var candidates: [String] { kind == "user" ? directory?.students.map(\.userId) ?? [] : card.scoreGroups.map(\.groupId) }
    var body: some View {
        VStack(alignment: .leading) {
            Text(EduI18n.text("tool_awardScore"))
            Picker(EduI18n.text("tool_scoreTarget"), selection: $kind) {
                Text(EduI18n.text("tool_scoreUser")).tag("user")
                Text(EduI18n.text("tool_scoreGroup")).tag("group")
            }.onChange(of: kind) { _ in target = "" }
            Picker(EduI18n.text(kind == "user" ? "tool_scoreStudent" : "tool_targetGroup"), selection: $target) {
                Text(EduI18n.text(kind == "user" ? "tool_selectStudent" : "tool_selectGroup")).tag("")
                if kind == "user" { ForEach(directory?.students ?? []) { Text($0.displayName).tag($0.userId) } }
                else { ForEach(card.scoreGroups) { Text($0.name).tag($0.groupId) } }
            }
            if kind == "user", let directory {
                Button(EduI18n.text("tool_refresh")) { controller.loadToolStudents() }
                if let cursor = directory.nextCursor { Button(EduI18n.text("tool_moreStudents")) { controller.loadToolStudents(cursor: cursor) } }
            }
            TextField(EduI18n.text("tool_scoreDelta"), text: $delta)
            TextField(EduI18n.text("tool_scoreReason"), text: $reason)
            Button(EduI18n.text("tool_awardScore")) { controller.awardToolScore(card, kind: kind, id: target, delta: delta, reason: reason) }
                .disabled(!candidates.contains(target) || reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }.disabled(controller.toolMutationPending(card.sessionId)).onChange(of: candidates) { ids in if !ids.contains(target) { target = "" } }
    }
}

@MainActor
private struct TeachingToolHistoryVersionsPanel: View {
    let pages: [TeachingToolHistoryVersions]
    @ObservedObject var controller: ClassroomController
    var body: some View {
        ForEach(pages) { page in
            VStack(alignment: .leading) {
                ForEach(page.items) { version in
                    VStack(alignment: .leading) {
                        Text(version.title)
                        Text(EduI18n.text("tool_status_" + version.status) + " · " + EduI18n.text("tool_revision") + " " + version.revision)
                        Text(version.recordedAt)
                        Button(EduI18n.text("tool_results")) { controller.loadToolHistoryDetail(sessionId: page.sessionId, revision: version.revision) }
                    }
                }
                if let cursor = page.nextCursor { Button(EduI18n.text("tool_nextHistoryPage")) { controller.loadToolHistoryVersions(sessionId: page.sessionId, cursor: cursor) } }
            }
        }
    }
}

@MainActor
struct TeachingToolsPanel: View {
    @ObservedObject var controller: ClassroomController
    var portrait: Bool = false
    var onNotice: (String) -> Void = { _ in }
    @State private var selected: ClassroomToolCatalogItem?
    var body: some View {
        ToolCatalogGrid(catalog: controller.snapshot.classroomView.toolCatalog) { selected = $0 }
            .overlay {
                if let tool = selected {
                    PopupShell(visible: true, onDismiss: { selected = nil }, alignBottom: portrait) {
                        VStack(spacing: 0) {
                            HStack { Text(EduI18n.text(tool.titleKey)).font(.headline); Spacer(); Button { selected = nil } label: { EduIcon("close") }.frame(width: MobileClassroomTokens.touch, height: MobileClassroomTokens.touch).accessibilityLabel(EduI18n.text("close")) }.padding(.horizontal, MobileClassroomTokens.inset)
                            TeachingToolSessionPanel(controller: controller, kind: tool.kind).frame(maxHeight: MobileClassroomTokens.toolDialogMaxHeight)
                        }.background(EduColors.surfaceLowest).clipShape(RoundedRectangle(cornerRadius: MobileClassroomTokens.cardRadius))
                    }
                }
            }
    }
}
