import Combine
import XCTest
@testable import EduSDKUI

final class WhiteboardViewUpdateLifecycleTest: XCTestCase {
    @MainActor
    func testFirstSessionAcquisitionDoesNotPublishObservableState() async {
        let host = WhiteboardHost.shared
        host.endSession()
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }

        let config = WhiteboardConfig()
        host.applyJoinCredentials(config)

        var publicationCount = 0
        let cancellable = host.objectWillChange.sink {
            publicationCount += 1
        }
        defer {
            cancellable.cancel()
            host.endSession()
        }

        XCTAssertNotNil(host.acquireSession(config: config))
        XCTAssertEqual(publicationCount, 0)
    }
}
