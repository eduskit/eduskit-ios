import XCTest
@testable import EduSDKUI

final class TeachingToolDraftTest: XCTestCase {
    func testAuthoringInitialDurations() throws {
        XCTAssertEqual(try TeachingToolDraft().config(trueLabel: "T", falseLabel: "F")["durationMs"] as? Int64, 180000)
        XCTAssertEqual(TeachingQuestionDraft().seconds, "60")
    }
    func testQuizFiveTypesAndCorrectIds() throws {
        var single = TeachingQuestionDraft(); single.options = "A\nB"; single.optionIds = ["a", "b"]; single.correct = "2"
        var multiple = TeachingQuestionDraft(); multiple.kind = "multiple"; multiple.options = "A\nB\nC"; multiple.optionIds = ["x", "y", "z"]; multiple.correct = "1,3"
        var judgement = TeachingQuestionDraft(); judgement.kind = "true_false"; judgement.correct = "false"
        var fill = TeachingQuestionDraft(); fill.kind = "fill"; fill.accepted = "One\n1"; fill.caseSensitive = true
        var short = TeachingQuestionDraft(); short.kind = "short"
        var draft = TeachingToolDraft(); draft.kind = "quiz"; draft.questions = [single, multiple, judgement, fill, short]; draft.rewardScoreSessionId = "scores1"
        let config = try draft.config(trueLabel: "是", falseLabel: "否")
        let questions = try XCTUnwrap(config["questions"] as? [[String: Any]])
        XCTAssertEqual((questions[0]["answerKey"] as? [String: Any])?["optionIds"] as? [String], ["b"])
        XCTAssertEqual((questions[1]["answerKey"] as? [String: Any])?["optionIds"] as? [String], ["x", "z"])
        XCTAssertEqual((questions[2]["options"] as? [[String: String]])?[1]["label"], "否")
        XCTAssertEqual((questions[3]["answerKey"] as? [String: Any])?["acceptedAnswers"] as? [String], ["One", "1"])
        XCTAssertTrue(questions[4]["answerKey"] is NSNull)
        XCTAssertEqual(config["rewardScoreSessionId"] as? String, "scores1")
        XCTAssertEqual(questions[0]["id"] as? String, single.id)
    }
    func testExactDurationAndTargetIds() throws {
        var draft = TeachingToolDraft(); draft.kind = "buzzer"; draft.seconds = "1.001"; draft.scope = "selected_students"; draft.userIds = "a, b\nc"
        let config = try draft.config(trueLabel: "T", falseLabel: "F")
        XCTAssertEqual(config["durationMs"] as? Int64, 1001)
        XCTAssertEqual((config["target"] as? [String: Any])?["userIds"] as? [String], ["a", "b", "c"])
        XCTAssertTrue(config["rewardScoreSessionId"] is NSNull)
        draft.seconds = "1.0001"
        XCTAssertThrowsError(try draft.config(trueLabel: "T", falseLabel: "F"))
    }
    func testJudgementLabelsAndIdsArePreserved() throws {
        var question = TeachingQuestionDraft(); question.kind = "true_false"; question.optionIds = ["false", "true"]; question.options = "No custom\nYes custom"; question.correct = "true"
        var draft = TeachingToolDraft(); draft.kind = "quiz"; draft.questions = [question]
        let questions = try XCTUnwrap(draft.config(trueLabel: "Changed", falseLabel: "Changed")["questions"] as? [[String: Any]])
        XCTAssertEqual(questions[0]["options"] as? [[String: String]], [["id": "false", "label": "No custom"], ["id": "true", "label": "Yes custom"]])
        XCTAssertEqual((questions[0]["answerKey"] as? [String: Any])?["optionIds"] as? [String], ["true"])
    }
    func testAddedPollOptionsDoNotCollideAndInvalidCorrectIndexFails() throws {
        var draft = TeachingToolDraft(); draft.kind = "poll"; draft.options = "A\nB\nC"; draft.pollOptionIds = ["choice3", "choice1"]
        let options = try XCTUnwrap(draft.config(trueLabel: "T", falseLabel: "F")["options"] as? [[String: String]])
        XCTAssertEqual(options[0]["id"], "choice3")
        XCTAssertEqual(options[1]["id"], "choice1")
        XCTAssertFalse(["choice3", "choice1"].contains(options[2]["id"]!))
        draft.kind = "quiz"; draft.questions[0].options = "A\nB"; draft.questions[0].correct = "3"
        XCTAssertThrowsError(try draft.config(trueLabel: "T", falseLabel: "F"))
        draft.questions[0].correct = String(Int.min)
        XCTAssertThrowsError(try draft.config(trueLabel: "T", falseLabel: "F"))
    }
    func testPickerScopeAndBuzzerRewardsAreExplicit() throws {
        var draft = TeachingToolDraft(); draft.kind = "random_picker"; draft.scope = "on_stage_students"; draft.excludeIds = "u1,u2"; draft.noRepeat = false
        var config = try draft.config(trueLabel: "T", falseLabel: "F")
        XCTAssertEqual(config["scope"] as? String, "on_stage_students")
        XCTAssertEqual(config["excludeUserIds"] as? [String], ["u1", "u2"])
        XCTAssertEqual(config["noRepeat"] as? Bool, false)
        draft.kind = "buzzer"; draft.rewardScoreSessionId = "score1"; draft.rewardPoints = "7"
        config = try draft.config(trueLabel: "T", falseLabel: "F")
        XCTAssertEqual(config["rewardPoints"] as? Int, 7)
        XCTAssertEqual(config["rewardScoreSessionId"] as? String, "score1")
    }
    private func roundTrip(_ config: [String: Any]) throws -> [String: Any] {
        let draft = try JSONDecoder().decode(TeachingToolDraft.self, from: JSONSerialization.data(withJSONObject: config))
        return try draft.config(trueLabel: "Changed true", falseLabel: "Changed false")
    }
    func testSixKindsRoundTripPreservesAuthoringFields() throws {
        for kind in ["random_picker", "countdown", "stopwatch", "quiz", "poll", "buzzer"] {
            var draft = TeachingToolDraft(); draft.kind = kind; draft.title = "Tool"; draft.seconds = "1.001"
            draft.count = "2"; draft.scope = "selected_students"; draft.userIds = "u1,u2"; draft.excludeIds = "u3"
            draft.display = "wheel"; draft.noRepeat = false; draft.sound = false; draft.allowChanges = true
            draft.prompt = "Pick"; draft.options = "A\nB"; draft.pollOptionIds = ["custom-a", "custom-b"]
            draft.rewardScoreSessionId = "score1"; draft.rewardPoints = "3"; draft.questions[0].options = "A\nB"; draft.questions[0].optionIds = ["one", "two"]
            let config = try draft.config(trueLabel: "Yes", falseLabel: "No")
            XCTAssertTrue(NSDictionary(dictionary: config).isEqual(to: try roundTrip(config)), kind)
        }
    }
    func testQuizEditingPreservesFiveKindsAndCustomJudgementOrder() throws {
        var single = TeachingQuestionDraft(); single.options = "A\nB"; single.optionIds = ["a", "b"]; single.correct = "2"
        var multiple = single; multiple.id = "multiple-id"; multiple.kind = "multiple"; multiple.correct = "1,2"
        var judgement = TeachingQuestionDraft(); judgement.kind = "true_false"; judgement.optionIds = ["false", "true"]; judgement.options = "否\n是"; judgement.correct = "true"
        var fill = TeachingQuestionDraft(); fill.kind = "fill"; fill.accepted = "One\n1"; fill.caseSensitive = true; fill.trimWhitespace = false
        var short = TeachingQuestionDraft(); short.kind = "short"; short.explanation = "Explain"
        var draft = TeachingToolDraft(); draft.kind = "quiz"; draft.questions = [single, multiple, judgement, fill, short]
        let config = try draft.config(trueLabel: "Yes", falseLabel: "No")
        XCTAssertTrue(NSDictionary(dictionary: config).isEqual(to: try roundTrip(config)))
    }
    func testMissingRequiredNullableAndMissingAuthoringAnswerKeyAreRejected() throws {
        var draft = TeachingToolDraft(); draft.kind = "buzzer"
        var config = try draft.config(trueLabel: "T", falseLabel: "F"); config.removeValue(forKey: "rewardScoreSessionId")
        XCTAssertThrowsError(try roundTrip(config))
        draft.kind = "quiz"; draft.questions[0].options = "A\nB"
        config = try draft.config(trueLabel: "T", falseLabel: "F")
        var questions = config["questions"] as! [[String: Any]]; questions[0].removeValue(forKey: "answerKey"); config["questions"] = questions
        XCTAssertThrowsError(try roundTrip(config))
    }

    func testRemainingAuthoringVariantsRoundTripIdsWeightsNullDurationAndPrivateFlags() throws {
        for (kind, mode, timed) in [("random_props", "dice", false), ("random_props", "coin", false), ("random_props", "wheel", false), ("status_card", "dice", false), ("status_card", "dice", true), ("word_cloud", "dice", false), ("groups", "dice", false), ("scores", "dice", false)] {
            var draft = TeachingToolDraft(); draft.kind = kind; draft.title = "Tool"; draft.propMode = mode; draft.timed = timed; draft.seconds = "1.001"
            draft.diceCount = "4"; draft.wheel = "Label|part|2\nBeta|5"; draft.wheelIds = ["preserved-1", "preserved-2"]; draft.noRepeat = false
            draft.color = "yellow"; draft.workMode = "collaborate"; draft.scope = "selected_students"; draft.userIds = "u1,u2"; draft.excludeIds = "u3"
            draft.allocationMode = "group_size"; draft.allocationValue = "3"; draft.maxWords = "5"; draft.mergeLatinCase = false; draft.allowChanges = true; draft.showLiveResults = true; draft.prompt = "Explain"; draft.showLeaderboard = true; draft.scoreVisual = "trophies"
            let config = try draft.config(trueLabel: "T", falseLabel: "F")
            XCTAssertTrue(NSDictionary(dictionary: config).isEqual(to: try roundTrip(config)), kind + ":" + mode)
            let decoded = try JSONDecoder().decode(TeachingToolDraft.self, from: JSONSerialization.data(withJSONObject: config))
            if kind == "random_props" && mode == "wheel" { XCTAssertEqual(decoded.wheelIds, draft.wheelIds); XCTAssertEqual(decoded.wheel, draft.wheel) }
            if kind == "status_card" { XCTAssertEqual(decoded.timed, timed) }
        }
    }
    func testNewAuthoringFieldsDoNotDefaultMissingDurationOrWheelWeight() throws {
        XCTAssertThrowsError(try roundTrip(["kind": "status_card", "title": "Status", "color": "green", "workMode": "quiet"]))
        var draft = TeachingToolDraft(); draft.kind = "random_props"; draft.propMode = "wheel"; draft.wheel = "Missing weight"
        XCTAssertThrowsError(try draft.config(trueLabel: "T", falseLabel: "F"))
        draft.kind = "status_card"; draft.timed = true; draft.seconds = "0.0001"
        XCTAssertThrowsError(try draft.config(trueLabel: "T", falseLabel: "F"))
    }

}
