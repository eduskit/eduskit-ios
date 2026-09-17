import SwiftUI
import UIKit

struct ClassroomVideoBinder {
    let bindUserVideo: (String, UIView) -> Void
    let unbindUserVideo: (String, UIView) -> Void
}

private struct ClassroomVideoBinderKey: EnvironmentKey {
    static let defaultValue: ClassroomVideoBinder? = nil
}

extension EnvironmentValues {
    var classroomVideoBinder: ClassroomVideoBinder? {
        get { self[ClassroomVideoBinderKey.self] }
        set { self[ClassroomVideoBinderKey.self] = newValue }
    }
}

struct RtcVideoSlotView: UIViewRepresentable {
    let userId: String
    var cornerRadius: CGFloat = EduDimens.radiusXl
    @Environment(\.classroomVideoBinder) private var binder

    func makeCoordinator() -> Coordinator {
        Coordinator(userId: userId)
    }

    func makeUIView(context: Context) -> RtcVideoHostView {
        let view = RtcVideoHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.applyCornerRadius(cornerRadius)
        context.coordinator.binder = binder
        view.onReady = { [weak coordinator = context.coordinator] readyView in
            guard let coordinator else { return }
            coordinator.binder?.bindUserVideo(coordinator.userId, readyView)
        }
        return view
    }

    func updateUIView(_ uiView: RtcVideoHostView, context: Context) {
        if context.coordinator.userId != userId {
            context.coordinator.binder?.unbindUserVideo(context.coordinator.userId, uiView)
        }
        context.coordinator.userId = userId
        context.coordinator.binder = binder
        uiView.applyCornerRadius(cornerRadius)
        uiView.onReady = { [weak coordinator = context.coordinator] readyView in
            guard let coordinator else { return }
            coordinator.binder?.bindUserVideo(coordinator.userId, readyView)
        }
        binder?.bindUserVideo(userId, uiView)
    }

    static func dismantleUIView(_ uiView: RtcVideoHostView, coordinator: Coordinator) {
        coordinator.binder?.unbindUserVideo(coordinator.userId, uiView)
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: RtcVideoHostView, context: Context) -> CGSize {
        let fallback = uiView.bounds.size
        let defaultSize = (fallback.width > 0 && fallback.height > 0)
            ? fallback
            : CGSize(width: 1, height: 1)
        return proposal.replacingUnspecifiedDimensions(by: defaultSize)
    }

    final class Coordinator {
        var userId: String
        var binder: ClassroomVideoBinder?

        init(userId: String) {
            self.userId = userId
        }
    }
}

/// TRTC 往 host 注入的渲染层必须跟着 SwiftUI 槽位一起铺满。
/// 圆角在 UIKit 裁，禁止祖先再用 `.clipShape` / `.shadow` 离屏合成，否则 Metal 画面会被拍成空白。
final class RtcVideoHostView: UIView {
    var onReady: ((UIView) -> Void)?
    private var lastReadySize = CGSize.zero
    private var cornerRadius: CGFloat = 0

    func applyCornerRadius(_ radius: CGFloat) {
        if cornerRadius != radius {
            cornerRadius = radius
            layer.cornerRadius = radius
            layer.cornerCurve = .continuous
        }
        clipsToBounds = true
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        notifyReadyIfPossible(force: true)
    }

    override func didAddSubview(_ subview: UIView) {
        super.didAddSubview(subview)
        pinSubview(subview)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        for subview in subviews {
            pinSubview(subview)
        }
        notifyReadyIfPossible(force: bounds.size != lastReadySize)
    }

    private func pinSubview(_ subview: UIView) {
        subview.frame = bounds
        subview.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    }

    private func notifyReadyIfPossible(force: Bool) {
        guard force, window != nil, bounds.width > 0, bounds.height > 0 else { return }
        lastReadySize = bounds.size
        onReady?(self)
    }
}
