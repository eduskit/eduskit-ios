import Foundation

/// OS notification for completion of the SDK teardown job. Core alone decides
/// cleanup outcomes/deadlines; this receipt does not claim resources succeeded.
final class NativeSdkDestroyReceipt {
    private let group=DispatchGroup()
    private let lock=NSLock()
    private var completed=false
    init() {group.enter()}
    func notify(_ completion:@escaping()->Void) {
        group.notify(queue:.global(qos:.userInitiated),execute:completion)
    }
    /// Called by the dedicated SDK destroy worker, never by a render callback.
    func complete() {
        lock.lock()
        guard !completed else{lock.unlock();return}
        completed=true
        lock.unlock()
        group.leave()
    }
}
