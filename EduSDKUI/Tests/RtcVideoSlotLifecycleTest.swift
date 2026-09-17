import XCTest
import UIKit
@testable import EduSDK
@testable import EduSDKUI

@MainActor
final class RtcVideoSlotLifecycleTest: XCTestCase {
    func testBindBeforeInitializationIsRetainedForRtcConnection() {
        let sdk = EduSdk.create(options: EduSdkCreateOptions(
            appId: "test-app",
            backendUrl: "https://example.invalid"
        ))
        let hostedView = UIView()

        sdk.bindUserVideo(userId: "remote-user", view: hostedView)

        XCTAssertTrue(sdk.videoViews["remote-user"]?.last?.value === hostedView)
    }

    func testDismantleUnbindsTheExactHostedView() {
        let hostedView = RtcVideoHostView()
        var unboundUserId: String?
        weak var unboundView: UIView?
        let coordinator = RtcVideoSlotView.Coordinator(userId: "remote-user")
        coordinator.binder = ClassroomVideoBinder(
            bindUserVideo: { _, _ in },
            unbindUserVideo: { userId, view in
                unboundUserId = userId
                unboundView = view
            }
        )

        RtcVideoSlotView.dismantleUIView(hostedView, coordinator: coordinator)

        XCTAssertEqual(unboundUserId, "remote-user")
        XCTAssertTrue(unboundView === hostedView)
    }

    func testHostViewPinsVendorSubviewsToBounds() {
        let host = RtcVideoHostView(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        let child = UIView(frame: .zero)
        host.addSubview(child)
        host.layoutIfNeeded()

        XCTAssertEqual(child.frame, host.bounds)

        host.bounds = CGRect(x: 0, y: 0, width: 220, height: 124)
        host.layoutIfNeeded()
        XCTAssertEqual(child.frame, host.bounds)
    }

    func testSidebarStripUnbindsWhenCollapsed() {
        XCTAssertFalse(MeetingSidebarView.bindsStripVideo(collapsed: true))
        XCTAssertTrue(MeetingSidebarView.bindsStripVideo(collapsed: false))
    }
}
