import Foundation

/// OS publication only. Main reads its last immutable value without waiting for a worker.
final class SnapshotPublication<Value> {
    private let worker: DispatchQueue
    private let callbacks: TypedEventListeners<Value>
    private let revision: (Value) -> UInt64
    private let lifetime = DispatchWorkItem {}
    private let preparedLock = NSLock()
    private var prepared: Value
    private var mainValue: Value // only read/written on main after initialization

    init(initial: Value, worker: DispatchQueue, revision: @escaping (Value) -> UInt64) {
        prepared = initial
        mainValue = initial
        self.worker = worker
        self.revision = revision
        callbacks = TypedEventListeners(worker: worker)
    }

    func read() -> Value {
        if Thread.isMainThread { return mainValue }
        preparedLock.lock()
        defer { preparedLock.unlock() }
        return prepared
    }

    func subscribe(_ listener: @escaping (Value) -> Void) -> () -> Void {
        let lease = DispatchWorkItem {}
        let lifetime = self.lifetime
        let revision = self.revision
        var deliveredRevision: UInt64? // the delivery closure only runs on main
        let deliver: (Value) -> Void = { value in
            guard !lifetime.isCancelled, !lease.isCancelled else { return }
            let next = revision(value)
            if let deliveredRevision, next <= deliveredRevision { return }
            deliveredRevision = next
            listener(value)
        }
        let unsubscribe = callbacks.add(.event, listener: deliver)
        worker.async { [weak self] in
            guard let self, !lifetime.isCancelled, !lease.isCancelled else { return }
            let initial = self.read()
            DispatchQueue.main.async { deliver(initial) }
        }
        return { lease.cancel(); unsubscribe() }
    }

    /// Called by the single presentation worker after mapping the Core projection.
    func publish(_ value: Value, validUntil poll: DispatchWorkItem) {
        guard !lifetime.isCancelled, !poll.isCancelled else { return }
        preparedLock.lock()
        prepared = value
        preparedLock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.lifetime.isCancelled, !poll.isCancelled else { return }
            self.mainValue = value
        }
        callbacks.emit(value, channel: .event, validUntil: poll, destination: .main)
    }

    /// Called after preparing this batch, even when it contains events without a projection change.
    func deliverAfterPublication(validUntil poll: DispatchWorkItem, _ delivery: @escaping () -> Void) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.lifetime.isCancelled, !poll.isCancelled else { return }
            delivery()
        }
    }

    func close() {
        lifetime.cancel()
        callbacks.close()
    }
}
