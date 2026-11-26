import Foundation

@propertyWrapper
struct RequiredToolNullable<Value: Decodable>: Decodable {
    var wrappedValue: Value?
    init(wrappedValue: Value?) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws { wrappedValue = try decoder.singleValueContainer().decode(Value?.self) }
}
struct TeachingToolRandom: Decodable {
    struct Row: Decodable, Identifiable { let id: String; let label: String; @RequiredToolNullable var labelKey: String?; @RequiredToolNullable var glyph: String? }
    struct Slice: Decodable { @RequiredToolNullable var id: String?; @RequiredToolNullable var label: String?; let weight: Int; let colorIndex: Int; let points: [[Double]] }
    let mode: String; let roundId: String; let rows: [Row]; let slices: [Slice]; let rotationDegrees: Double; let poolWeight: Int
}
struct TeachingToolGroup: Decodable, Identifiable {
    struct Member: Decodable, Identifiable { var id: String { userId }; let userId: String; let displayName: String }
    var id: String { groupId }; let groupId: String; let name: String
    @RequiredToolNullable var leaderId: String?
    let members: [Member]
}
struct TeachingToolOption: Decodable, Identifiable { let id: String; let label: String }
struct TeachingToolInput: Decodable { let type: String; let prompt: String; let options: [TeachingToolOption]? }
struct TeachingToolAnswer: Decodable { let kind: String; let optionIds: [String]?; let text: String?; let words: [String]?; let acceptedAnswers: [String]? }
private struct ToolReceipt: Decodable { struct Submission: Decodable { let revision: String; let answer: TeachingToolAnswer; @RequiredToolNullable var score: Int?; @RequiredToolNullable var feedback: String? }; let submission: Submission }
struct TeachingToolScoreGroup: Decodable, Identifiable { var id: String { groupId }; let groupId: String; let name: String }
struct TeachingToolStudentDirectory: Decodable { struct Student: Decodable, Identifiable { var id: String { userId }; let userId: String; let displayName: String }; let loaded: Bool; let nextCursor: String?; let students: [Student]
    private enum CodingKeys: String, CodingKey { case loaded, nextCursor, students }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        loaded = try c.decode(Bool.self, forKey: .loaded); nextCursor = try c.decode(String?.self, forKey: .nextCursor)
        students = try c.decode([Student].self, forKey: .students)
    }
}
private struct CoreToolUI: Decodable {
    let canExport: Bool
    let canManageGroups: Bool; let canReadDefinition: Bool
    @RequiredToolNullable var ownGroupId: String?
    let canReadScorePeriods: Bool; let canReadScoreLedger: Bool; let canReadScoreRank: Bool; let canReadAllScores: Bool; let scoreReversibleEntryIds: [String]
    let scoreGroups: [TeachingToolScoreGroup]
    let controls: [String]; let input: TeachingToolInput?; let ownReceipt: ToolReceipt?
    let canReadOwn: Bool; let canRequestSubmit: Bool; let canReadResults: Bool; let canReviewCurrentRound: Bool; let canManageScores: Bool; let canManageTerms: Bool; let canEditDraft: Bool
}
private struct CoreToolClock: Decodable { let elapsedMs: UInt64; let remainingMs: UInt64?; let awaitingServerCompletion: Bool }
private struct CoreToolSession: Decodable {
    struct Config: Decodable { let kind: String; let title: String; let color: String?; let workMode: String? }
    struct Round: Decodable { let roundId: String; let result: Result? }
    struct Result: Decodable {
        struct Selected: Decodable { let displayName: String }
        let groups: [TeachingToolGroup]?
        let kind: String; let selected: [Selected]?; let mode: String?; let values: [Int]?; let value: String?; let label: String?
    }
    struct Lap: Decodable { let label: String; let elapsedMs: UInt64 }
    let sessionId: String; let revision: String; let status: String; let config: Config
    let participation: Round?; let round: Round?; let laps: [Lap]
}
private struct CoreToolSubmission: Decodable {
    let submissionId: String; let userId: String; let revision: String; let answer: TeachingToolAnswer; let score: Int?; let feedback: String?
}
struct TeachingToolQuizMember: Decodable, Identifiable {
    var id: String { userId }
    let userId: String; let displayName: String; let eligibleQuestionCount: Int; let submittedCount: Int
    let pendingCount: Int; let earnedPoints: Int; let maxPoints: Int
    @RequiredToolNullable var finalScore: Int?
}
struct TeachingToolQuizSummary: Decodable {
    let questionCount: Int; let startedQuestionCount: Int; let submittedAnswerCount: Int; let eligibleAnswerCount: Int
    let correctAnswerCount: Int; let gradedAnswerCount: Int; let unansweredAnswerCount: Int; let pendingAnswerCount: Int
    let members: [TeachingToolQuizMember]
    @RequiredToolNullable var nextCursor: String?
}
private struct CoreToolResults: Decodable {
    @RequiredToolNullable var quizSummary: TeachingToolQuizSummary?
    struct Count: Decodable { let optionId: String; let count: Int }
    struct Winner: Decodable { let userId: String; let displayName: String; let ordinal: Int }
    struct Word: Decodable { let key: String; let word: String; let count: Int }
    let sessionId: String; let roundId: String; let submittedCount: Int; let eligibleCount: Int; let unansweredCount: Int
    let correctCount: Int?; let pendingCount: Int?; let denominator: Int; let anonymous: Bool
    let optionCounts: [Count]; let winners: [Winner]; let words: [Word]; let hiddenWords: [Word]; let submissions: [CoreToolSubmission]
    let answerKey: TeachingToolAnswer?; let explanation: String?; let nextCursor: String?
}
private enum CoreToolPrivateView: Decodable {
    case results(CoreToolResults), definition(TeachingToolEdit), scores(CoreToolScorePage, TeachingToolScoreQuery), scorePeriods(TeachingToolScorePeriods), unused
    private enum CodingKeys: String, CodingKey { case type, data }
    private enum DefinitionKeys: String, CodingKey { case sessionId, revision, config }
    private enum ConfigKeys: String, CodingKey { case kind }
    private struct ScoresData: Decodable { let query: TeachingToolScoreQuery; let response: CoreToolScorePage }
    private struct PeriodsData: Decodable { let response: TeachingToolScorePeriods }
    private struct ResultsData: Decodable { let response: CoreToolResults }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "results": self = .results(try container.decode(ResultsData.self, forKey: .data).response)
        case "definition":
            let data = try container.nestedContainer(keyedBy: DefinitionKeys.self, forKey: .data)
            let config = try data.nestedContainer(keyedBy: ConfigKeys.self, forKey: .config)
            switch try config.decode(String.self, forKey: .kind) {
            case "random_picker", "countdown", "stopwatch", "quiz", "poll", "buzzer", "random_props", "status_card", "word_cloud", "groups", "scores":
                self = .definition(TeachingToolEdit(sessionId: try data.decode(String.self, forKey: .sessionId), revision: try data.decode(String.self, forKey: .revision), draft: try data.decode(TeachingToolDraft.self, forKey: .config)))
            default: throw invalidView("Unknown definition kind")
            }
        case "scores":
            let data = try container.decode(ScoresData.self, forKey: .data); self = .scores(data.response, data.query)
        case "score_periods": self = .scorePeriods(try container.decode(PeriodsData.self, forKey: .data).response)
        case "own", "reviewed": self = .unused
        default: throw invalidView("Unknown private view")
        }
    }
}
struct TeachingToolHistory: Decodable {
    struct Item: Decodable { let sessionId: String; let kind: String; let title: String; let revision: String; let lastUsedRevision: String; let lastUsedAt: String }
    struct Entry: Decodable { let item: Item }
    let items: [Entry]; let nextCursor: String?
}
struct TeachingToolSubmission: Identifiable {
    let id: String; let userId: String; let revision: String; let answerText: String?; let score: Int?; let feedback: String?
}
struct TeachingToolWord: Identifiable { var id: String { key }; let key: String; let word: String; let count: Int }
struct TeachingToolResults {
    let quizSummary: TeachingToolQuizSummary?
    let submitted: Int; let eligible: Int; let unanswered: Int; let correct: Int?; let pending: Int?; let denominator: Int
    let optionCounts: [(String, Int)]; let winners: [(String, Int)]; let words: [TeachingToolWord]; let hiddenWords: [TeachingToolWord]
    let submissions: [TeachingToolSubmission]; let answerText: String?; let explanation: String?; let nextCursor: String?; let anonymous: Bool
}
struct TeachingToolOperation: Decodable, Identifiable {
    struct Failure: Decodable { let code: String; let message: String }
    var id: String { requestId }
    let requestId: String; let operation: String; let status: String; let attempts: Int; let canRetry: Bool; let canResolve: Bool; let blocksWrites: Bool
    @RequiredToolNullable var sessionId: String?
    @RequiredToolNullable var error: Failure?
}
private struct CoreToolsView: Decodable {
    let exports: [TeachingToolExport]
    let operations: [TeachingToolOperation]
    struct Entry: Decodable { let session: CoreToolSession; let ui: CoreToolUI; let clock: CoreToolClock?; @RequiredToolNullable var random: TeachingToolRandom? }
    struct HistoryEntry: Decodable { let recordedAt: String; let session: CoreToolSession; let ui: CoreToolUI; let clock: CoreToolClock?; @RequiredToolNullable var random: TeachingToolRandom? }
    let historyVersions: [TeachingToolHistoryVersions]
    let historyDetails: [HistoryEntry]
    let canCreate: Bool; let nextCursor: String?; let availableKinds: [String]; let sessions: [Entry]; let privateViews: [CoreToolPrivateView]; let history: TeachingToolHistory?
    let studentDirectory: TeachingToolStudentDirectory?
    let scoreTargets: [TeachingToolRewardTarget]
    private enum CodingKeys: String, CodingKey { case exports, historyVersions, historyDetails, operations, canCreate, nextCursor, availableKinds, sessions, privateViews, history, studentDirectory, scoreTargets }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scoreTargets = try c.decode([TeachingToolRewardTarget].self, forKey: .scoreTargets)
        exports = try c.decode([TeachingToolExport].self, forKey: .exports)
        historyVersions = try c.decode([TeachingToolHistoryVersions].self, forKey: .historyVersions)
        historyDetails = try c.decode([HistoryEntry].self, forKey: .historyDetails)
        operations = try c.decode([TeachingToolOperation].self, forKey: .operations)
        canCreate = try c.decode(Bool.self, forKey: .canCreate); nextCursor = try c.decode(String?.self, forKey: .nextCursor)
        availableKinds = try c.decode([String].self, forKey: .availableKinds); sessions = try c.decode([Entry].self, forKey: .sessions)
        privateViews = try c.decode([CoreToolPrivateView].self, forKey: .privateViews); history = try c.decode(TeachingToolHistory?.self, forKey: .history)
        studentDirectory = try c.decode(TeachingToolStudentDirectory?.self, forKey: .studentDirectory)
    }
}
struct TeachingToolEdit { let sessionId: String; let revision: String; let draft: TeachingToolDraft }
struct TeachingToolCard: Identifiable {
    var id: String { sessionId }
    let sessionId: String; let revision: String; let kind: String; let title: String; let status: String; let canExport: Bool
    let controls: [String]; let roundId: String?; let clock: String?; let awaiting: Bool
    let random: TeachingToolRandom?; let laps: [(String, String)]; let input: TeachingToolInput?
    let canSubmit: Bool; let canReadResults: Bool; let ownRevision: String?; let initialSelection: [String]; let initialText: String; let canReview: Bool; let canManageTerms: Bool; let roundResults: TeachingToolResults?; let canEditDraft: Bool; let edit: TeachingToolEdit?; let canManageScores: Bool; let scoreGroups: [TeachingToolScoreGroup]; let scores: TeachingToolScores?; let canManageGroups: Bool; let canReadDefinition: Bool; let ownGroupId: String?; let groups: [TeachingToolGroup]; let groupMembers: [TeachingToolGroup.Member]; let statusColor: String?; let workMode: String?; let canReadOwn: Bool; let ownAnswerText: String?; let ownScore: Int?; let ownFeedback: String?
}
struct TeachingToolHistoryDetail: Identifiable { var id: String { card.sessionId + ":" + card.revision }; let recordedAt: String; let card: TeachingToolCard }
struct TeachingToolRewardTarget: Identifiable, Decodable {
    var id: String { sessionId }
    let sessionId: String
    let title: String
}
struct TeachingToolsView {
    let exports: [TeachingToolExport]
    let operations: [TeachingToolOperation]
    let canCreate: Bool; let nextCursor: String?; let availableKinds: [String]; let cards: [TeachingToolCard]; let history: TeachingToolHistory?; let historyDetails: [TeachingToolHistoryDetail]; let historyVersions: [TeachingToolHistoryVersions]; let scoreTargets: [TeachingToolRewardTarget]; let studentDirectory: TeachingToolStudentDirectory?
    /// Decode and format Core's prepared view on the serial query queue, never in a SwiftUI body.
    static func decode(_ json: String) throws -> TeachingToolsView {
        let view = try JSONDecoder().decode(CoreToolsView.self, from: Data(json.utf8))
        func time(_ ms: UInt64, stopwatch: Bool) -> String {
            let seconds = stopwatch ? ms / 1000 : ms / 1000 + (ms % 1000 == 0 ? 0 : 1)
            let base = String(format: "%02llu:%02llu", seconds / 60, seconds % 60)
            return stopwatch ? base + String(format: ".%02llu", ms % 1000 / 10) : base
        }
        func decodeCard(_ entry: CoreToolsView.Entry) throws -> TeachingToolCard {

            let session = entry.session
            let result = session.round?.result
            let roundId = session.participation?.roundId ?? session.round?.roundId
            let canEditDraft = entry.ui.canEditDraft && ["random_picker", "countdown", "stopwatch", "quiz", "poll", "buzzer", "random_props", "status_card", "word_cloud", "groups", "scores"].contains(session.config.kind)
            let edit = canEditDraft ? view.privateViews.compactMap { value -> TeachingToolEdit? in
                if case .definition(let definition) = value, definition.sessionId == session.sessionId { return definition }
                return nil
            }.first : nil
            let currentResults = view.privateViews.compactMap { value -> CoreToolResults? in
                if case .results(let result) = value, result.sessionId == session.sessionId, result.roundId == roundId { return result }
                return nil
            }.first
            func answerText(_ answer: TeachingToolAnswer) throws -> String? {
                switch answer.kind {
                case "choice":
                    guard let ids = answer.optionIds else { throw invalidView("Missing option IDs") }
                    return ids.map { id in entry.ui.input?.options?.first { $0.id == id }?.label ?? id }.joined(separator: " / ")
                case "text":
                    if let accepted = answer.acceptedAnswers { return accepted.joined(separator: " / ") }
                    guard let text = answer.text else { throw invalidView("Missing answer text") }; return text
                case "words":
                    guard let words = answer.words else { throw invalidView("Missing answer words") }; return words.joined(separator: " / ")
                case "buzz": return nil
                default: throw invalidView("Unknown answer kind")
                }
            }
            let roundResults = try currentResults.map { result in
                TeachingToolResults(quizSummary: result.quizSummary, submitted: result.submittedCount, eligible: result.eligibleCount, unanswered: result.unansweredCount,
                    correct: result.correctCount, pending: result.pendingCount, denominator: result.denominator,
                    optionCounts: result.optionCounts.map { row in (entry.ui.input?.options?.first { $0.id == row.optionId }?.label ?? row.optionId, row.count) },
                    winners: result.winners.map { ($0.displayName, $0.ordinal) }, words: result.words.map { TeachingToolWord(key: $0.key, word: $0.word, count: $0.count) }, hiddenWords: result.hiddenWords.map { TeachingToolWord(key: $0.key, word: $0.word, count: $0.count) },
                    submissions: try result.submissions.map { TeachingToolSubmission(id: $0.submissionId, userId: $0.userId, revision: $0.revision, answerText: try answerText($0.answer), score: $0.score, feedback: $0.feedback) },
                    answerText: try result.answerKey.flatMap(answerText), explanation: result.explanation, nextCursor: result.nextCursor, anonymous: result.anonymous)
            }
            let own = entry.ui.ownReceipt?.submission
            let answer = own?.answer
            var text = ""; var selection: [String] = []
            if let answer {
                switch answer.kind {
                case "choice": guard let ids = answer.optionIds else { throw invalidView("Missing option IDs") }; selection = ids
                case "text": guard let value = answer.text else { throw invalidView("Missing text") }; text = value
                case "words": guard let words = answer.words else { throw invalidView("Missing words") }; text = words.joined(separator: "\n")
                case "buzz": break
                default: throw invalidView("Unknown answer kind")
                }
            }
            let clock = entry.clock.flatMap { clock in
                clock.remainingMs.map { time($0, stopwatch: false) } ?? (session.config.kind == "stopwatch" ? time(clock.elapsedMs, stopwatch: true) : nil)
            }
            let periods = view.privateViews.compactMap { value -> TeachingToolScorePeriods? in if case let .scorePeriods(page) = value, page.sessionId == session.sessionId { return page }; return nil }.first
            let groups: [TeachingToolGroup]
            if result?.kind == "groups" { guard let rows = result?.groups else { throw invalidView("Missing groups") }; groups = rows } else { groups = [] }
            if session.config.kind == "status_card" { guard let color = session.config.color, let work = session.config.workMode, ["red", "yellow", "green"].contains(color), ["quiet", "collaborate", "speak"].contains(work) else { throw invalidView("Invalid status card fields") } }
            let scores = session.config.kind == "scores" ? TeachingToolScores(canReadPeriods: entry.ui.canReadScorePeriods, canReadLedger: entry.ui.canReadScoreLedger, canReadRank: entry.ui.canReadScoreRank, canReadAll: entry.ui.canReadAllScores, periods: periods?.periods ?? [], periodsCursor: periods?.nextCursor,
                pages: view.privateViews.compactMap { value -> TeachingToolScorePage? in if case let .scores(page, query) = value, page.sessionId == session.sessionId { return TeachingToolScorePage(page, query: query, reversible: Set(entry.ui.scoreReversibleEntryIds)) }; return nil }) : nil
            return TeachingToolCard(sessionId: session.sessionId, revision: session.revision, kind: session.config.kind, title: session.config.title,
                status: session.status, canExport: entry.ui.canExport, controls: entry.ui.controls, roundId: roundId,
                clock: clock, awaiting: entry.clock?.awaitingServerCompletion ?? false, random: entry.random,
                laps: session.laps.map { ($0.label, time($0.elapsedMs, stopwatch: true)) }, input: entry.ui.input,
                canSubmit: entry.ui.canRequestSubmit, canReadResults: entry.ui.canReadResults, ownRevision: own?.revision,
                initialSelection: selection, initialText: text, canReview: entry.ui.canReviewCurrentRound, canManageTerms: entry.ui.canManageTerms, roundResults: roundResults, canEditDraft: canEditDraft, edit: edit, canManageScores: entry.ui.canManageScores, scoreGroups: entry.ui.scoreGroups, scores: scores, canManageGroups: entry.ui.canManageGroups, canReadDefinition: entry.ui.canReadDefinition, ownGroupId: entry.ui.ownGroupId, groups: groups, groupMembers: groups.flatMap(\.members), statusColor: session.config.kind == "status_card" ? session.config.color : nil, workMode: session.config.kind == "status_card" ? session.config.workMode : nil, canReadOwn: entry.ui.canReadOwn, ownAnswerText: try own.flatMap { try answerText($0.answer) }, ownScore: own?.score, ownFeedback: own?.feedback)
        }
        return TeachingToolsView(exports: view.exports, operations: view.operations, canCreate: view.canCreate, nextCursor: view.nextCursor, availableKinds: view.availableKinds, cards: try view.sessions.map(decodeCard), history: view.history, historyDetails: try view.historyDetails.map { TeachingToolHistoryDetail(recordedAt: $0.recordedAt, card: try decodeCard(CoreToolsView.Entry(session: $0.session, ui: $0.ui, clock: $0.clock, random: $0.random))) }, historyVersions: view.historyVersions, scoreTargets: view.scoreTargets, studentDirectory: view.studentDirectory)
    }
}

private func invalidView(_ message: String) -> DecodingError {
    .dataCorrupted(.init(codingPath: [], debugDescription: message))
}

struct TeachingToolHistoryVersion: Decodable, Identifiable {
    var id: String { revision }; let revision: String; let kind: String; let title: String; let status: String; let recordedAt: String; let roundId: String?
}
struct TeachingToolHistoryVersions: Decodable, Identifiable {
    var id: String { sessionId }; let sessionId: String; let items: [TeachingToolHistoryVersion]; let nextCursor: String?
}

struct TeachingToolExport: Decodable, Identifiable {
    struct Job: Decodable {
        let exportId: String; let classroomId: String; let viewerUserId: String; let sessionId: String; let sourceRevision: String
        let status: String; let filename: String; let contentType: String
        @RequiredToolNullable var byteLength: Int64?
        @RequiredToolNullable var sha256: String?
        @RequiredToolNullable var rowCount: Int?
    }
    var id: String { job.exportId }
    let job: Job; let canDownload: Bool
    @RequiredToolNullable var downloadUrl: String?
}
