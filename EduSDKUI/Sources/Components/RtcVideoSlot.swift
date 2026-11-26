import SwiftUI
import UIKit
import EduSDK

/// 视频绑定按 `VideoSlot`（userId + streamType）键化：同一个用户可以同时有摄像头
/// 与屏幕共享两条轨道，只按 userId 绑会让共享画面覆盖掉对方的摄像头。
struct ClassroomVideoBinder {
    let bindUserVideo: (VideoSlot, UIView) -> Void
    let unbindUserVideo: (VideoSlot, UIView) -> Void
    var bindLiveStream: (String, UIView) -> Void = { _, _ in }
    var unbindLiveStream: (String, UIView) -> Void = { _, _ in }
}

private struct ClassroomVideoBinderKey: EnvironmentKey {
    static let defaultValue: ClassroomVideoBinder? = nil
}

private struct LiveUiSnapshotKey: EnvironmentKey {
    static let defaultValue: UiSnapshot? = nil
}

extension EnvironmentValues {
    var classroomVideoBinder: ClassroomVideoBinder? {
        get { self[ClassroomVideoBinderKey.self] }
        set { self[ClassroomVideoBinderKey.self] = newValue }
    }

    /// 当前课堂快照。格子据此决定绑 RTC 还是挂直播播放器。
    var liveUiSnapshot: UiSnapshot? {
        get { self[LiveUiSnapshotKey.self] }
        set { self[LiveUiSnapshotKey.self] = newValue }
    }
}

/// 台下某一路转推流的渲染槽。与 [RtcVideoSlotView] 互斥。
struct LiveVideoSlotView: UIViewRepresentable {
    let streamName: String
    var cornerRadius: CGFloat = EduDimens.radiusXl
    @Environment(\.classroomVideoBinder) private var binder

    func makeCoordinator() -> Coordinator {
        Coordinator(streamName: streamName)
    }

    func makeUIView(context: Context) -> RtcVideoHostView {
        let view = RtcVideoHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.applyCornerRadius(cornerRadius)
        context.coordinator.binder = binder
        view.onReady = { [weak coordinator = context.coordinator] readyView in
            guard let coordinator else { return }
            coordinator.binder?.bindLiveStream(coordinator.streamName, readyView)
        }
        return view
    }

    func updateUIView(_ uiView: RtcVideoHostView, context: Context) {
        if context.coordinator.streamName != streamName {
            context.coordinator.binder?.unbindLiveStream(context.coordinator.streamName, uiView)
        }
        context.coordinator.streamName = streamName
        context.coordinator.binder = binder
        uiView.applyCornerRadius(cornerRadius)
        uiView.onReady = { [weak coordinator = context.coordinator] readyView in
            guard let coordinator else { return }
            coordinator.binder?.bindLiveStream(coordinator.streamName, readyView)
        }
        binder?.bindLiveStream(streamName, uiView)
    }

    static func dismantleUIView(_ uiView: RtcVideoHostView, coordinator: Coordinator) {
        coordinator.binder?.unbindLiveStream(coordinator.streamName, uiView)
    }

    final class Coordinator {
        var streamName: String
        var binder: ClassroomVideoBinder?

        init(streamName: String) {
            self.streamName = streamName
        }
    }
}

struct RtcVideoSlotView: UIViewRepresentable {
    let userId: String
    var cornerRadius: CGFloat = EduDimens.radiusXl
    var streamType: EduStreamType = .camera
    @Environment(\.classroomVideoBinder) private var binder

    private var slot: VideoSlot { VideoSlot(userId: userId, streamType: streamType) }

    func makeCoordinator() -> Coordinator {
        Coordinator(slot: slot)
    }

    func makeUIView(context: Context) -> RtcVideoHostView {
        let view = RtcVideoHostView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.applyCornerRadius(cornerRadius)
        context.coordinator.binder = binder
        view.onReady = { [weak coordinator = context.coordinator] readyView in
            guard let coordinator else { return }
            coordinator.binder?.bindUserVideo(coordinator.slot, readyView)
        }
        return view
    }

    func updateUIView(_ uiView: RtcVideoHostView, context: Context) {
        if context.coordinator.slot != slot {
            context.coordinator.binder?.unbindUserVideo(context.coordinator.slot, uiView)
        }
        context.coordinator.slot = slot
        context.coordinator.binder = binder
        uiView.applyCornerRadius(cornerRadius)
        uiView.onReady = { [weak coordinator = context.coordinator] readyView in
            guard let coordinator else { return }
            coordinator.binder?.bindUserVideo(coordinator.slot, readyView)
        }
        binder?.bindUserVideo(slot, uiView)
    }

    static func dismantleUIView(_ uiView: RtcVideoHostView, coordinator: Coordinator) {
        coordinator.binder?.unbindUserVideo(coordinator.slot, uiView)
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
        var slot: VideoSlot
        var binder: ClassroomVideoBinder?

        init(slot: VideoSlot) {
            self.slot = slot
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
