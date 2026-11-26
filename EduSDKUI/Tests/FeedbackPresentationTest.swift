import XCTest
import SwiftUI
import UIKit
@testable import EduSDK
@testable import EduSDKUI

@MainActor
final class FeedbackPresentationTest: XCTestCase {
    func testFeedbackAtPortraitLandscapeAndSmallViewportSizes() async throws {
        let sizes = [CGSize(width: 320, height: 568), CGSize(width: 390, height: 844), CGSize(width: 844, height: 390), CGSize(width: 667, height: 320)]
        for size in sizes {
            for longContent in [false, true] {
                let request = longContent
                    ? FeedbackRequest.create(mode: .dialog, tone: .error,
                        message: String(repeating: "请检查网络连接后重试。", count: 80), autoDismissMs: nil, modal: true,
                        actions: [FeedbackAction(id: "cancel", label: "取消", style: .text), FeedbackAction(id: "retry", label: "重试", style: .primary)])
                    : feedbackFromMediaOpenHint(audience: .teacher)
                let item = try await prepareFeedback(request)
                let host = UIHostingController(rootView: ZStack {
                    Color(red: 0.94, green: 0.96, blue: 0.98)
                    Text("课堂内容保持清晰").foregroundColor(.gray)
                    FeedbackHost(feedback: item, onShown: { _ in }, onDismiss: { _, _ in }, onAction: { _, _ in })
                }.ignoresSafeArea())
                let window = UIWindow(frame: CGRect(origin: .zero, size: size))
                window.rootViewController = host; window.makeKeyAndVisible()
                host.view.frame = window.bounds; host.view.layoutIfNeeded()
                try await Task.sleep(nanoseconds: 300_000_000)
                CATransaction.flush()
                let format = UIGraphicsImageRendererFormat(); format.scale = 1
                let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                    host.view.layer.render(in: context.cgContext)
                }
                XCTAssertGreaterThan(image.pngData()?.count ?? 0, 5000)
                let attachment = XCTAttachment(image: image)
                attachment.name = "feedback-\(longContent ? "long-dialog" : "notification")-\(Int(size.width))x\(Int(size.height))"
                attachment.lifetime = .keepAlways; add(attachment)
                window.isHidden = true; window.rootViewController = nil
            }
        }
    }
}
