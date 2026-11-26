import XCTest
import SwiftUI
import UIKit
@testable import EduSDKUI

@MainActor
final class ChatHistoryLifecycleTest: XCTestCase {
    func testControllerIgnoresHistoryBeforeJoinAndAfterDestroy() {
        let controller = ClassroomController(options: EduClassroomOptions(
            appId: "history-test", backendUrl: "https://example.invalid", classroomId: "class",
            userId: "user", displayName: "User"))
        controller.loadImMessageHistory()
        XCTAssertFalse(controller.snapshot.historyLoading)
        XCTAssertFalse(controller.snapshot.historyError)
        XCTAssertNil(controller.snapshot.feedback)
        controller.destroy()
        controller.loadImMessageHistory()
        XCTAssertFalse(controller.snapshot.historyLoading)
        XCTAssertNil(controller.snapshot.feedback)
    }

    func testChatAppearanceDoesNotStartHistoryBeforeOrAfterReady() async throws {
        var requests = 0
        for ready in [false, true] {
            let view = ClassroomChatView(messages: [], currentUserId: "student", onSendMessage: { _ in false })
                .environment(\.chatHistoryControls, ChatHistoryControls(load: { requests += 1 }, ready: ready))
            let host = UIHostingController(rootView: view)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 500))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(requests, 0, "Core join success owns the initial request; view appearance must not paginate")
            window.isHidden = true
            window.rootViewController = nil
        }
    }
}
