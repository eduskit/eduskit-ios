import XCTest
@testable import EduSDKUI

final class ClassroomInitEpochTest: XCTestCase {
    func testDownstreamThrowIsReportedWithoutEscaping() {
        let gate = ClassroomInitEpoch()
        let epoch = gate.bump()
        var reported: Error?
        let expected = NSError(domain: "test", code: 1)

        gate.run(epoch, { throw expected }, onError: { reported = $0 })

        XCTAssertEqual((reported as NSError?)?.code, expected.code)
    }

    func testUnboundEpochMakesQueuedCallbackANoOp() {
        let gate = ClassroomInitEpoch()
        let queued = gate.bump()
        var ran = false
        gate.bump()

        gate.run(queued, { ran = true }, onError: { _ in XCTFail("stale callback must not run") })

        XCTAssertFalse(ran)
    }

    func testQueuedCallbackAfterDestroyIsNoOp() {
        let gate = ClassroomInitEpoch()
        let queued = gate.bump()
        var ran = false
        gate.bump()

        gate.run(queued, { ran = true }, onError: { _ in XCTFail("destroyed epoch must not run") })

        XCTAssertFalse(ran)
        XCTAssertTrue(gate.isCurrent(gate.current()))
    }
}
