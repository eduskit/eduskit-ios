import Foundation

enum WhiteboardWriteDecision: Equatable {
    case allowed
    /// `feedbackReason` 为 nil 表示静默拒绝：权限类拒绝或提示仍在冷却窗口内。
    case denied(feedbackReason: String?)
}

/// DrawsKit 写操作的授权缓存。
///
/// DrawsKit 会在自己的线程同步调用写授权闭环，因此裁决不能碰 `@MainActor` 状态，
/// 也不能触发 Core 查询：策略由 Core 事件驱动写入这里，闭环只做纯值判定。
final class WhiteboardWriteGate: @unchecked Sendable {
    /// 被拒的书写会随笔迹连续触发，提示按窗口收敛，避免刷屏和逐笔主线程投递。
    private static let restrictionCooldown: TimeInterval = 2

    private let lock = NSLock()
    private var allowed = false
    private var feedbackReason: String?
    private var lastRestrictionAt: TimeInterval = 0

    func update(allowed: Bool, feedbackReason: String?) {
        lock.lock()
        self.allowed = allowed
        self.feedbackReason = feedbackReason
        lock.unlock()
    }

    func authorize(
        now: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) -> WhiteboardWriteDecision {
        lock.lock()
        defer { lock.unlock() }
        if allowed { return .allowed }
        guard let feedbackReason else { return .denied(feedbackReason: nil) }
        guard now - lastRestrictionAt >= Self.restrictionCooldown else {
            return .denied(feedbackReason: nil)
        }
        lastRestrictionAt = now
        return .denied(feedbackReason: feedbackReason)
    }
}
