import Foundation

/// Coalesces queue submissions, never events. A wakeup during drain queues one more pass.
/// The lock protects only dispatch state; Core work and callbacks never run under it.
final class SerialEventPump {
    private let queue: DispatchQueue
    private let drain: () -> Void
    private let lock = NSLock()
    private var queued = false
    private var closed = false

    init(queue: DispatchQueue, drain: @escaping () -> Void) {
        self.queue = queue
        self.drain = drain
    }

    func request() {
        lock.lock()
        guard !closed, !queued else { lock.unlock(); return }
        queued = true
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.queued = false
            let active = !self.closed
            self.lock.unlock()
            if active { self.drain() }
        }
    }

    func close() {
        lock.lock()
        closed = true
        lock.unlock()
    }
}
