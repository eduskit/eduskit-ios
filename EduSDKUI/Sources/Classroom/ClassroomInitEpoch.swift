import Foundation

/// 取消过期的后台进课 / 回调（retry、leave、destroy）。
final class ClassroomInitEpoch: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    @discardableResult
    func bump() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    func current() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func isCurrent(_ epoch: UInt64) -> Bool {
        current() == epoch
    }

    func run(_ epoch: UInt64, _ body: () throws -> Void, onError: (Error) -> Void) {
        guard isCurrent(epoch) else { return }
        do {
            try body()
        } catch {
            onError(error)
        }
    }
}
