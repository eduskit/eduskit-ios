import XCTest
import UIKit
import SwiftUI
@testable import EduSDK
@testable import EduSDKUI

@MainActor
private final class StagePresentation: ObservableObject {
    @Published var vertical = false
    @Published var hidden = false
}

@MainActor
private struct StageLifecycleHarness: View {
    @ObservedObject var presentation: StagePresentation
    let binder: ClassroomVideoBinder
    var liveSnapshot: UiSnapshot? = nil
    var body: some View {
        MobileStageStrip(participants: (0..<6).map {
            ClassroomParticipant(id: "participant-\($0)", displayName: "课堂成员 \($0)", onStage: true, videoMuted: false)
        }, emptySeatCount: 0, vertical: presentation.vertical, canManage: false, showLive: false, onInvite: {})
            .frame(width: presentation.vertical ? 168 : 390, height: presentation.vertical ? 320 : 106)
            .opacity(presentation.hidden ? 0 : 1)
            .environment(\.classroomVideoBinder, binder)
            .environment(\.liveUiSnapshot, liveSnapshot)
    }
}

@MainActor
final class RtcVideoSlotLifecycleTest: XCTestCase {
    func testMobileStripRetainsAllNativeHostsAcrossAxisAndVisibilityChanges() async throws {
        try await verifyMobileHosts(live: false)
    }
    func testStudentLiveStripRetainsSizedHostsAcrossAxisAndVisibilityChanges() async throws {
        try await verifyMobileHosts(live: true)
    }
    private func verifyMobileHosts(live: Bool) async throws {
        let presentation = StagePresentation()
        var hosts: [String: Set<ObjectIdentifier>] = [:]
        var views: [String: UIView] = [:]
        var unbinds = 0
        let binder = ClassroomVideoBinder(bindUserVideo: { slot, view in
            XCTAssertFalse(live, "Student live tiles must route to the live player")
            hosts[slot.userId, default: []].insert(ObjectIdentifier(view))
            views[slot.userId] = view
        }, unbindUserVideo: { _, _ in unbinds += 1 }, bindLiveStream: { name, view in
            XCTAssertTrue(live)
            hosts[name, default: []].insert(ObjectIdentifier(view)); views[name] = view
        }, unbindLiveStream: { _, _ in unbinds += 1 })
        var snapshot = UiSnapshot(); snapshot.needLive = true
        snapshot.liveStreams = (0..<6).map { index in
            LiveStream(streamName: "stream-\(index)", publisherUserId: "participant-\(index)", streamType: "main",
                url: "webrtc://example.invalid/stream-\(index)", muted: true, expiresAt: "2026-12-01T00:00:00Z", playing: true)
        }
        let controller = UIHostingController(rootView: StageLifecycleHarness(presentation: presentation, binder: binder, liveSnapshot: live ? snapshot : nil))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 844, height: 390))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(hosts.count, 6)
        for (vertical, hidden) in [(true, false), (true, true), (false, true), (false, false)] {
            presentation.vertical = vertical; presentation.hidden = hidden
            controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 100_000_000)
            XCTAssertEqual(unbinds, 0, "Presentation changes must not unbind media")
            XCTAssertTrue(hosts.values.allSatisfy { $0.count == 1 }, "Each participant keeps the same native host")
            for view in views.values {
                XCTAssertGreaterThan(view.bounds.width, 100, "Player host must have a usable render size")
                XCTAssertEqual(view.bounds.width / view.bounds.height, 16.0 / 9.0, accuracy: 0.02)
            }
        }
    }
    func testBindBeforeInitializationIsRetainedForRtcConnection() {
        let sdk = EduSdk.create(options: EduSdkCreateOptions(
            appId: "test-app",
            backendUrl: "https://example.invalid"
        ))
        let hostedView = UIView()

        sdk.bindUserVideo(userId: "remote-user", view: hostedView)

        XCTAssertTrue(sdk.videoViews[VideoSlot(userId: "remote-user", streamType: .camera).key]?.last?.value === hostedView)
    }

    func testDismantleUnbindsTheExactHostedView() {
        let hostedView = RtcVideoHostView()
        var unboundSlot: VideoSlot?
        weak var unboundView: UIView?
        let slot = VideoSlot(userId: "remote-user", streamType: .camera)
        let coordinator = RtcVideoSlotView.Coordinator(slot: slot)
        coordinator.binder = ClassroomVideoBinder(
            bindUserVideo: { _, _ in },
            unbindUserVideo: { slot, view in
                unboundSlot = slot
                unboundView = view
            }
        )

        RtcVideoSlotView.dismantleUIView(hostedView, coordinator: coordinator)

        XCTAssertEqual(unboundSlot, slot)
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

    func testCameraOffHidesRtcSurfaceButKeepsMainLiveHost() {
        XCTAssertFalse(showsParticipantCameraSurface(videoMuted: true))
        XCTAssertTrue(showsParticipantCameraSurface(videoMuted: false))
        XCTAssertTrue(showsParticipantLiveSurface(liveStreamName: "main"))
        XCTAssertFalse(showsParticipantLiveSurface(liveStreamName: nil))
        XCTAssertFalse(showsParticipantLiveSurface(liveStreamName: ""))
    }

    func testCameraOffKeepsMainLiveHostAndProgrammeAudioAndScreenShare() async throws {
        let muted = try await mountedCameraHosts(videoMuted: true)
        XCTAssertTrue(muted.live.contains("main"))
        XCTAssertTrue(muted.rtc.isEmpty)
        XCTAssertTrue(muted.live.contains("audio"))
        XCTAssertTrue(muted.live.contains("aux"))

        let open = try await mountedCameraHosts(videoMuted: false)
        XCTAssertTrue(open.live.contains("main"))
        XCTAssertTrue(open.live.contains("audio"))
        XCTAssertTrue(open.live.contains("aux"))
        XCTAssertTrue(open.rtc.isEmpty)
    }

    private func mountedCameraHosts(videoMuted: Bool) async throws -> (live: Set<String>, rtc: Set<String>) {
        final class HostLog {
            var live = Set<String>()
            var rtc = Set<String>()
        }
        let log = HostLog()
        let binder = ClassroomVideoBinder(
            bindUserVideo: { slot, _ in log.rtc.insert(slot.key) },
            unbindUserVideo: { _, _ in },
            bindLiveStream: { name, _ in log.live.insert(name) },
            unbindLiveStream: { _, _ in }
        )
        var snapshot = UiSnapshot()
        snapshot.needLive = true
        snapshot.liveStreams = ["main", "audio", "aux"].map { name in
            LiveStream(
                streamName: name,
                publisherUserId: name == "audio" ? "" : "teacher",
                streamType: name,
                url: "webrtc://example.invalid/\(name)",
                muted: name != "audio",
                expiresAt: "2026-12-01T00:00:00Z",
                playing: true
            )
        }
        let root = CameraSurfaceHarness(videoMuted: videoMuted, binder: binder, snapshot: snapshot)
        let controller = UIHostingController(rootView: root)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 640))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 150_000_000)
        return (log.live, log.rtc)
    }
}

@MainActor
private struct CameraSurfaceHarness: View {
    let videoMuted: Bool
    let binder: ClassroomVideoBinder
    let snapshot: UiSnapshot

    private var teacher: ClassroomParticipant {
        ClassroomParticipant(id: "teacher", displayName: "Teacher", onStage: true, videoMuted: videoMuted)
    }

    var body: some View {
        VStack {
            MainVideoStageView(teacher: teacher, showLiveBadge: true)
                .frame(width: 320, height: 180)
            ScreenShareStageView(userId: teacher.id, displayName: teacher.displayName)
                .frame(width: 320, height: 180)
            ParticipantVideoTile(participant: teacher, bindVideo: true)
        }
        .environment(\.classroomVideoBinder, binder)
        .environment(\.liveUiSnapshot, snapshot)
    }
}
