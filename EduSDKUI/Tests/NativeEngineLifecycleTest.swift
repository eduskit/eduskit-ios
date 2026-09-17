@testable import DrawsKit
import XCTest

final class NativeEngineLifecycleTest: XCTestCase {
    func testExportWorkspaceAfterDestroyIsNoOp() throws {
        guard NativeEngine.isLibLoaded else {
            throw XCTSkip("Whiteboard FFI is not linked")
        }
        guard let session = NativeEngine.EngineSession(
            documentId: "destroy-lifecycle",
            onFrame: { _ in }
        ) else {
            XCTFail("engine create failed")
            return
        }
        session.destroy()
        XCTAssertNil(session.exportWorkspaceJson(roomId: "room-1", checkpointSeq: 0))
        session.destroy()
    }
}
