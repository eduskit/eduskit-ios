import XCTest
import EduSDK

/// Real SDK/Core/storage/publication path, without joining a classroom.
final class ContinuationSdkIntegrationTest: XCTestCase {
    @MainActor
    func testFailedConfigurationRetiresSdkAndRejectsJoining() async {
        let sdk = EduSdk.create(options: .init(appId: "continuation-native-test", backendUrl: "http://127.0.0.1:9",
            continuation: { throw NSError(domain: "configuration-unavailable", code: 1) }))
        let checked = expectation(description: "configuration failure prevents joining")
        DispatchQueue.global(qos: .userInitiated).async {
            defer { checked.fulfill() }
            do { try sdk.initialize(); XCTFail("initialization must fail") } catch { }
            do {
                try sdk.enterClassroom(params: .init(classroomId: "must-not-join", userId: "test", displayName: "test"))
                XCTFail("failed configuration must reject joining")
            } catch { }
        }
        await fulfillment(of: [checked], timeout: 15)
        let destroyed = expectation(description: "failed SDK teardown settled")
        sdk.destroy { destroyed.fulfill() }
        await fulfillment(of: [destroyed], timeout: 20)
    }

    @MainActor
    func testIncompleteFactoryConfigurationIsRejectedByNativeCore() async {
        let sdk = EduSdk.create(options: .init(appId: "continuation-native-test", backendUrl: "http://127.0.0.1:9",
            continuation: { "{\"type\":\"configure\"}" }))
        let checked = expectation(description: "Core rejects incomplete factory configuration")
        DispatchQueue.global(qos: .userInitiated).async {
            defer { checked.fulfill() }
            do { try sdk.initialize(); XCTFail("initialization must fail") } catch { }
            do {
                try sdk.enterClassroom(params: .init(classroomId: "must-not-join", userId: "test", displayName: "test"))
                XCTFail("failed configuration must reject joining")
            } catch { }
        }
        await fulfillment(of: [checked], timeout: 15)
        let destroyed = expectation(description: "invalid configuration teardown settled")
        sdk.destroy { destroyed.fulfill() }
        await fulfillment(of: [destroyed], timeout: 20)
    }

    @MainActor
    func testConfigurationPublishesPreferencesBeforeJoining() async {
        var reportEnvironment: ContinuationEnvironmentReport!
        let subscriptionClosed = expectation(description: "environment subscription closed")
        let sdk = EduSdk.create(options: .init(appId:"continuation-native-test", backendUrl:"http://127.0.0.1:9", continuation: {
                XCTAssertFalse(Thread.isMainThread)
                let capabilities = Dictionary(uniqueKeysWithValues: ["manual_window", "automatic_window",
                    "background_audio", "background_microphone", "background_camera", "background_screen_share",
                    "whiteboard_window"].map { ($0,"unavailable") })
                let environment: [String:Any] = ["app_foreground":true,"classroom_visible":true,
                    "window_minimized":false,"lock_state":"unlocked"]
                let input: [String:Any] = ["type":"configure","platform":"mobile",
                    "scope":["application":"native-test","tenant":UUID().uuidString,"account":"no-room","device":"simulator"],
                    "host_defaults":NSNull(),"host":["window":true,"background_audio":true,"background_microphone":true],
                    "capabilities":capabilities,"environment":environment]
                let json = try JSONSerialization.data(withJSONObject:input)
                return String(decoding:json,as:UTF8.self)
        }, continuationEnvironment: { report in
            reportEnvironment = report
            return { subscriptionClosed.fulfill() }
        }))
        let ready = expectation(description:"Core preferences ready before join")
        let configured = expectation(description:"worker configuration completed")
        var received = false
        let off = sdk.onClassroomContinuationChanged { view in
            guard !received, let view, view.settings?.storage == "ready" else { return }
            received = true
            XCTAssertEqual(view.settings?.settings.media.autoWindow, true)
            XCTAssertEqual(view.settings?.settings.media.backgroundAudio, true)
            XCTAssertEqual(view.settings?.settings.media.backgroundMicrophone, false)
            XCTAssertEqual(view.windowState, "closed")
            ready.fulfill()
        }
        DispatchQueue.global(qos:.userInitiated).async {
            defer { configured.fulfill() }
            do {
                try sdk.initialize()
            } catch { XCTFail("Native continuation configuration failed: \(error)") }
        }
        await fulfillment(of:[configured,ready],timeout:15)
        XCTAssertEqual(sdk.getClassroomContinuationView()?.settings?.storage,"ready")
        let updated = expectation(description: "environment delivered through subscription")
        reportEnvironment(#"{"type":"environment","environment":{"app_foreground":false,"classroom_visible":false,"window_minimized":false,"lock_state":"unlocked"},"capabilities":{"manual_window":"unavailable","automatic_window":"unavailable","background_audio":"unavailable","background_microphone":"unavailable","background_camera":"unavailable","background_screen_share":"unavailable","whiteboard_window":"unavailable"}}"#) { result in
            XCTAssertFalse(Thread.isMainThread)
            if case .failure(let error) = result { XCTFail("environment input failed: \(error)") }
            updated.fulfill()
        }
        await fulfillment(of: [updated], timeout: 5)
        off()
        let destroyed = expectation(description:"SDK native teardown settled")
        sdk.destroy { destroyed.fulfill() }
        await fulfillment(of:[destroyed, subscriptionClosed],timeout:20)
        let late = expectation(description: "retired environment report rejected")
        reportEnvironment("{}") { result in
            if case .success = result { XCTFail("retired subscription accepted input") }
            late.fulfill()
        }
        await fulfillment(of: [late], timeout: 5)
    }
}
