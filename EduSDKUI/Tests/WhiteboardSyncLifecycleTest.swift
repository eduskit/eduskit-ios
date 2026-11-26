import XCTest
import EduSDK
@testable import EduSDKUI

final class WhiteboardSyncLifecycleTest: XCTestCase {
    @MainActor
    func testTerminalStatusesUnbindWhiteboardSync() {
        var unbindCount = 0

        for status in [ClassroomLifecycleStatus.ended, .expired] {
            ClassroomController.unbindWhiteboardSyncIfTerminal(lifecycleStatus: status) {
                unbindCount += 1
            }
        }

        XCTAssertEqual(unbindCount, 2)
    }

    @MainActor
    func testActiveStatusesKeepWhiteboardSyncBound() {
        var unbindCount = 0

        for status in [ClassroomLifecycleStatus.notStarted, .inProgress] {
            ClassroomController.unbindWhiteboardSyncIfTerminal(lifecycleStatus: status) {
                unbindCount += 1
            }
        }

        XCTAssertEqual(unbindCount, 0)
    }
}
