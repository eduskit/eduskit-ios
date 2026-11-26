import XCTest
@testable import EduSDK
@testable import EduSDKUI

final class LiveStreamsTest: XCTestCase {
    private func stream(
        _ streamName: String,
        publisherUserId: String,
        streamType: String,
        muted: Bool = true
    ) -> LiveStream {
        LiveStream(
            streamName: streamName,
            publisherUserId: publisherUserId,
            streamType: streamType,
            url: "webrtc://play.example.com/live/\(streamName)",
            muted: muted,
            expiresAt: "2026-10-18T12:00:00Z",
            playing: false
        )
    }

    private func snapshot(needLive: Bool) -> UiSnapshot {
        var snapshot = UiSnapshot()
        snapshot.needLive = needLive
        snapshot.liveStreams = [
            stream("cls_1__eu_1__e3", publisherUserId: "eu_1", streamType: "main"),
            stream("cls_1__eu_1_aux__e3", publisherUserId: "eu_1", streamType: "aux"),
            stream("cls_1__audio__e3", publisherUserId: "", streamType: "audio", muted: false),
        ]
        return snapshot
    }

    func testOnlyCameraMainStreamsClaimAParticipantTile() {
        XCTAssertEqual(LiveStreams.byUser(snapshot(needLive: true)), ["eu_1": "cls_1__eu_1__e3"])
    }

    func testScreenShareAuxIsAddressedSeparatelyFromTheMainStream() {
        let snapshot = snapshot(needLive: true)
        XCTAssertEqual(LiveStreams.auxStreamName(snapshot, userId: "eu_1"), "cls_1__eu_1_aux__e3")
        XCTAssertNil(LiveStreams.auxStreamName(snapshot, userId: "eu_2"))
    }

    func testAudioMixHasNoPublisherAndIsFoundByType() {
        let snapshot = snapshot(needLive: true)
        XCTAssertEqual(LiveStreams.audioStreamName(snapshot), "cls_1__audio__e3")
        XCTAssertEqual(LiveStreams.stream(snapshot, streamName: "cls_1__audio__e3")?.muted, false)
    }

    func testAnOnStageMemberNeverTakesOverTheRtcTile() {
        let snapshot = snapshot(needLive: false)
        XCTAssertTrue(LiveStreams.byUser(snapshot).isEmpty)
        XCTAssertNil(LiveStreams.audioStreamName(snapshot))
        XCTAssertNil(LiveStreams.auxStreamName(snapshot, userId: "eu_1"))
    }
}
