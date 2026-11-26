import Foundation

/// Owns Swift callback objects and OS queue lifetimes, never room/media policy.
/// Preparation stays on the worker; UI delivery only checks cancellation and calls listeners.
final class QueuedEventListeners<Key: Equatable, Value> {
    typealias Channel = Key
    private struct Entry {
        let id: UUID
        let channel: Channel
        let lease: DispatchWorkItem
        let callback: (Value) -> Void
        let onWorker: Bool
    }
    private static var workerLabel: String { "com.edukits.edusdk.whiteboard-media-callbacks" }
    private let worker: DispatchQueue
    private let lifetime = DispatchWorkItem {}
    private var entries: [Entry] = [] // accessed only on worker

    init(worker: DispatchQueue? = nil) {
        self.worker = worker ?? DispatchQueue(label: Self.workerLabel, qos: .userInitiated)
    }

    deinit { lifetime.cancel() }

    func add(_ channel: Channel, onWorker: Bool = false, listener: @escaping (Value) -> Void) -> () -> Void {
        let id = UUID()
        let lease = DispatchWorkItem {}
        worker.async { [weak self] in
            guard let self, !self.lifetime.isCancelled, !lease.isCancelled else { return }
            self.entries.append(Entry(id: id, channel: channel, lease: lease, callback: listener, onWorker:onWorker))
        }
        return { [weak self] in
            lease.cancel() // synchronous invalidation; never wait for the worker/UI queue
            self?.worker.async { [weak self] in self?.entries.removeAll { $0.id == id } }
        }
    }

    func emit(_ value: Value, channel: Channel, validUntil poll: DispatchWorkItem,
              destination: DispatchQueue?) {
        worker.async { [weak self] in
            guard let self, !self.lifetime.isCancelled, !poll.isCancelled else { return }
            let snapshot = self.entries.filter { $0.channel == channel && !$0.lease.isCancelled }
            let lifetime = self.lifetime
            let deliver: ([Entry]) -> Void = { values in
                guard !lifetime.isCancelled, !poll.isCancelled else { return }
                for entry in values where !entry.lease.isCancelled {
                    guard !lifetime.isCancelled, !poll.isCancelled else { return }
                    // Swift public callbacks are non-throwing. No Core/JSON/I/O here.
                    entry.callback(value)
                }
            }
            deliver(snapshot.filter { $0.onWorker })
            let published = snapshot.filter { !$0.onWorker }
            if let destination { destination.async { deliver(published) } }
            else { deliver(published) }
        }
    }

    func close() {
        lifetime.cancel()
        worker.async { [weak self] in self?.entries.removeAll() }
    }
}

// Keep one implementation of Swift subscription identity and OS queue cancellation.
enum WhiteboardMediaChannel { case clock, programResult, media }
typealias WhiteboardMediaEventListeners = QueuedEventListeners<WhiteboardMediaChannel, String>
enum CallbackChannel { case event }
typealias TypedEventListeners<Value> = QueuedEventListeners<CallbackChannel, Value>
