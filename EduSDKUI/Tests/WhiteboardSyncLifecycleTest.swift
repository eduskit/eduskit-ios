import XCTest
import EduSDK
@testable import EduSDKUI

final class WhiteboardSyncLifecycleTest: XCTestCase {
    @MainActor
    func testEndedPhaseUnbindsWhiteboardSync() {
        var unbindCount = 0

        ClassroomController.unbindWhiteboardSyncIfEnded(phase: .ended) {
            unbindCount += 1
        }

        XCTAssertEqual(unbindCount, 1)
    }

    @MainActor
    func testActivePhasesKeepWhiteboardSyncBound() {
        var unbindCount = 0

        for phase in [ClassPhase.entered, .inClass] {
            ClassroomController.unbindWhiteboardSyncIfEnded(phase: phase) {
                unbindCount += 1
            }
        }

        XCTAssertEqual(unbindCount, 0)
    }
}
