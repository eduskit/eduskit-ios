import XCTest
import EduSDKUniffi

final class RemoteDrawingLiveCoreIntegrationTest: XCTestCase {
    func testRemoteDrawingPreservesLiveSnapshotThroughNativeBinding() throws {
        let client = EdusdkClient()
        try client.`init`(config: InitConfig(appId: "app", backendBaseUrl: "https://example.invalid",
            rtcProvider: "mock", imProvider: "mock", liveProvider: "mock", whiteboardProvider: "mock",
            userToken: "test-token", platform: "ios"))
        defer { try? client.shutdown() }
        try client.joinRoom(roomId: "class-live", userId: "student", displayName: "Student")
        let effects = try client.pollRuntimeUpdate(forceSnapshot: false).hostEffects.map {
            try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
        }
        let join = try XCTUnwrap(effects.first { ($0["action"] as? [String: Any])?["type"] as? String == "http" })
        let payload = try JSONSerialization.jsonObject(with: Data(Self.join.utf8))
        let receipt: [String: Any] = ["effect_id": join["id"]!, "outcome": ["status": "success", "payload": payload]]
        try client.completeHostEffect(resultJson: String(decoding: JSONSerialization.data(withJSONObject: receipt), as: UTF8.self))
        try client.applyProviderEvent(domain: "live", payloadJson:
            #"{"type":"play_started","stream_name":"teacher-main"}"#)
        _ = try client.pollRuntimeUpdate(forceSnapshot: false).events
        try client.applyProviderEvent(domain: "im", payloadJson: Self.drawing)
        let events = try client.pollRuntimeUpdate(forceSnapshot: false).events
        XCTAssertTrue(events.contains { $0.kind == .whiteboardSyncReceived })
        XCTAssertFalse(events.contains { $0.kind == .error })
        let snapshot = try client.backendSnapshot()
        XCTAssertTrue(snapshot.needLive)
        XCTAssertEqual(snapshot.liveStreams.count, 1)
        XCTAssertTrue(try XCTUnwrap(snapshot.liveStreams.first).playing)
        XCTAssertEqual(snapshot.liveStreams.first?.streamName, "teacher-main")
    }
    private static let join = #"{"traceId":"a1b2c3d4e5f6789012345678abcdef01","init":{"needWhiteboard":true,"needRtc":false},"session":{"appId":"app","eduUserId":"student","nickname":"Student"},"classroom":{"classroomId":"class-live","appId":"app","status":"live"},"self":{"role":"student","stageStatus":"off","permissions":[]},"onStageMembers":[{"eduUserId":"teacher","role":"teacher","stageStatus":"on"}],"im":{"token":"sig","expireAt":1893456000,"provider":"openim","userId":"student","platformId":5,"apiAddr":"https://im.example.com","wsAddr":"wss://im.example.com"},"rtc":{"sdkAppId":"1400999999","userId":"student","userSig":"sig","expireAt":1893456000,"roomId":"class-live"},"sessionControl":{"accessToken":"test","expiresAt":"2099-01-01T00:00:00Z","scope":"classroom:join-session"},"observability":{"classSessionId":"01a01a33-aa4a-7f22-8d1d-e863ed9b27f0","attemptId":"5a91bc86-efa0-8cd6-8f03-8af77960df3a","attemptNo":1,"deviceId":"56086356-76d9-4f5b-9865-a42c4a7db14e"},"telemetry":{"accessToken":"test","expiresAt":"2099-01-01T00:00:00Z","ingestUrl":"https://example.test/telemetry"},"relay":{"status":"ready","version":7,"streams":[{"streamName":"teacher-main","publisherUserId":"teacher","streamType":"main","play":{"webrtc":"","flv":"https://example.test/main.flv","hls":"","rtmp":""},"expiresAt":"2099-01-01T00:00:00Z","audioSource":null}]}}"#
    private static let drawing = #"{"v":1,"signalId":"remote-drawing","type":"whiteboard.sync","classroomId":"class-live","senderId":"teacher","data":{"payload":{"op_id":"remote-op","board_id":"board","user_id":"teacher","capture_server_ms":1234,"op":{"points":[{"x":1.5,"y":2.0}],"done":true}}}}"#
}
