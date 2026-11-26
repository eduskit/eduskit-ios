import XCTest
import UIKit
import EduSDK
@testable import EduSDKUI

final class ClassroomContinuationBindingTest: XCTestCase {
    @MainActor
    func testOfficialBindingConfiguresNativeCoreAndReportsHiddenPresentation() async {
        let options = EduClassroomOptions(appId: "binding-test", backendUrl: "http://127.0.0.1:9", classroomId: "no-room",
            userId: "account", displayName: "Test", continuation: EduContinuationOptions(tenantId: UUID().uuidString,
                deviceId: "device", defaults: EduContinuationDefaults(autoWindow: false, backgroundAudio: false)))
        let binding = ClassroomContinuationBinding(options: options) { XCTFail("environment failed: \($0)") }
        let first = expectation(description: "first environment delivered")
        let hidden = expectation(description: "hidden presentation delivered")
        var reports = 0 // subscription worker
        let sdk = EduSdk.create(options: .init(appId: options.appId, backendUrl: options.backendUrl,
            continuation: { try binding.configure() }, continuationEnvironment: { report in
                try binding.subscribe { json, completion in
                    XCTAssertFalse(Thread.isMainThread)
                    do {
                        let value = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
                        let capabilities = value["capabilities"] as! [String: String]
                        XCTAssertEqual(capabilities["whiteboard_window"], capabilities["automatic_window"])
                        XCTAssertEqual(capabilities["background_camera"], "unavailable")
                        XCTAssertEqual(capabilities["background_screen_share"], "unavailable")
                        XCTAssertEqual((value["environment"] as! [String: Any])["classroom_visible"] as? Bool, false)
                    } catch { XCTFail("invalid environment: \(error)") }
                    reports += 1
                    if reports == 1 { first.fulfill() }
                    if reports == 2 { hidden.fulfill() }
                    report(json, completion)
                }
            }))
        let ready = expectation(description: "custom preferences loaded by Core")
        var received = false
        let off = sdk.onClassroomContinuationChanged { view in
            guard !received, view?.settings?.storage == "ready" else { return }
            received = true
            XCTAssertEqual(view?.settings?.settings.media.autoWindow, false)
            XCTAssertEqual(view?.settings?.settings.media.backgroundAudio, false)
            ready.fulfill()
        }
        let initialized = expectation(description: "initialized")
        DispatchQueue.global().async {
            defer { initialized.fulfill() }
            do { try sdk.initialize() } catch { XCTFail("configuration failed: \(error)") }
        }
        await fulfillment(of: [initialized, ready, first], timeout: 15)
        binding.presentation(visible: false, scene: nil)
        await fulfillment(of: [hidden], timeout: 5)
        off()
        let destroyed = expectation(description: "SDK shutdown")
        sdk.destroy { destroyed.fulfill() }
        binding.close()
        await fulfillment(of: [destroyed], timeout: 20)
    }

    @MainActor
    func testOldCleanupCannotDetachReplacementSubscription() async {
        let options = EduClassroomOptions(appId: "binding-test", backendUrl: "http://127.0.0.1:9", classroomId: "no-room",
            userId: "account", displayName: "Test", continuation: EduContinuationOptions(tenantId: "tenant", deviceId: "device"))
        let binding = ClassroomContinuationBinding(options: options) { XCTFail("\($0)") }
        let subscribed = expectation(description: "replacement registered")
        let update = expectation(description: "replacement still receives updates")
        var reports = 0
        DispatchQueue.global().async {
            defer { subscribed.fulfill() }
            do {
                let old = try binding.subscribe { _, done in done(.success(())) }
                _ = try binding.subscribe { _, done in
                    reports += 1
                    if reports == 2 { update.fulfill() }
                    done(.success(()))
                }
                old()
            } catch { XCTFail("\(error)") }
        }
        await fulfillment(of: [subscribed], timeout: 5)
        binding.presentation(visible: false, scene: nil)
        await fulfillment(of: [update], timeout: 5)
        binding.close()
    }
}
