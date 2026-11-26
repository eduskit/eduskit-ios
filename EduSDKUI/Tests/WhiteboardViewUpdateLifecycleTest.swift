import Combine
import XCTest
@testable import EduSDKUI

final class WhiteboardViewUpdateLifecycleTest: XCTestCase {
    @MainActor
    func testOldReadyCannotChangeSameRoomNewInstance() async {
        let host = WhiteboardHost.shared
        host.endSession()
        defer { host.endSession() }
        let config = WhiteboardConfig(roomId: "same-room", appId: "app-test", userId: "user-test",
            token: "token-test", serverHost: "https://wb.example.com")
        host.applyJoinCredentials(config)
        let old = host.acquireSession()!
        host.endSession()
        host.applyJoinCredentials(config)
        let current = host.acquireSession()!
        XCTAssertFalse(old === current)
        host.markEngineReady(true, report: false, source: old)
        XCTAssertFalse(host.engineReady)
        host.markEngineReady(true, report: false, source: current)
        host.markEngineReady(false, report: false, source: old)
        XCTAssertTrue(host.engineReady)
        XCTAssertFalse(host.engineFailed)
        host.applyHistory(from: current, canUndo: true, canRedo: false)
        host.applyHistory(from: old, canUndo: false, canRedo: true)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertTrue(host.history.canUndo)
        XCTAssertFalse(host.history.canRedo)
    }

    @MainActor
    func testFirstSessionAcquisitionDoesNotPublishObservableState() async {
        let host = WhiteboardHost.shared
        host.endSession()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        // 测试夹具：仅用于构造会话，不发起网络请求。
        let config = WhiteboardConfig(
            roomId: "room-test",
            appId: "app-test",
            userId: "user-test",
            token: "token-test",
            serverHost: "https://wb.example.com"
        )
        host.applyJoinCredentials(config)

        var publicationCount = 0
        let cancellable = host.objectWillChange.sink {
            publicationCount += 1
        }
        defer {
            cancellable.cancel()
            host.endSession()
        }

        XCTAssertNotNil(host.acquireSession())
        XCTAssertEqual(publicationCount, 0)
    }
}
