import XCTest
import EduSDK
@testable import EduSDKUI

final class FeedbackTest: XCTestCase {
    @MainActor
    func testTerminalClassroomNoticeStaysUntilDismissed() async throws {
        let item = try await prepareFeedback(feedback(from: ClassroomLifecycleStatus.ended, canStart: false))

        // 终态说明常驻：只读页面上所有禁用都靠它解释，一闪而过的 Toast 不够。
        if case .notification? = item?.mode {} else { XCTFail("expected notification") }
        if case .success? = item?.tone {} else { XCTFail("expected success tone") }
        XCTAssertNil(item?.autoDismissMs)
        XCTAssertTrue(item?.dismissible ?? false)
        XCTAssertFalse(item?.message.isEmpty ?? true)
    }

    @MainActor
    func testWaitingTeacherGetsStartAction() async throws {
        let item = try await prepareFeedback(feedback(from: ClassroomLifecycleStatus.notStarted, canStart: true))

        XCTAssertTrue(item?.actions.contains(where: { $0.id == classroomStatusStartAction }) == true)
    }

    @MainActor
    func testInProgressDoesNotCreateStatusNotification() async throws {
        let item = try await prepareFeedback(feedback(from: ClassroomLifecycleStatus.inProgress, canStart: true))
        XCTAssertNil(item)
    }

    @MainActor
    func testRestrictionFeedbackUsesLocalizedActionInsteadOfInternalName() async throws {
        let item = try await prepareFeedback(interactionRestrictionFeedback(
            action: "edit_whiteboard",
            reason: "classroom_not_started",
            localeTag: "en-US"
        ))

        XCTAssertEqual(item!.message, "Whiteboard collaboration will be available after class starts.")
        XCTAssertFalse(item!.message.contains("{action}"))
        XCTAssertFalse(item!.message.contains("edit_whiteboard"))
    }

    @MainActor
    func testDialogShowsCatalogCopyInsteadOfRawHttpBody() async throws {
        let error = SdkError(
            code: .networkError,
            message: "join HTTP 500: {\"statusCode\":500,\"message\":\"Internal Server Error\"}"
        )
        let item = try await prepareFeedback(feedback(from: error, duringInitialization: true, localeTag: "zh-CN"))

        XCTAssertEqual(item!.mode, .dialog)
        XCTAssertEqual(item!.message, EduI18n.text("feedbackEnterNetwork", localeTag: "en-US"))
        XCTAssertFalse(item!.message.contains("HTTP"))
        XCTAssertFalse(item!.message.contains("{"))
    }

    @MainActor
    func testDialogDiagnosticKeepsCodeMessageAndTraceId() async throws {
        let error = SdkError(
            code: .networkError,
            message: "Unauthorized\nerrorCode: CLASSROOM_NOT_MEMBER\ntraceId: abc123"
        )
        let item = try await prepareFeedback(feedback(from: error, duringInitialization: true, localeTag: "zh-CN"))

        // 后台 errorCode 比数值码更利于排障，存在时直接作为诊断码展示。
        XCTAssertEqual(item?.diagnostic?.code, "CLASSROOM_NOT_MEMBER")
        XCTAssertEqual(item?.diagnostic?.message, "Unauthorized")
        XCTAssertEqual(item?.diagnostic?.traceId, "abc123")
    }

    @MainActor
    func testPlainProviderMessageStaysInTheDiagnostic() async throws {
        let message = "Live license check failed: the app package name is not registered on this license (vendor code -4)"
        let error = SdkError(code: .liveProviderError, message: message)
        let item = try await prepareFeedback(feedback(from: error, duringInitialization: true, localeTag: "zh-CN"))

        XCTAssertEqual(item?.diagnostic?.code, "60001")
        XCTAssertEqual(item?.diagnostic?.message, message)
    }
}

@MainActor
func prepareFeedback(_ request: FeedbackRequest) async throws -> UiFeedback? {
    try await withCheckedThrowingContinuation { continuation in
        var presenter: FeedbackPresenter?
        presenter = FeedbackPresenter(locale: "en-US", onFrame: { frame in
            presenter?.close(); presenter = nil
            continuation.resume(returning: frame.current)
        }, onFailure: { error in
            presenter?.close(); presenter = nil
            continuation.resume(throwing: error)
        })
        presenter!.present(request)
    }
}
