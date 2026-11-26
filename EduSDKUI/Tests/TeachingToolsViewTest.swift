import XCTest
@testable import EduSDKUI

final class TeachingToolsViewTest: XCTestCase {
    func testRewardTargetsComeOnlyFromCore() throws {
        var raw = try JSONSerialization.jsonObject(with: Data(fixture().utf8)) as! [String: Any]
        raw["scoreTargets"] = [["sessionId":"authorized", "title":"Core reward title"]]
        func decoded() throws -> TeachingToolsView { try TeachingToolsView.decode(String(data: JSONSerialization.data(withJSONObject: raw), encoding: .utf8)!) }
        XCTAssertEqual(try decoded().scoreTargets.first?.id, "authorized")
        XCTAssertEqual(try decoded().scoreTargets.first?.title, "Core reward title")
        raw["scoreTargets"] = []
        XCTAssertTrue(try decoded().scoreTargets.isEmpty)
        raw.removeValue(forKey: "scoreTargets")
        XCTAssertThrowsError(try decoded())
    }
    func testQuizTotalsKeepPendingNullFinalZeroAndStrictNullableKeys() throws {
        let data=Data(#"{"firstRoundId":"r1","questionCount":2,"startedQuestionCount":2,"closedQuestionCount":2,"completed":true,"eligibleAnswerCount":4,"submittedAnswerCount":3,"unansweredAnswerCount":1,"pendingAnswerCount":1,"gradedAnswerCount":2,"correctAnswerCount":1,"responseRateBps":7500,"correctRateBps":5000,"possiblePoints":10,"members":[{"userId":"u1","displayName":"Pending","eligibleQuestionCount":2,"submittedCount":2,"pendingCount":1,"correctCount":1,"earnedPoints":5,"maxPoints":10,"finalScore":null},{"userId":"u2","displayName":"Zero","eligibleQuestionCount":2,"submittedCount":1,"pendingCount":0,"correctCount":0,"earnedPoints":0,"maxPoints":10,"finalScore":0}],"nextCursor":"u2"}"#.utf8)
        let summary=try JSONDecoder().decode(TeachingToolQuizSummary.self,from:data)
        XCTAssertEqual(summary.nextCursor,"u2");XCTAssertEqual(summary.members[0].earnedPoints,5)
        XCTAssertNil(summary.members[0].finalScore);XCTAssertEqual(summary.members[1].finalScore,0)
        var raw=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        var members=raw["members"] as! [[String:Any]];members[0].removeValue(forKey:"finalScore");raw["members"]=members
        XCTAssertThrowsError(try JSONDecoder().decode(TeachingToolQuizSummary.self,from:JSONSerialization.data(withJSONObject:raw)))
    }
    private func fixture(kind: String = "quiz", own: [String: Any]? = nil, clock: [String: Any]? = nil, result: [String: Any]? = nil) throws -> String {
        let ui: [String: Any] = ["canExport":false,"canReadOwn": true,"canManageGroups": false, "canReadDefinition": false, "ownGroupId": NSNull(), "controls": ["close"], "canRequestSubmit": false, "canReadResults": true, "canReviewCurrentRound": false, "canReadScorePeriods": false, "canReadScoreLedger": false, "canReadScoreRank": false, "canReadAllScores": false, "scoreReversibleEntryIds": [], "canManageScores": false, "scoreGroups": [], "canManageTerms": false, "canEditDraft": false,
            "input": ["type": "single_choice", "prompt": "Choose", "options": [["id": "a", "label": "Alpha"]]],
            "ownReceipt": own as Any? ?? NSNull()]
        let session: [String: Any] = ["sessionId": "s1", "revision": "9007199254740993", "status": "active",
            "config": ["kind": kind, "title": "Tool", "color": "green", "workMode": "quiet"], "participation": ["roundId": "r1"],
            "round": result.map { ["roundId": "r1", "result": $0] } as Any? ?? NSNull(),
            "laps": [["label": "first", "elapsedMs": 1234]]]
        let view: [String: Any] = ["scoreTargets":[],"exports":[],"historyVersions":[],"historyDetails": [],"operations": [], "studentDirectory": NSNull(), "canCreate": false, "nextCursor": NSNull(), "availableKinds": [kind],
            "privateViews": [], "history": NSNull(), "sessions": [["session": session, "ui": ui, "random": NSNull(), "clock": clock as Any? ?? NSNull()]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: view), as: UTF8.self)
    }
    func testCorePermissionsAndExactPersonalRevision() throws {
        let own: [String: Any] = ["submission": ["score": NSNull(), "feedback": NSNull(), "revision": "9007199254740995", "answer": ["kind": "choice", "optionIds": ["a"]]]]
        let card = try TeachingToolsView.decode(fixture(own: own)).cards[0]
        XCTAssertFalse(card.canSubmit)
        XCTAssertEqual(card.revision, "9007199254740993")
        XCTAssertEqual(card.ownRevision, "9007199254740995")
        XCTAssertEqual(card.initialSelection, ["a"])
        XCTAssertEqual(card.controls, ["close"])
    }
    func testCountdownCeilingStopwatchHundredthsAndLaps() throws {
        let countdown = try TeachingToolsView.decode(fixture(kind: "countdown", clock: ["elapsedMs": 0, "remainingMs": 1, "awaitingServerCompletion": false])).cards[0]
        XCTAssertEqual(countdown.clock, "00:01")
        let stopwatch = try TeachingToolsView.decode(fixture(kind: "stopwatch", clock: ["elapsedMs": 61559, "remainingMs": NSNull(), "awaitingServerCompletion": false])).cards[0]
        XCTAssertEqual(stopwatch.clock, "01:01.55")
        XCTAssertEqual(stopwatch.laps[0].1, "00:01.23")
        let completed = try TeachingToolsView.decode(fixture(kind: "countdown", clock: ["elapsedMs": 1000, "remainingMs": 0, "awaitingServerCompletion": true])).cards[0]
        XCTAssertTrue(completed.awaiting)
    }
    func testMissingAuthorityFieldIsRejected() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture().utf8)) as! [String: Any]
        var entries = root["sessions"] as! [[String: Any]]
        var ui = entries[0]["ui"] as! [String: Any]
        ui.removeValue(forKey: "canRequestSubmit")
        entries[0]["ui"] = ui; root["sessions"] = entries
        let broken = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        XCTAssertThrowsError(try TeachingToolsView.decode(broken))
    }
    func testPreparedRandomResultIsRequiredAndNoLocalSelectionIsDerived() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture(kind: "random_props").utf8)) as! [String: Any]
        var entries = root["sessions"] as! [[String: Any]]
        entries[0]["random"] = ["mode":"dice", "roundId":"r1", "rotationDegrees":0, "poolWeight":0, "slices":[], "rows":[["id":"dice_0","label":"6","labelKey":NSNull(),"glyph":"⚅"],["id":"dice_1","label":"2","labelKey":NSNull(),"glyph":"⚁"]]] as [String:Any]
        root["sessions"]=entries
        let card=try TeachingToolsView.decode(String(decoding:JSONSerialization.data(withJSONObject:root),as:UTF8.self)).cards[0]
        XCTAssertEqual(card.random?.rows.map(\.label), ["6","2"])
        entries[0].removeValue(forKey:"random");root["sessions"]=entries
        XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding:JSONSerialization.data(withJSONObject:root),as:UTF8.self)))
    }
    func testTextWordsAndMalformedOwnAnswer() throws {
        let own: [String: Any] = ["submission": ["score": NSNull(), "feedback": NSNull(), "revision": "2", "answer": ["kind": "words", "words": ["First", "Second"]]]]
        XCTAssertEqual(try TeachingToolsView.decode(fixture(own: own)).cards[0].initialText, "First\nSecond")
        let invalid: [String: Any] = ["submission": ["score": NSNull(), "feedback": NSNull(), "revision": "2", "answer": ["kind": "choice"]]]
        XCTAssertThrowsError(try TeachingToolsView.decode(fixture(own: invalid)))
    }
    private func results(roundId: String) -> [String: Any] {
        ["sessionId": "s1", "roundId": roundId, "submittedCount": 2, "eligibleCount": 7, "unansweredCount": 5,
         "quizSummary": NSNull(),"correctCount": 1, "pendingCount": 0, "denominator": 2, "anonymous": false,
         "optionCounts": [["optionId": "a", "count": 2]], "winners": [["userId": "u1", "displayName": "Student", "ordinal": 1]], "words": [], "hiddenWords": [],
         "submissions": [["submissionId": "answer1", "userId": "u1", "revision": "9007199254740995",
                           "answer": ["kind": "choice", "optionIds": ["a", "other-id"]], "score": 0, "feedback": "Review"]],
         "answerKey": ["kind": "choice", "optionIds": ["a"]], "explanation": "Explanation", "nextCursor": "cursor2"]
    }
    private func resultFixture(roundId: String) throws -> String {
        var root = try JSONSerialization.jsonObject(with: Data(fixture().utf8)) as! [String: Any]
        root["privateViews"] = [["type": "results", "data": ["cursor": NSNull(), "response": results(roundId: roundId)]]]
        return String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
    }
    func testResultsKeepServerCountsLabelsAndExactSubmissionRevision() throws {
        let card = try TeachingToolsView.decode(resultFixture(roundId: "r1")).cards[0]
        let result = try XCTUnwrap(card.roundResults)
        XCTAssertEqual(result.eligible, 7)
        XCTAssertEqual(result.unanswered, 5)
        XCTAssertEqual(result.optionCounts[0].0, "Alpha")
        XCTAssertEqual(result.winners[0].0, "Student")
        XCTAssertEqual(result.submissions[0].answerText, "Alpha / other-id")
        XCTAssertEqual(result.submissions[0].revision, "9007199254740995")
        XCTAssertEqual(result.submissions[0].score, 0)
        XCTAssertEqual(result.submissions[0].feedback, "Review")
        XCTAssertEqual(result.answerText, "Alpha")
        XCTAssertEqual(result.nextCursor, "cursor2")
        XCTAssertFalse(card.canReview)
    }
    func testWordModerationPreservesKeysAndRequiresHiddenWords() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture(kind: "word_cloud").utf8)) as! [String: Any]
        var entries = root["sessions"] as! [[String: Any]]
        var policy = entries[0]["ui"] as! [String: Any]; policy["canManageTerms"] = true
        entries[0]["ui"] = policy; root["sessions"] = entries
        var response = results(roundId: "r1")
        response["words"] = [["key": "visible-key", "word": "Visible", "count": 2]]
        response["hiddenWords"] = [["key": "hidden-key", "word": "Hidden", "count": 1]]
        func frame() throws -> String {
            root["privateViews"] = [["type": "results", "data": ["response": response]]]
            return String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        }
        let card = try TeachingToolsView.decode(frame()).cards[0]
        XCTAssertTrue(card.canManageTerms)
        let result = try XCTUnwrap(card.roundResults)
        XCTAssertEqual(result.words[0].key, "visible-key"); XCTAssertEqual(result.words[0].count, 2)
        XCTAssertEqual(result.hiddenWords[0].key, "hidden-key")
        response.removeValue(forKey: "hiddenWords")
        XCTAssertThrowsError(try TeachingToolsView.decode(frame()))
    }
    func testOldRoundResultsAreNotShownWithNewQuestion() throws {
        XCTAssertNil(try TeachingToolsView.decode(resultFixture(roundId: "old-round")).cards[0].roundResults)
    }
    func testHistoryRemainsMetadataOutsideEditableCurrentCards() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture().utf8)) as! [String: Any]
        root["history"] = ["nextCursor": "h1", "items": [["item": ["sessionId": "h1", "kind": "buzzer", "title": "Previous",
            "revision": "9007199254740995", "lastUsedRevision": "9007199254740993", "lastUsedAt": "2026-10-02T00:00:00Z"]]]]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        let view = try TeachingToolsView.decode(json)
        XCTAssertEqual(view.cards.map(\.sessionId), ["s1"])
        XCTAssertEqual(view.history?.items[0].item.lastUsedRevision, "9007199254740993")
        XCTAssertEqual(view.history?.nextCursor, "h1")
    }
    func testMissingReviewPermissionAndUnknownPrivateViewFail() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture().utf8)) as! [String: Any]
        root["privateViews"] = [["type": "unknown-view", "data": [:]]]
        var json = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        XCTAssertThrowsError(try TeachingToolsView.decode(json))
        root["privateViews"] = []
        var entries = root["sessions"] as! [[String: Any]]
        var ui = entries[0]["ui"] as! [String: Any]
        ui.removeValue(forKey: "canReviewCurrentRound")
        entries[0]["ui"] = ui; root["sessions"] = entries
        json = String(decoding: try JSONSerialization.data(withJSONObject: root), as: UTF8.self)
        XCTAssertThrowsError(try TeachingToolsView.decode(json))
    }

    func testPrivateDefinitionPermissionAndExactRevision() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture(kind: "countdown").utf8)) as! [String: Any]
        var draft = TeachingToolDraft(); draft.title = "Timer"
        let definition: [String: Any] = ["sessionId": "s1", "revision": "9007199254740993", "config": try draft.config(trueLabel: "T", falseLabel: "F")]
        root["privateViews"] = [["type": "definition", "data": definition]]
        func decode() throws -> TeachingToolCard { try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)).cards[0] }
        XCTAssertNil(try decode().edit)
        var entries = root["sessions"] as! [[String: Any]]; var ui = entries[0]["ui"] as! [String: Any]
        ui["canEditDraft"] = true; entries[0]["ui"] = ui; root["sessions"] = entries
        XCTAssertEqual(try decode().edit?.revision, "9007199254740993")
        XCTAssertEqual(try decode().edit?.draft.title, "Timer")
        var session = entries[0]["session"] as! [String: Any]; session["revision"] = "9007199254740994"; entries[0]["session"] = session; root["sessions"] = entries
        XCTAssertNotEqual(try decode().edit?.revision, try decode().revision)
        var invalid = definition; invalid["revision"] = 9007199254740993 as Int64; root["privateViews"] = [["type": "definition", "data": invalid]]
        XCTAssertThrowsError(try decode())
    }

    func testScoreCandidatesPreserveCoreIdsCursorAndAuthority() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture(kind: "scores").utf8)) as! [String: Any]
        root["studentDirectory"] = ["loaded": true, "nextCursor": "opaque-next", "students": [["userId": "ungrouped", "displayName": "Ungrouped"]]]
        var entries = root["sessions"] as! [[String: Any]]; var ui = entries[0]["ui"] as! [String: Any]
        ui["canManageScores"] = true; ui["scoreGroups"] = [["groupId": "group-1", "name": "Group"]]; entries[0]["ui"] = ui; root["sessions"] = entries
        let frame = try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self))
        XCTAssertEqual(frame.studentDirectory?.nextCursor, "opaque-next")
        XCTAssertEqual(frame.studentDirectory?.students.first?.userId, "ungrouped")
        XCTAssertTrue(frame.cards[0].canManageScores); XCTAssertEqual(frame.cards[0].scoreGroups.first?.groupId, "group-1")
        root["studentDirectory"] = NSNull()
        XCTAssertNil(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)).studentDirectory)
    }
    func testRequiredDirectoryAndNullableCursorNeverSilentlyDefault() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture().utf8)) as! [String: Any]
        root.removeValue(forKey: "studentDirectory")
        XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)))
        root["studentDirectory"] = ["loaded": true, "students": []]
        XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)))
    }

    private func scoreQuery(_ view: String = "ledger", kind: Any = NSNull(), id: Any = NSNull()) -> [String: Any] {
        ["periodId": "period-1", "view": view, "targetKind": kind, "targetId": id, "cursor": "9007199254740991", "limit": 7]
    }
    private func scoreLedger() -> [String: Any] {
        ["view": "ledger", "sessionId": "s1", "periodId": "period-1", "target": ["kind": "user", "id": "student-1"], "balance": "9007199254740993", "nextCursor": "9007199254740995",
         "entries": [["entryId": "entry-1", "displayName": "Student", "delta": -3, "balanceAfter": "9007199254740993", "reason": "Correction", "createdAt": "2026-10-01T00:00:00Z", "origin": "manual", "reversed": false]]]
    }
    func testScorePeriodsLedgerRanksAndReversalFlagsPreserveExactStrings() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture(kind: "scores").utf8)) as! [String: Any]
        var entries = root["sessions"] as! [[String: Any]]; var ui = entries[0]["ui"] as! [String: Any]
        ui["canReadScorePeriods"] = true; ui["canReadScoreLedger"] = true; ui["canReadScoreRank"] = true; ui["scoreReversibleEntryIds"] = ["entry-1"]; entries[0]["ui"] = ui; root["sessions"] = entries
        let periods: [String: Any] = ["sessionId": "s1", "nextCursor": "9007199254740997", "periods": [["periodId": "period-1", "ordinal": "9007199254740993", "startedAt": "2026-10-01T00:00:00Z", "isClosed": true]]]
        let ranks: [String: Any] = ["view": "leaderboard", "sessionId": "s1", "periodId": "period-1", "targetKind": "group", "nextCursor": NSNull(), "rows": [["target": ["kind": "group", "id": "g1"], "displayName": "Group", "balance": "9007199254740999", "rank": "9007199254740993"]]]
        root["privateViews"] = [["type": "score_periods", "data": ["response": periods]], ["type": "scores", "data": ["query": scoreQuery(), "response": scoreLedger()]], ["type": "scores", "data": ["query": scoreQuery("leaderboard", kind: "group"), "response": ranks]]]
        let scores = try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)).cards[0].scores!
        XCTAssertEqual(scores.periodsCursor, "9007199254740997"); XCTAssertEqual(scores.periods[0].ordinal, "9007199254740993")
        XCTAssertNil(scores.pages[0].query.targetKind); XCTAssertNil(scores.pages[0].query.targetId)
        XCTAssertEqual(scores.pages[0].query.cursor, "9007199254740991"); XCTAssertEqual(scores.pages[0].query.limit, 7)
        XCTAssertEqual(scores.pages[0].balance, "9007199254740993"); XCTAssertEqual(scores.pages[0].nextCursor, "9007199254740995")
        XCTAssertEqual(scores.pages[0].entries[0].deltaText, "-3"); XCTAssertTrue(scores.pages[0].entries[0].canReverse)
        XCTAssertEqual(scores.pages[1].rows[0].balance, "9007199254740999"); XCTAssertEqual(scores.pages[1].rows[0].rank, "9007199254740993")
        ui["scoreReversibleEntryIds"] = []; entries[0]["ui"] = ui; root["sessions"] = entries
        XCTAssertFalse(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)).cards[0].scores!.pages[0].entries[0].canReverse)
    }
    func testScoreQueryRequiresNullableIdentityFields() throws {
        var query = scoreQuery()
        query.removeValue(forKey: "targetKind")
        XCTAssertThrowsError(try JSONDecoder().decode(TeachingToolScoreQuery.self, from: JSONSerialization.data(withJSONObject: query)))
        var root = try JSONSerialization.jsonObject(with: Data(fixture(kind: "scores").utf8)) as! [String: Any]
        root["privateViews"] = [["type": "scores", "data": ["response": scoreLedger()]]]
        XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)))
    }
    func testScoreNullableCursorIsRequiredAndUnrelatedSessionDoesNotLeak() throws {
        var ledger = scoreLedger(); ledger.removeValue(forKey: "nextCursor")
        XCTAssertThrowsError(try JSONDecoder().decode(CoreToolScorePage.self, from: JSONSerialization.data(withJSONObject: ledger)))
        ledger["nextCursor"] = NSNull(); ledger["sessionId"] = "other-session"
        var root = try JSONSerialization.jsonObject(with: Data(fixture(kind: "scores").utf8)) as! [String: Any]
        root["privateViews"] = [["type": "scores", "data": ["query": scoreQuery(), "response": ledger]]]
        XCTAssertTrue(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)).cards[0].scores!.pages.isEmpty)
    }

    func testRemainingPrivateDefinitionsAttachOnlyUnderCoreEditFlag() throws {
        for kind in ["random_props", "status_card", "word_cloud", "groups", "scores"] {
            var draft = TeachingToolDraft(); draft.kind = kind; draft.title = "Tool"; draft.scope = "all_students"
            let config = try draft.config(trueLabel: "T", falseLabel: "F")
            var root = try JSONSerialization.jsonObject(with: Data(fixture(kind: kind).utf8)) as! [String: Any]
            var entries = root["sessions"] as! [[String: Any]]; var ui = entries[0]["ui"] as! [String: Any]
            ui["canEditDraft"] = true; entries[0]["ui"] = ui; entries[0]["session"] = ["sessionId": "s1", "revision": "9007199254740993", "status": "draft", "config": ["kind": kind, "title": "Tool", "color": "green", "workMode": "quiet"], "participation": NSNull(), "round": NSNull(), "laps": []]; root["sessions"] = entries
            root["privateViews"] = [["type": "definition", "data": ["sessionId": "s1", "revision": "9007199254740993", "config": config]]]
            let frame = try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self))
            XCTAssertEqual(frame.cards[0].edit?.draft.kind, kind); XCTAssertEqual(frame.cards[0].edit?.revision, "9007199254740993")
            ui["canEditDraft"] = false; entries[0]["ui"] = ui; root["sessions"] = entries
            XCTAssertNil(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)).cards[0].edit)
        }
    }

    func testGroupsKeepCoreLeaderOwnGroupAndManageFlags() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture(kind: "groups").utf8)) as! [String: Any]
        var entries = root["sessions"] as! [[String: Any]]; var ui = entries[0]["ui"] as! [String: Any]; var session = entries[0]["session"] as! [String: Any]
        var groups: [[String: Any]] = [["groupId": "g1", "name": "First", "leaderId": "u1", "members": [["userId": "u1", "displayName": "One"]]], ["groupId": "g2", "name": "Second", "leaderId": NSNull(), "members": [["userId": "u2", "displayName": "Two"]]]]
        session["round"] = ["roundId": "group-round", "result": ["kind": "groups", "groups": groups]]; session["participation"] = NSNull()
        ui["canManageGroups"] = true; ui["canReadDefinition"] = true; entries[0]["ui"] = ui; entries[0]["session"] = session; root["sessions"] = entries
        let card = try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)).cards[0]
        XCTAssertTrue(card.canManageGroups); XCTAssertEqual(card.groups[0].leaderId, "u1"); XCTAssertNil(card.groups[1].leaderId); XCTAssertEqual(card.groupMembers.map(\.id), ["u1", "u2"])
        ui["canManageGroups"] = false; ui["canReadDefinition"] = false; ui["ownGroupId"] = "g2"; entries[0]["ui"] = ui; root["sessions"] = entries
        XCTAssertEqual(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)).cards[0].ownGroupId, "g2")
        groups[1].removeValue(forKey: "leaderId"); session["round"] = ["roundId": "group-round", "result": ["kind": "groups", "groups": groups]]; entries[0]["session"] = session; root["sessions"] = entries
        XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)))
    }
    func testOwnGroupAndStatusFieldsNeverSilentlyDefault() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture().utf8)) as! [String: Any]
        var entries = root["sessions"] as! [[String: Any]]; var ui = entries[0]["ui"] as! [String: Any]; ui.removeValue(forKey: "ownGroupId"); entries[0]["ui"] = ui; root["sessions"] = entries
        XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)))
        root = try JSONSerialization.jsonObject(with: Data(fixture(kind: "status_card").utf8)) as! [String: Any]; entries = root["sessions"] as! [[String: Any]]; var session = entries[0]["session"] as! [String: Any]; var config = session["config"] as! [String: Any]
        config["color"] = "red"; config["workMode"] = "speak"; session["config"] = config; entries[0]["session"] = session; root["sessions"] = entries
        let card = try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)).cards[0]; XCTAssertEqual(card.statusColor, "red"); XCTAssertEqual(card.workMode, "speak")
        config.removeValue(forKey: "workMode"); session["config"] = config; entries[0]["session"] = session; root["sessions"] = entries
        XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)))
        config["workMode"] = "unknown"; session["config"] = config; entries[0]["session"] = session; root["sessions"] = entries
        XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)))
    }

    func testOperationFeedbackPreservesOriginalIdentityAndRequiresCoreFacts() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture().utf8)) as! [String: Any]
        root["operations"] = [["requestId": "original", "operation": "submit", "sessionId": "s1", "status": "failed", "attempts": 2, "error": ["code": "NETWORK_ERROR", "message": "Unconfirmed"], "canRetry": true,"canResolve":true,"blocksWrites":true]]
        let encoded = try JSONSerialization.data(withJSONObject: root)
        let operation = try TeachingToolsView.decode(String(decoding: encoded, as: UTF8.self)).operations[0]
        XCTAssertEqual(operation.requestId, "original"); XCTAssertEqual(operation.attempts, 2); XCTAssertTrue(operation.canRetry); XCTAssertEqual(operation.error?.message, "Unconfirmed")
        root.removeValue(forKey: "operations")
        XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding: JSONSerialization.data(withJSONObject: root), as: UTF8.self)))
    }

    func testHistoryRetainsOriginalLabelsAndZeroScoreAlongsideNewDraft() throws {
        let own: [String: Any] = ["submission": ["revision": "3", "score": 0, "feedback": "Original feedback", "answer": ["kind": "choice", "optionIds": ["a"]]]]
        var root = try JSONSerialization.jsonObject(with: Data(fixture(own: own).utf8)) as! [String: Any]
        var live = (root["sessions"] as! [[String: Any]])[0]
        var old = live
        old["recordedAt"] = "2026-10-01T10:00:00Z"
        var oldUI = old["ui"] as! [String: Any]; oldUI["controls"] = [String](); oldUI["canRequestSubmit"] = false; old["ui"] = oldUI
        var session = live["session"] as! [String: Any]; session["revision"] = "9"; live["session"] = session
        var liveUI = live["ui"] as! [String: Any]; var input = liveUI["input"] as! [String: Any]; input["options"] = [["id": "a", "label": "Changed option"]]; liveUI["input"] = input; live["ui"] = liveUI
        root["sessions"] = [live]; root["historyDetails"] = [old]
        let json = String(data: try JSONSerialization.data(withJSONObject: root), encoding: .utf8)!
        let decoded = try TeachingToolsView.decode(json)
        XCTAssertEqual(decoded.cards[0].revision, "9")
        let history = decoded.historyDetails[0]
        XCTAssertEqual(history.recordedAt, "2026-10-01T10:00:00Z")
        XCTAssertEqual(history.card.revision, "9007199254740993")
        XCTAssertEqual(history.card.ownAnswerText, "Alpha")
        XCTAssertEqual(history.card.ownScore, 0)
        XCTAssertEqual(history.card.ownFeedback, "Original feedback")
        XCTAssertFalse(history.card.canSubmit); XCTAssertTrue(history.card.controls.isEmpty)
    }

    func testPublicHistoryVersionsPreserveLargeRevisionAndOriginalRound() throws {
        var root = try JSONSerialization.jsonObject(with: Data(fixture().utf8)) as! [String: Any]
        root["historyVersions"] = [["sessionId":"s1","nextCursor":"9007199254740993","items":[["revision":"9007199254740993","kind":"quiz","title":"Original question","status":"closed","recordedAt":"2026-10-01T00:00:00Z","roundId":"original-round"]]]]
        let page = try TeachingToolsView.decode(String(decoding:JSONSerialization.data(withJSONObject:root),as:UTF8.self)).historyVersions[0]
        XCTAssertEqual(page.nextCursor,"9007199254740993");XCTAssertEqual(page.items[0].roundId,"original-round");XCTAssertEqual(page.items[0].revision,"9007199254740993")
        root.removeValue(forKey:"historyVersions");XCTAssertThrowsError(try TeachingToolsView.decode(String(decoding:JSONSerialization.data(withJSONObject:root),as:UTF8.self)))
    }

    func testExportFrameKeepsExactRevisionAndRequiresNullableFields() throws {
        var raw=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(fixture().utf8)) as? [String:Any])
        let job:[String:Any]=["exportId":"export_1","classroomId":"cls_1","viewerUserId":"teacher_1","sessionId":"s1","sourceRevision":"9007199254740993","status":"queued","filename":"teaching-tools-export_1.csv","contentType":"text/csv; charset=utf-8","byteLength":NSNull(),"sha256":NSNull(),"rowCount":NSNull()]
        raw["exports"]=[["job":job,"canDownload":false,"downloadUrl":NSNull()]]
        func decode(_ raw:[String:Any])throws->TeachingToolsView {try TeachingToolsView.decode(String(decoding:JSONSerialization.data(withJSONObject:raw),as:UTF8.self))}
        let entry=try decode(raw).exports[0];XCTAssertEqual(entry.job.sourceRevision,"9007199254740993");XCTAssertNil(entry.downloadUrl);XCTAssertFalse(entry.canDownload)
        var missing=raw;missing.removeValue(forKey:"exports");XCTAssertThrowsError(try decode(missing))
        var jobs=job;jobs.removeValue(forKey:"sha256");missing=raw;missing["exports"]=[["job":jobs,"canDownload":false,"downloadUrl":NSNull()]];XCTAssertThrowsError(try decode(missing))
    }
}
