import XCTest
import SwiftUI
import UIKit
@testable import EduSDKUI

private struct DevicePreviewBounds: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

@MainActor
final class DeviceCheckPanelLayoutTest: XCTestCase {
    func testPreviewIsBoundedInShortLandscapeWithScrollableDevices() async throws {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844),
                     CGSize(width: 667, height: 375), CGSize(width: 844, height: 390),
                     CGSize(width: 874, height: 402), CGSize(width: 667, height: 240)] {
            var preview = CGRect.zero
            let panel = DeviceCheckPanelLayout(onClose: {}, onConfirm: {}, preview: {
                Color.black.background(GeometryReader { geo in
                    Color.clear.preference(key: DevicePreviewBounds.self, value: geo.frame(in: .global))
                })
            }, controls: {
                VStack(alignment: .leading) {
                    ForEach(0..<12) { index in
                        Text("设备 \(index + 1) · 长设备名称测试").frame(minHeight: 44)
                    }
                }
            }).onPreferenceChange(DevicePreviewBounds.self) { preview = $0 }
            let host = UIHostingController(rootView: panel.ignoresSafeArea(.container)
                .environment(\.dynamicTypeSize, .accessibility1))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host; window.makeKeyAndVisible()
            host.view.frame = window.bounds; host.view.layoutIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertGreaterThan(preview.width, 0)
            XCTAssertEqual(preview.width / preview.height, 16 / 9, accuracy: 0.01)
            XCTAssertLessThanOrEqual(preview.width, size.width)
            if size.width > size.height { XCTAssertLessThan(preview.height, size.height * 0.6) }
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                host.view.layer.render(in: context.cgContext)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "devices-large-\(Int(size.width))x\(Int(size.height))"
            attachment.lifetime = .keepAlways; add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
    }
}
