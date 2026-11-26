import SwiftUI

@MainActor
struct TeachingToolCreationForm: View {
    let availableKinds: [String]
    let scoreTargets: [TeachingToolRewardTarget]
    @ObservedObject var controller: ClassroomController
    let edit: TeachingToolEdit?
    let currentRevision: String?
    let onClose: (() -> Void)?
    @State private var editorGeneration = UUID()
    @State private var requestId: String?
    @State private var opened = false
    @State private var draft = TeachingToolDraft()
    init(availableKinds: [String], scoreTargets: [TeachingToolRewardTarget], controller: ClassroomController,
         edit: TeachingToolEdit? = nil, currentRevision: String? = nil, onClose: (() -> Void)? = nil) {
        self.availableKinds = availableKinds; self.scoreTargets = scoreTargets; self.controller = controller
        self.edit = edit; self.currentRevision = currentRevision; self.onClose = onClose
        _opened = State(initialValue: edit != nil); _draft = State(initialValue: edit?.draft ?? TeachingToolDraft())
    }
    private var operation: TeachingToolOperation? { controller.toolsView?.operations.first { $0.requestId == requestId } }
    private var waiting: Bool { requestId != nil && (operation == nil || operation?.blocksWrites == true) }
    private func close() { editorGeneration = UUID(); requestId = nil; if let onClose { onClose() } else { opened = false } }
    private var stale: Bool { edit != nil && edit?.revision != currentRevision }
    private var supported: [String] { availableKinds.filter { ["random_picker", "countdown", "stopwatch", "quiz", "poll", "buzzer", "random_props", "status_card", "word_cloud", "groups", "scores"].contains($0) } }
    var body: some View {
        if !supported.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Button(EduI18n.text(opened ? "tool_back" : "tool_create")) { if opened { close() } else { opened = true } }
                if opened { fields.disabled(waiting) }
            }.onAppear { if !supported.contains(draft.kind), let first = supported.first { draft.kind = first; if edit == nil { draft.scope = first == "groups" ? "all_students" : "present_students" } } }
            .onChange(of: operation?.status) { status in if requestId != nil && status == "succeeded" { close() } }
            .onChange(of: ObjectIdentifier(controller)) { _ in close(); draft = TeachingToolDraft() }
            .onDisappear { editorGeneration = UUID(); requestId = nil }
        }
    }
    private var fields: some View {
        VStack(alignment: .leading, spacing: 6) {
            if edit == nil { Picker(EduI18n.text("tool_kind"), selection: $draft.kind) {
                ForEach(supported, id: \.self) { Text(EduI18n.text("tool_kind_" + $0)).tag($0) }
            }.onChange(of: draft.kind) { _ in draft.scope = draft.kind == "groups" ? "all_students" : "present_students" } }
            field("title", $draft.title)
            if ["countdown", "poll", "buzzer", "word_cloud"].contains(draft.kind) || (draft.kind == "status_card" && draft.timed) { field("seconds", $draft.seconds) }
            if draft.kind == "countdown" { Toggle(EduI18n.text("tool_sound"), isOn: $draft.sound) }
            if ["random_picker", "buzzer"].contains(draft.kind) { field("count", $draft.count) }
            if draft.kind == "random_picker" {
                Toggle(EduI18n.text("tool_noRepeat"), isOn: $draft.noRepeat)
                Picker(EduI18n.text("tool_display"), selection: $draft.display) {
                    ForEach(["cards", "wheel", "list"], id: \.self) { Text(EduI18n.text("tool_display_" + $0)).tag($0) }
                }
                field("excludedIds", $draft.excludeIds)
            }
            if ["random_picker", "quiz", "poll", "buzzer", "word_cloud", "groups"].contains(draft.kind) {
                Picker(EduI18n.text("tool_scope"), selection: $draft.scope) {
                    if draft.kind == "groups" { Text(EduI18n.text("tool_scope_all_students")).tag("all_students") }
                    else { Text(EduI18n.text("tool_scope_present_students")).tag("present_students") }
                    if draft.kind == "random_picker" { Text(EduI18n.text("tool_scope_on_stage_students")).tag("on_stage_students") }
                    Text(EduI18n.text("tool_scope_selected_students")).tag("selected_students")
                }
                if draft.scope == "selected_students" { field("selectedIds", $draft.userIds) }
            }
            if ["quiz", "poll", "word_cloud"].contains(draft.kind) { Toggle(EduI18n.text("tool_allowChanges"), isOn: $draft.allowChanges) }
            if ["quiz", "buzzer"].contains(draft.kind) { rewardFields }
            additionalFields
            if draft.kind == "poll" { pollFields }
            if draft.kind == "quiz" { quizFields }
            if stale { Text(EduI18n.text("tool_draftChanged")) }
            Button(EduI18n.text("tool_createDraft")) {
                guard !waiting && !stale else { return }
                editorGeneration = UUID()
                let editor = editorGeneration
                let rejected: () -> Void = { if editorGeneration == editor { requestId = nil } }
                let preparedId: String
                if let edit { preparedId = controller.updateTool(edit, draft: draft, trueLabel: EduI18n.text("tool_true"), falseLabel: EduI18n.text("tool_false"), onRejected: rejected) }
                else { preparedId = controller.createTool(draft, trueLabel: EduI18n.text("tool_true"), falseLabel: EduI18n.text("tool_false"), onRejected: rejected) }
                requestId = preparedId
            }.disabled(stale)
        }
    }
    private var additionalFields: some View {
        VStack(alignment: .leading) {
            if draft.kind == "random_props" {
                choice("prop", $draft.propMode, ["dice", "coin", "wheel"], "prop")
                if draft.propMode == "dice" { field("diceCount", $draft.diceCount) }
                if draft.propMode == "wheel" {
                    Text(EduI18n.text("tool_wheelItems")); TextEditor(text: $draft.wheel).frame(minHeight: 80)
                    Toggle(EduI18n.text("tool_noRepeat"), isOn: $draft.noRepeat)
                }
            }
            if draft.kind == "status_card" {
                choice("color", $draft.color, ["red", "yellow", "green"], "color")
                choice("workMode", $draft.workMode, ["quiet", "collaborate", "speak"], "work")
                Toggle(EduI18n.text("tool_timed"), isOn: $draft.timed)
            }
            if draft.kind == "word_cloud" {
                field("prompt", $draft.prompt); field("maxWords", $draft.maxWords)
                Toggle(EduI18n.text("tool_mergeLatinCase"), isOn: $draft.mergeLatinCase)
                Toggle(EduI18n.text("tool_showLiveResults"), isOn: $draft.showLiveResults)
            }
            if draft.kind == "groups" {
                Picker(EduI18n.text("tool_allocationMode"), selection: $draft.allocationMode) {
                    Text(EduI18n.text("tool_groupCount")).tag("group_count"); Text(EduI18n.text("tool_groupSize")).tag("group_size")
                }
                field(draft.allocationMode == "group_count" ? "groupCount" : "groupSize", $draft.allocationValue); field("excludedIds", $draft.excludeIds)
            }
            if draft.kind == "scores" {
                Toggle(EduI18n.text("tool_showLeaderboard"), isOn: $draft.showLeaderboard)
                choice("scoreVisual", $draft.scoreVisual, ["stars", "trophies"], "visual")
            }
        }
    }
    private func choice(_ key: String, _ value: Binding<String>, _ values: [String], _ prefix: String) -> some View {
        Picker(EduI18n.text("tool_" + key), selection: value) { ForEach(values, id: \.self) { Text(EduI18n.text("tool_" + prefix + "_" + $0)).tag($0) } }
    }
    private var rewardFields: some View {
        VStack(alignment: .leading) {
            Picker(EduI18n.text("tool_rewardScoreTool"), selection: $draft.rewardScoreSessionId) {
                Text(EduI18n.text("tool_noAutomaticReward")).tag(String?.none)
                if let existing = draft.rewardScoreSessionId, !scoreTargets.contains(where: { $0.id == existing }) { Text(existing).tag(Optional(existing)) }
                ForEach(scoreTargets) { Text($0.title).tag(Optional($0.id)) }
            }.onChange(of: draft.rewardScoreSessionId) { if $0 == nil { draft.rewardPoints = "0" } }
            if draft.kind == "buzzer" && draft.rewardScoreSessionId != nil { field("rewardPoints", $draft.rewardPoints) }
        }
    }
    private var pollFields: some View {
        VStack(alignment: .leading) {
            field("question", $draft.prompt)
            Text(EduI18n.text("tool_options"))
            TextEditor(text: $draft.options).frame(minHeight: 80)
            field("minChoices", $draft.minChoices)
            field("maxChoices", $draft.maxChoices)
            Toggle(EduI18n.text("tool_anonymous"), isOn: $draft.anonymous)
            Toggle(EduI18n.text("tool_showLiveResults"), isOn: $draft.showLiveResults)
        }
    }
    private var quizFields: some View {
        VStack(alignment: .leading) {
            ForEach($draft.questions) { $question in
                TeachingQuestionDraftForm(question: $question)
                if draft.questions.count > 1 {
                    Button(EduI18n.text("tool_removeQuestion")) { draft.questions.removeAll { $0.id == question.id } }
                }
            }
            Button(EduI18n.text("tool_addQuestion")) { draft.questions.append(TeachingQuestionDraft()) }
                .disabled(draft.questions.count >= TeachingToolAuthoringNumbers.questionCount.max)
        }
    }
    private func field(_ key: String, _ value: Binding<String>) -> some View {
        TextField(EduI18n.text("tool_" + key), text: value)
    }
}
@MainActor
private struct TeachingQuestionDraftForm: View {
    @Binding var question: TeachingQuestionDraft
    var body: some View {
        VStack(alignment: .leading) {
            Picker(EduI18n.text("tool_questionType"), selection: $question.kind) {
                ForEach(["single", "multiple", "true_false", "fill", "short"], id: \.self) { Text(EduI18n.text("tool_question_" + $0)).tag($0) }
            }.onChange(of: question.kind) { kind in question.optionIds = []; question.correct = kind == "true_false" ? "true" : "1" }
            TextField(EduI18n.text("tool_question"), text: $question.stem)
            if ["single", "multiple"].contains(question.kind) {
                Text(EduI18n.text("tool_options"))
                TextEditor(text: $question.options).frame(minHeight: 80)
                TextField(EduI18n.text("tool_correctOptions"), text: $question.correct)
            }
            if question.kind == "true_false" {
                Picker(EduI18n.text("tool_correct"), selection: $question.correct) {
                    Text(EduI18n.text("tool_true")).tag("true")
                    Text(EduI18n.text("tool_false")).tag("false")
                }
            }
            if question.kind == "fill" {
                Text(EduI18n.text("tool_acceptedAnswers"))
                TextEditor(text: $question.accepted).frame(minHeight: 80)
                Toggle(EduI18n.text("tool_caseSensitive"), isOn: $question.caseSensitive)
                Toggle(EduI18n.text("tool_trimWhitespace"), isOn: $question.trimWhitespace)
            }
            TextField(EduI18n.text("tool_points"), text: $question.points)
            TextField(EduI18n.text("tool_seconds"), text: $question.seconds)
            TextField(EduI18n.text("tool_explanation"), text: $question.explanation)
        }.padding(.vertical, 8)
    }
}
