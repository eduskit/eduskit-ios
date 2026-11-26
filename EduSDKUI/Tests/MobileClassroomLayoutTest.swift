import XCTest
import SwiftUI
import UIKit
@testable import EduSDK
@testable import EduSDKUI

@available(iOS 16.0, *)
@MainActor
final class MobileClassroomLayoutTest: XCTestCase {
    func testPortraitAndLandscapeRenderInsideSafeBounds() async throws {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 360, height: 780), CGSize(width: 390, height: 844), CGSize(width: 430, height: 932), CGSize(width: 667, height: 375), CGSize(width: 844, height: 390), CGSize(width: 874, height: 402), CGSize(width: 780, height: 360), CGSize(width: 768, height: 1024), CGSize(width: 1024, height: 768)] {
            for dark in [false, true] {
            for drawer in size.width > size.height ? [0, 1, 2, 3, 4] : [0] {
            var snapshot = UiSnapshot()
            snapshot.initStatus = .ready
            snapshot.lifecycleStatus = .inProgress
            snapshot.badgeText = "进行中"
            snapshot.toolbarEntries = ["use_microphone": ToolbarEntry(visible: true, disabled: false), "use_camera": ToolbarEntry(visible: true, disabled: false), "raise_hand": ToolbarEntry(visible: true, disabled: false)]
            let root = MobileClassroomLayout(toolsPanel: { AnyView(EmptyView()) }, snapshot: snapshot,
                title: "移动课堂 · 长标题与横竖屏分辨率适配验证", elapsedLabel: "12:30", document: .constant(DemoData.document), members: [],
                stageParticipants: [ClassroomParticipant(id: "teacher", displayName: "主讲老师"), ClassroomParticipant(id: "student", displayName: "我的视频")],
                videoLayout: .top, videoWallOpen: false, onOpenSettings: {}, onOpenThumbnails: {}, onVideoLayout: { _ in }, onToggleVideoWall: {},
                onEnd: {}, onBack: {}, onSendMessage: { _ in false }, landscape: size.width > size.height, tab: drawer >= 3 ? drawer : 1, panelOpen: drawer != 0 && drawer != 2, videoExpanded: drawer != 2)
            let host = UIHostingController(rootView: root.ignoresSafeArea(.container).environment(\.colorScheme, dark ? .dark : .light).environment(\.dynamicTypeSize, dark ? .accessibility1 : .large))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 300_000_000)
            XCTAssertEqual(host.view.bounds.width, size.width)
            XCTAssertEqual(host.view.bounds.height, size.height)
            // Capture the hosted UIKit hierarchy, including native representables.
            // ImageRenderer substitutes unsupported-view glyphs for those hosts.
            CATransaction.flush()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor.white.setFill()
                context.fill(CGRect(origin: .zero, size: size))
                host.view.layer.render(in: context.cgContext)
            }
            let raster = try XCTUnwrap(image.cgImage?.dataProvider?.data)
            let bytes = try XCTUnwrap(CFDataGetBytePtr(raster))
            let colors = Set(stride(from: 0, to: CFDataGetLength(raster) - 3, by: 64).map { offset in
                UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2])
            })
            XCTAssertGreaterThan(colors.count, 8, "A blank capture is not visual evidence: \(size), state \(drawer)")
            let attachment = XCTAttachment(image: image)
            attachment.name = "mobile-\(dark ? "dark-large" : "light")-\(Int(size.width))x\(Int(size.height))-drawer-\(drawer)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true
            window.rootViewController = nil
            }
            }
        }
    }
    func testEmbeddedClassroomControlsAppearance() async throws {
        for size in [CGSize(width: 780, height: 360), CGSize(width: 844, height: 390)] {
            var snapshot = UiSnapshot()
            snapshot.initStatus = .ready
            snapshot.lifecycleStatus = .inProgress
            snapshot.toolbarEntries = ["use_microphone": ToolbarEntry(visible: true, disabled: false), "use_camera": ToolbarEntry(visible: true, disabled: false), "raise_hand": ToolbarEntry(visible: true, disabled: false)]
            let dock = MobileClassroomDock(snapshot: snapshot, embedded: true,
                onMic: {}, onCamera: {}, onHand: {}, onShare: {}, onCourseware: {}, onDevices: {}, onStart: {}, onEnd: {}, onWall: {}, onAnnotate: {}, onSettings: {})
            let root = ZStack(alignment: .bottom) { EduColors.surfaceLow; dock }.ignoresSafeArea(.container)
            let host = UIHostingController(rootView: root)
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in host.view.layer.render(in: ctx.cgContext) }
            let attachment = XCTAttachment(image: image)
            attachment.name = "landscape-actions-\(Int(size.width))x\(Int(size.height))"; attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
    }

}
