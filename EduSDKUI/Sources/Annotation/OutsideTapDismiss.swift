import SwiftUI
import UIKit

/// 对齐 Web `onDocPointerDown`：点在给定区域外关闭面板，不吞掉后续触摸。
///
/// - Note: `safeFramesInWindow` 实际是 SwiftUI `.global`（屏幕）坐标；命中时会把触点
///   转到同一坐标系再比较，避免 window / global 原点不一致误关面板。
struct OutsideTapDismiss: UIViewRepresentable {
    var enabled: Bool
    /// 启用后延迟多久才响应外点（避开「点工具开面板」同一击）
    var armDelay: TimeInterval = 0
    /// SwiftUI `.global` 坐标系下的安全区（工具列 + 面板等）
    var safeFramesInWindow: [CGRect]
    var onOutside: () -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.isUserInteractionEnabled = false
        view.onOutside = onOutside
        view.enabled = enabled
        view.armDelay = armDelay
        view.safeFramesInGlobal = safeFramesInWindow
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onOutside = onOutside
        uiView.armDelay = armDelay
        uiView.safeFramesInGlobal = safeFramesInWindow
        uiView.setEnabled(enabled)
    }

    final class ProbeView: UIView {
        var enabled: Bool = false
        var armDelay: TimeInterval = 0
        var safeFramesInGlobal: [CGRect] = []
        var onOutside: (() -> Void)?
        private weak var installedWindow: UIWindow?
        private var gesture: UITapGestureRecognizer?
        /// 启用后在此时间之前忽略外点
        private var armedAt: CFTimeInterval = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            syncGesture()
        }

        func setEnabled(_ next: Bool) {
            if next, !enabled {
                armedAt = CACurrentMediaTime() + max(0, armDelay)
            }
            enabled = next
            syncGesture()
        }

        func syncGesture() {
            if enabled {
                install()
            } else {
                uninstall()
            }
        }

        private func install() {
            guard let window = self.window else { return }
            if installedWindow === window, gesture != nil { return }
            uninstall()
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            gesture = tap
            installedWindow = window
        }

        private func uninstall() {
            if let g = gesture {
                installedWindow?.removeGestureRecognizer(g)
            }
            gesture = nil
            installedWindow = nil
        }

        @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
            guard enabled, let window = installedWindow ?? self.window else { return }
            if CACurrentMediaTime() < armedAt { return }

            // window 触点 → 屏幕/global，与 SwiftUI `.global` frame 对齐
            let pointInWindow = gesture.location(in: window)
            let pointGlobal = window.convert(pointInWindow, to: nil)

            let inside = safeFramesInGlobal.contains { frame in
                !frame.isNull && !frame.isEmpty && frame.insetBy(dx: -4, dy: -4).contains(pointGlobal)
            }
            if !inside {
                onOutside?()
            }
        }

        deinit {
            uninstall()
        }
    }
}

extension OutsideTapDismiss.ProbeView: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
