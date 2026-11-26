import XCTest
import SwiftUI
import UIKit
@testable import EduSDKUI

private struct PanelBoundsPreference: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
private extension View {
    func recordPanelBounds(_ name: String) -> some View {
        background(GeometryReader { geo in
            Color.clear.preference(key: PanelBoundsPreference.self, value: [name: geo.frame(in: .named("panel-test"))])
        })
    }
}

@MainActor
final class CoursewarePanelLayoutTest: XCTestCase {
    func testManyPagesScrollWithoutCoveringDismissAndJumpActions() async throws {
        for size in [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844), CGSize(width: 844, height: 390), CGSize(width: 780, height: 360), CGSize(width: 390, height: 300)] {
            for pageCount in [1, 120] {
                var bounds: [String: CGRect] = [:]
                let root = CoursewarePanelViewport(preferredHeight: CGFloat(pageCount) * 84 + 160, alignBottom: true) {
                    VStack(spacing: 12) {
                        HStack { Text("课件缩略图"); Spacer(); Button("关闭") {}.frame(width: 44, height: 44) }.recordPanelBounds("header")
                        ScrollView {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3)) {
                                ForEach(0..<pageCount, id: \.self) { index in
                                    Text("\(index + 1)").frame(maxWidth: .infinity).frame(height: 72).background(Color.blue.opacity(0.08))
                                }
                            }
                        }.frame(maxHeight: .infinity).clipped().recordPanelBounds("grid")
                        HStack { Text("跳转到页码"); Spacer(); Button("跳转") {} }.frame(height: 44).recordPanelBounds("footer")
                    }.padding(20).recordPanelBounds("panel")
                }.coordinateSpace(name: "panel-test").onPreferenceChange(PanelBoundsPreference.self) { bounds = $0 }
                let host = UIHostingController(rootView: root.ignoresSafeArea(.container))
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
                host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 150_000_000)
                let panel = try XCTUnwrap(bounds["panel"])
                let header = try XCTUnwrap(bounds["header"])
                let footer = try XCTUnwrap(bounds["footer"])
                let grid = try XCTUnwrap(bounds["grid"])
                XCTAssertGreaterThan(panel.minY, 0, "The classroom must remain visible behind the panel")
                XCTAssertLessThanOrEqual(panel.height, size.height * 0.82 + 1)
                XCTAssertLessThanOrEqual(panel.maxY, size.height - 11)
                XCTAssertGreaterThanOrEqual(panel.minX, 11)
                XCTAssertGreaterThanOrEqual(header.height, 44)
                XCTAssertGreaterThanOrEqual(footer.height, 44)
                XCTAssertLessThanOrEqual(header.maxY, grid.minY)
                XCTAssertLessThanOrEqual(grid.maxY, footer.minY)
                XCTAssertLessThanOrEqual(footer.maxY, panel.maxY)
                let image = UIGraphicsImageRenderer(size: size).image { context in host.view.layer.render(in: context.cgContext) }
                let attachment = XCTAttachment(image: image)
                attachment.name = "courseware-\(pageCount)-\(Int(size.width))x\(Int(size.height))"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }
}
