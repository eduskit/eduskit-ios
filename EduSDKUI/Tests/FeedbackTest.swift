import XCTest
import EduSDK
@testable import EduSDKUI

final class FeedbackTest: XCTestCase {
    @MainActor
    func testClassroomStatusUsesPersistentNotification() {
        let item = feedback(from: ClassroomLifecycleStatus.ended, canStart: false)

        if case .notification? = item?.mode {} else { XCTFail("expected notification") }
        if case .success? = item?.tone {} else { XCTFail("expected success tone") }
        XCTAssertNil(item?.autoDismissMs)
        XCTAssertFalse(item?.message.isEmpty ?? true)
    }

    @MainActor
    func testWaitingTeacherGetsStartAction() {
        let item = feedback(from: ClassroomLifecycleStatus.notStarted, canStart: true)

        XCTAssertTrue(item?.actions.contains(where: { $0.id == classroomStatusStartAction }) == true)
    }

    @MainActor
    func testInProgressDoesNotCreateStatusNotification() {
        XCTAssertNil(feedback(from: ClassroomLifecycleStatus.inProgress, canStart: true))
    }

    @MainActor
    func testRestrictionFeedbackUsesLocalizedActionInsteadOfInternalName() {
        let item = interactionRestrictionFeedback(
            action: "edit_whiteboard",
            reason: "classroom_not_started",
            localeTag: "en-US"
        )

        XCTAssertEqual(item.message, "Whiteboard collaboration will be available after class starts.")
        XCTAssertFalse(item.message.contains("{action}"))
        XCTAssertFalse(item.message.contains("edit_whiteboard"))
    }

    @MainActor
    func testDialogShowsCatalogCopyInsteadOfRawHttpBody() {
        let error = SdkError(
            code: .networkError,
            message: "join HTTP 500: {\"statusCode\":500,\"message\":\"Internal Server Error\"}"
        )
        let item = feedback(from: error, duringInitialization: true, localeTag: "zh-CN")

        XCTAssertEqual(item.mode, .dialog)
        XCTAssertEqual(item.message, EduI18n.text("feedbackEnterNetwork", localeTag: "zh-CN"))
        XCTAssertFalse(item.message.contains("HTTP"))
        XCTAssertFalse(item.message.contains("{"))
    }

    @MainActor
    func testDialogDiagnosticKeepsCodeMessageAndTraceId() {
        let error = SdkError(
            code: .networkError,
            message: "Unauthorized\ncode: 401\ntraceId: abc123"
        )
        let item = feedback(from: error, duringInitialization: true, localeTag: "zh-CN")

        XCTAssertEqual(item.diagnostic?.code, "401")
        XCTAssertEqual(item.diagnostic?.message, "Unauthorized")
        XCTAssertEqual(item.diagnostic?.traceId, "abc123")
    }
}
