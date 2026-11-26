import Foundation

/// Delivery bookkeeping only. Registration precedes making the batch available to workers.
final class RequiredEffectTracker {
    final class Completion {
        private let condition = NSCondition()
        private var finished = false
        private var failure: Error?
        func wait() -> Error? {
            condition.lock(); defer { condition.unlock() }
            while !finished { condition.wait() }
            return failure
        }
        fileprivate func finish(_ error: Error?) {
            condition.lock(); failure = error; finished = true
            condition.broadcast(); condition.unlock()
        }
    }
    final class Waiter {
        private let lock = NSLock()
        private var error: Error?
        private var retired = false
        var failure: Error? { lock.lock(); defer { lock.unlock() }; return error }
        var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return retired }
        fileprivate func record(_ failure: Error) {
            lock.lock(); if error == nil { error = failure }; lock.unlock()
        }
        fileprivate func cancel() { lock.lock(); retired = true; lock.unlock() }
    }
    private let lock = NSLock()
    private var pending: [UInt64: Completion] = [:]
    private var waiters: [ObjectIdentifier: Waiter] = [:]
    func beginWait() -> Waiter {
        lock.lock(); defer { lock.unlock() }
        let waiter = Waiter(); waiters[ObjectIdentifier(waiter)] = waiter
        return waiter
    }
    @discardableResult func endWait(_ waiter: Waiter) -> Error? {
        lock.lock(); defer { lock.unlock() }
        waiters.removeValue(forKey: ObjectIdentifier(waiter))
        return waiter.failure
    }
    func register(_ ids: [UInt64], replacingPending: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        if replacingPending { waiters.values.forEach { $0.cancel() }; waiters.removeAll() }
        let retired = replacingPending ? Array(pending.values) : []
        if replacingPending { pending.removeAll() }
        for id in ids where pending[id] == nil { pending[id] = Completion() }
        retired.forEach { $0.finish(nil) }
    }
    func snapshot() -> [Completion] {
        lock.lock(); defer { lock.unlock() }
        return Array(pending.values)
    }
    func complete(_ id: UInt64, failure: Error? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard let completion = pending.removeValue(forKey: id) else { return }
        if let failure { waiters.values.forEach { $0.record(failure) } }
        completion.finish(failure)
    }
    func cancelAll() {
        lock.lock(); defer { lock.unlock() }
        waiters.values.forEach { $0.cancel() }; waiters.removeAll()
        pending.values.forEach { $0.finish(nil) }; pending.removeAll()
    }
}
