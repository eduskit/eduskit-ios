import XCTest
import EduSDKUniffi

/// Exercise the rebuilt native Core through the same UniFFI boundary used by iOS.
/// No network, vendor player or classroom session is started by this fixture.
final class LiveLicenceCoreIntegrationTest: XCTestCase {
    func testCachedFailureThenSuccessDoesNotEmitAnInitializationError() throws {
        let client = EdusdkClient()
        try client.`init`(config: InitConfig(appId: "license-test", backendBaseUrl: "",
            rtcProvider: "mock", imProvider: "mock", liveProvider: "mock", whiteboardProvider: "mock"))
        defer { try? client.shutdown() }
        _ = try client.pollRuntimeUpdate(forceSnapshot: false).events
        try client.applyProviderEvent(domain: "live", payloadJson:
            #"{"type":"play_failed","stream_name":"teacher-main","message":"edusdk.live_licence:loading:0:"}"#)
        XCTAssertFalse(try client.pollRuntimeUpdate(forceSnapshot: false).events.contains { $0.kind == .error })
        try client.applyProviderEvent(domain: "live", payloadJson:
            #"{"type":"licence_loaded","loaded":false,"state":"failed","code":-11,"message":"license expired."}"#)
        XCTAssertFalse(try client.pollRuntimeUpdate(forceSnapshot: false).events.contains { $0.kind == .error })
        try client.applyProviderEvent(domain: "live", payloadJson:
            #"{"type":"licence_loaded","loaded":true,"state":"loaded","code":0,"message":""}"#)
        XCTAssertFalse(try client.pollRuntimeUpdate(forceSnapshot: false).events.contains { $0.kind == .error })

        let policy = try JSONSerialization.jsonObject(with: Data(client.interactionPolicyJson().utf8)) as! [[String: Any]]
        XCTAssertEqual(policy.first { $0["action"] as? String == "start_class" }?["visible"] as? Bool, false)

        try client.applyProviderEvent(domain: "live", payloadJson:
            #"{"type":"play_failed","stream_name":"teacher-main","message":"edusdk.live_licence:failed:-11:license expired."}"#)
        let errors = try client.pollRuntimeUpdate(forceSnapshot: false).events.compactMap(\.error)
        XCTAssertEqual(errors.count, 1)
        XCTAssertTrue(errors.first?.message.contains("license has expired") == true)
    }
}
