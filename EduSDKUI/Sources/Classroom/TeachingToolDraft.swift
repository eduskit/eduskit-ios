import Foundation

struct TeachingQuestionDraft: Identifiable {
    var id = UUID().uuidString
    var optionIds: [String] = []
    var kind = "single"
    var stem = ""
    var options = ""
    var correct = "1"
    var accepted = ""
    var points = String(TeachingToolAuthoringNumbers.points.initial)
    var seconds = TeachingToolAuthoringNumbers.questionDurationMsInitialSeconds
    var explanation = ""
    var caseSensitive = false
    var trimWhitespace = true
}
struct TeachingToolDraft {
    var kind = "countdown"
    var title = ""
    var seconds = TeachingToolAuthoringNumbers.durationMsInitialSeconds
    var count = String(TeachingToolAuthoringNumbers.pickerCount.initial)
    var noRepeat = true
    var sound = true
    var scope = "present_students"
    var userIds = ""
    var excludeIds = ""
    var display = "cards"
    var allowChanges = false
    var prompt = ""
    var options = ""
    var minChoices = String(TeachingToolAuthoringNumbers.selectionCount.initial)
    var maxChoices = String(TeachingToolAuthoringNumbers.selectionCount.initial)
    var anonymous = true
    var showLiveResults = false
    var rewardScoreSessionId: String?
    var rewardPoints = String(TeachingToolAuthoringNumbers.rewardPoints.initial)
    var questions = [TeachingQuestionDraft()]
    var propMode = "dice"; var diceCount = String(TeachingToolAuthoringNumbers.diceCount.initial); var wheel = ""; var wheelIds: [String] = []
    var color = "green"; var workMode = "quiet"; var timed = false
    var maxWords = String(TeachingToolAuthoringNumbers.maxWords.initial); var mergeLatinCase = true
    var allocationMode = "group_count"; var allocationValue = String(TeachingToolAuthoringNumbers.groupCount.initial)
    var showLeaderboard = false; var scoreVisual = "stars"
    var pollOptionIds: [String] = []

    /// Only background form encoding. Core/backend own rule validation and execution.
    func config(trueLabel: String, falseLabel: String) throws -> [String: Any] {
        func lines(_ value: String) -> [String] { value.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        func ids(_ value: String) -> [String] { value.split { $0.isWhitespace || $0 == "," }.map(String.init) }
        func integer(_ value: String) throws -> Int {
            guard let number = Int(value) else { throw invalidDraft("Invalid integer") }; return number
        }
        func duration(_ value: String) throws -> Int64 {
            let number = NSDecimalNumber(string: value, locale: Locale(identifier: "en_US_POSIX")).multiplying(by: 1000)
            guard let milliseconds = Int64(number.stringValue) else { throw invalidDraft("Invalid duration") }; return milliseconds
        }
        func itemId(_ existing: [String], _ index: Int) -> String { index < existing.count ? existing[index] : UUID().uuidString }
        var config: [String: Any] = ["kind": kind, "title": title]
        let target: [String: Any] = ["scope": scope, "userIds": ids(userIds)]
        switch kind {
        case "countdown": config["durationMs"] = try duration(seconds); config["sound"] = sound
        case "stopwatch": break
        case "scores": config["showLeaderboard"] = showLeaderboard; config["visual"] = scoreVisual
        case "groups": config.merge(["scope": scope, "userIds": ids(userIds), "excludeUserIds": ids(excludeIds), "allocation": ["mode": allocationMode, "value": try integer(allocationValue)]]) { _, new in new }
        case "status_card": config.merge(["color": color, "workMode": workMode, "durationMs": timed ? try duration(seconds) : NSNull()]) { _, new in new }
        case "word_cloud": config.merge(["target": target, "prompt": prompt, "maxWords": try integer(maxWords), "durationMs": try duration(seconds), "allowChanges": allowChanges, "mergeLatinCase": mergeLatinCase, "showLiveResults": showLiveResults]) { _, new in new }
        case "random_props":
            config["mode"] = propMode
            switch propMode {
            case "coin": break
            case "dice": config["diceCount"] = try integer(diceCount)
            case "wheel":
                config["noRepeat"] = noRepeat
                config["items"] = try lines(wheel).enumerated().map { index, line -> [String: Any] in
                    guard let separator = line.lastIndex(of: "|") else { throw invalidDraft("Missing wheel weight separator") }
                    return ["id": itemId(wheelIds, index), "label": String(line[..<separator]), "weight": try integer(String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces))]
                }
            default: throw invalidDraft("Unknown random prop mode")
            }
        case "random_picker":
            config.merge(["count": try integer(count), "noRepeat": noRepeat, "scope": scope, "userIds": ids(userIds), "excludeUserIds": ids(excludeIds), "display": display]) { _, new in new }
        case "buzzer":
            config.merge(["target": target, "winners": try integer(count), "durationMs": try duration(seconds), "rewardScoreSessionId": rewardScoreSessionId as Any? ?? NSNull(), "rewardPoints": try integer(rewardPoints)]) { _, new in new }
        case "poll":
            config.merge(["target": target, "question": prompt, "options": lines(options).enumerated().map { ["id": itemId(pollOptionIds, $0.offset), "label": $0.element] },
                "minChoices": try integer(minChoices), "maxChoices": try integer(maxChoices), "durationMs": try duration(seconds), "allowChanges": allowChanges, "anonymous": anonymous, "showLiveResults": showLiveResults]) { _, new in new }
        case "quiz":
            config["target"] = target; config["rewardScoreSessionId"] = rewardScoreSessionId as Any? ?? NSNull(); config["allowChanges"] = allowChanges
            config["questions"] = try questions.map { question -> [String: Any] in
                let options: [[String: String]]
                switch question.kind {
                case "true_false":
                    if question.optionIds.count == 2 {
                        let labels = lines(question.options)
                        guard labels.count == 2 else { throw invalidDraft("Invalid judgement labels") }
                        options = question.optionIds.enumerated().map { ["id": $0.element, "label": labels[$0.offset]] }
                    } else { options = [["id": "true", "label": trueLabel], ["id": "false", "label": falseLabel]] }
                case "single", "multiple": options = lines(question.options).enumerated().map { ["id": itemId(question.optionIds, $0.offset), "label": $0.element] }
                case "fill", "short": options = []
                default: throw invalidDraft("Unknown question type")
                }
                let key: Any
                switch question.kind {
                case "short": key = NSNull()
                case "fill": key = ["kind": "text", "acceptedAnswers": lines(question.accepted), "caseSensitive": question.caseSensitive, "trimWhitespace": question.trimWhitespace]
                default:
                    let answers = try ids(question.correct).map { value -> String in
                        if question.kind == "true_false" { return value }
                        let (index, overflow) = try integer(value).subtractingReportingOverflow(1)
                        guard !overflow, options.indices.contains(index), let id = options[index]["id"] else { throw invalidDraft("Invalid correct option") }; return id
                    }
                    key = ["kind": "choice", "optionIds": answers]
                }
                return ["id": question.id, "kind": question.kind, "stem": question.stem, "options": options,
                    "points": try integer(question.points), "durationMs": try duration(question.seconds), "answerKey": key, "explanation": question.explanation]
            }
        default: throw invalidDraft("Unsupported authoring tool")
        }
        return config
    }
}
private func invalidDraft(_ message: String) -> NSError { NSError(domain: "TeachingToolForm", code: 5, userInfo: [NSLocalizedDescriptionKey: message]) }

extension TeachingQuestionDraft: Decodable {
    private enum Keys: String, CodingKey { case id, kind, stem, options, points, durationMs, explanation, answerKey }
    private struct Key: Decodable { let kind: String; let optionIds: [String]?; let acceptedAnswers: [String]?; let caseSensitive: Bool?; let trimWhitespace: Bool? }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: Keys.self)
        id = try c.decode(String.self, forKey: .id); kind = try c.decode(String.self, forKey: .kind)
        stem = try c.decode(String.self, forKey: .stem)
        let choices = try c.decode([TeachingToolOption].self, forKey: .options)
        optionIds = choices.map(\.id); options = choices.map(\.label).joined(separator: "\n")
        points = String(try c.decode(Int.self, forKey: .points))
        seconds = NSDecimalNumber(value: try c.decode(Int64.self, forKey: .durationMs)).dividing(by: 1000).stringValue
        explanation = try c.decode(String.self, forKey: .explanation)
        let key = try c.decode(Key?.self, forKey: .answerKey)
        switch kind {
        case "single", "multiple", "true_false":
            guard key?.kind == "choice", let ids = key?.optionIds else { throw invalidDraft("Missing choice answer key") }
            correct = try ids.map { value in
                if kind == "true_false" { return value }
                guard let index = choices.firstIndex(where: { $0.id == value }) else { throw invalidDraft("Unknown correct option") }
                return String(index + 1)
            }.joined(separator: ",")
        case "fill":
            guard key?.kind == "text", let answers = key?.acceptedAnswers, let sensitive = key?.caseSensitive, let trim = key?.trimWhitespace else { throw invalidDraft("Missing fill answer key") }
            accepted = answers.joined(separator: "\n"); caseSensitive = sensitive; trimWhitespace = trim
        case "short": guard key == nil else { throw invalidDraft("Unexpected short answer key") }
        default: throw invalidDraft("Unknown question type")
        }
    }
}
extension TeachingToolDraft: Decodable {
    private enum Keys: String, CodingKey {
        case kind, title, durationMs, count, noRepeat, sound, scope, userIds, excludeUserIds, display, target, winners, rewardScoreSessionId, rewardPoints
        case question, options, minChoices, maxChoices, allowChanges, anonymous, showLiveResults, questions
        case mode, diceCount, items, color, workMode, prompt, maxWords, mergeLatinCase, allocation, showLeaderboard, visual
    }
    private struct WheelItem: Decodable { let id: String; let label: String; let weight: Int }
    private struct Allocation: Decodable { let mode: String; let value: Int }
    private struct Target: Decodable { let scope: String; let userIds: [String] }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: Keys.self)
        kind = try c.decode(String.self, forKey: .kind); title = try c.decode(String.self, forKey: .title)
        if ["countdown", "poll", "buzzer", "word_cloud"].contains(kind) {
            seconds = NSDecimalNumber(value: try c.decode(Int64.self, forKey: .durationMs)).dividing(by: 1000).stringValue
        }
        if ["quiz", "poll", "buzzer", "word_cloud"].contains(kind) {
            let target = try c.decode(Target.self, forKey: .target); scope = target.scope; userIds = target.userIds.joined(separator: ", ")
        }
        if ["quiz", "buzzer"].contains(kind) { rewardScoreSessionId = try c.decode(String?.self, forKey: .rewardScoreSessionId) }
        switch kind {
        case "countdown": sound = try c.decode(Bool.self, forKey: .sound)
        case "stopwatch": break
        case "scores": showLeaderboard = try c.decode(Bool.self, forKey: .showLeaderboard); scoreVisual = try c.decode(String.self, forKey: .visual)
        case "groups":
            scope = try c.decode(String.self, forKey: .scope); userIds = try c.decode([String].self, forKey: .userIds).joined(separator: ", ")
            excludeIds = try c.decode([String].self, forKey: .excludeUserIds).joined(separator: ", ")
            let allocation = try c.decode(Allocation.self, forKey: .allocation); allocationMode = allocation.mode; allocationValue = String(allocation.value)
        case "status_card":
            color = try c.decode(String.self, forKey: .color); workMode = try c.decode(String.self, forKey: .workMode)
            let milliseconds = try c.decode(Int64?.self, forKey: .durationMs); timed = milliseconds != nil
            if let milliseconds { seconds = NSDecimalNumber(value: milliseconds).dividing(by: 1000).stringValue }
        case "word_cloud":
            prompt = try c.decode(String.self, forKey: .prompt); maxWords = String(try c.decode(Int.self, forKey: .maxWords))
            allowChanges = try c.decode(Bool.self, forKey: .allowChanges); mergeLatinCase = try c.decode(Bool.self, forKey: .mergeLatinCase); showLiveResults = try c.decode(Bool.self, forKey: .showLiveResults)
        case "random_props":
            propMode = try c.decode(String.self, forKey: .mode)
            switch propMode {
            case "coin": break
            case "dice": diceCount = String(try c.decode(Int.self, forKey: .diceCount))
            case "wheel": let items = try c.decode([WheelItem].self, forKey: .items); wheelIds = items.map(\.id); wheel = items.map { $0.label + "|" + String($0.weight) }.joined(separator: "\n"); noRepeat = try c.decode(Bool.self, forKey: .noRepeat)
            default: throw invalidDraft("Unknown random prop mode")
            }
        case "random_picker":
            count = String(try c.decode(Int.self, forKey: .count)); noRepeat = try c.decode(Bool.self, forKey: .noRepeat)
            scope = try c.decode(String.self, forKey: .scope); userIds = try c.decode([String].self, forKey: .userIds).joined(separator: ", ")
            excludeIds = try c.decode([String].self, forKey: .excludeUserIds).joined(separator: ", "); display = try c.decode(String.self, forKey: .display)
        case "buzzer": count = String(try c.decode(Int.self, forKey: .winners)); rewardPoints = String(try c.decode(Int.self, forKey: .rewardPoints))
        case "poll":
            prompt = try c.decode(String.self, forKey: .question)
            let choices = try c.decode([TeachingToolOption].self, forKey: .options)
            options = choices.map(\.label).joined(separator: "\n"); pollOptionIds = choices.map(\.id)
            minChoices = String(try c.decode(Int.self, forKey: .minChoices)); maxChoices = String(try c.decode(Int.self, forKey: .maxChoices))
            allowChanges = try c.decode(Bool.self, forKey: .allowChanges); anonymous = try c.decode(Bool.self, forKey: .anonymous)
            showLiveResults = try c.decode(Bool.self, forKey: .showLiveResults)
        case "quiz": allowChanges = try c.decode(Bool.self, forKey: .allowChanges); questions = try c.decode([TeachingQuestionDraft].self, forKey: .questions)
        default: throw invalidDraft("Unsupported authoring tool")
        }
    }
}
