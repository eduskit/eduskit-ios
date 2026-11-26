import Foundation
import UIKit
import AVKit
import EduSDK

/// System PiP for one live content view. Closing the controller does not end the SDK session.
@available(iOS 15.0, *)
final class IosContinuationWindowPort: NSObject, ContinuationWindowPort, AVPictureInPictureControllerDelegate {
    private let sourceView: () -> UIView?
    private let attachContent: (String, UIView) -> Bool
    private let onPresentationRejected: () -> Void
    private let onContentReleased: () -> Void
    private let content = ContinuationContentController()
    private var controller: AVPictureInPictureController?
    private var owner: Owner?
    private var destroyed = false

    private struct Owner {
        let id: String
        let report: (String) -> Void
        var entered = false
    }

    init(sourceView: @escaping () -> UIView?, attachContent: @escaping (String, UIView) -> Bool, onPresentationRejected: @escaping () -> Void = {}, onContentReleased: @escaping () -> Void = {}) {
        self.sourceView = sourceView
        self.attachContent = attachContent
        self.onPresentationRejected = onPresentationRejected
        self.onContentReleased = onContentReleased
    }

    func dispatch(requestJson: String, report: @escaping (String) -> Void) throws {
        let request = try JSONSerialization.jsonObject(with: Data(requestJson.utf8)) as? [String: Any]
        guard let id = request?["id"] as? String, !id.isEmpty,
              let operation = request?["operation"] as? String, operation == "enter" || operation == "exit",
              let content = request?["content"] as? String else {
            throw NSError(domain: "EduSDK.ContinuationWindow", code: 1)
        }
        DispatchQueue.main.async { [weak self] in
            guard let self else { report(Self.event("failed", id)); return }
            self.dispatchOnMain(id: id, operation: operation, content: content, report: report)
        }
    }

    func hasOwner() -> Bool { owner != nil }

    func presentationDestroyed() {
        precondition(Thread.isMainThread)
        destroyed = true
        let current = owner
        owner = nil
        controller?.stopPictureInPicture()
        content.clear()
        onContentReleased()
        current.map { $0.report(Self.event("closed", $0.id, "unknown")) }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        guard var current = owner, !current.entered else { return }
        current.entered = true
        owner = current
        current.report(Self.event("entered", current.id))
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        let current = owner
        owner = nil
        content.clear()
        onContentReleased()
        onPresentationRejected()
        current?.report(Self.event("failed", current?.id ?? ""))
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        let current = owner
        owner = nil
        content.clear()
        onContentReleased()
        current?.report(Self.event("closed", current?.id ?? "", "unknown"))
    }

    private func dispatchOnMain(id: String, operation: String, content: String, report: @escaping (String) -> Void) {
        if destroyed || !AVPictureInPictureController.isPictureInPictureSupported() {
            report(Self.event("failed", id)); return
        }
        if operation == "exit" {
            guard let current = owner, current.id == id else {
                report(Self.event("closed", id, "system")); return
            }
            controller?.stopPictureInPicture()
            return
        }
        if let current = owner {
            if current.id == id && current.entered { report(Self.event("entered", id)) }
            else if current.id != id { report(Self.event("failed", id)) }
            return
        }
        guard self.content.show(content, attach: attachContent), let view = sourceView(), view.window != nil else {
            self.content.clear()
            onContentReleased()
            report(Self.event("failed", id)); return
        }
        let source = AVPictureInPictureController.ContentSource(activeVideoCallSourceView: view, contentViewController: self.content)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        self.controller = controller
        if controller.isPictureInPictureActive {
            owner = Owner(id: id, report: report, entered: true)
            report(Self.event("entered", id))
            return
        }
        owner = Owner(id: id, report: report)
        controller.startPictureInPicture()
    }

    private static func event(_ type: String, _ id: String, _ reason: String? = nil) -> String {
        var payload: [String: Any] = ["type": type, "id": id]
        if let reason { payload["reason"] = reason }
        let data = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

@available(iOS 15.0, *)
private final class ContinuationContentController: AVPictureInPictureVideoCallViewController {
    func show(_ content: String, attach: (String, UIView) -> Bool) -> Bool {
        loadViewIfNeeded()
        view.subviews.forEach { $0.removeFromSuperview() }
        return attach(content, view)
    }

    func clear() {
        loadViewIfNeeded()
        view.subviews.forEach { $0.removeFromSuperview() }
    }
}
