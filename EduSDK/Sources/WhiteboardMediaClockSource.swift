import Foundation

/// SDK clock callbacks only wake this OS cache. The original server/display and
/// sampling coordinates come from Rust's scoped clock_sample capability.
public final class WhiteboardMediaClockSource {
    public static let defaultTimeoutMs = 15_000
    public typealias Completion = (Result<Void,SdkError>) -> Void
    private enum Defaults {
        static let maximumWaits = 32
        static let maximumTimeoutMs = 60_000
        static let queueLabel = "com.edukits.edusdk.whiteboard-media-clock"
    }
    private final class Wait {
        let lease = DispatchWorkItem {}
        let completion: Completion
        var timer: DispatchSourceTimer?
        var done = false
        init(_ completion: @escaping Completion) { self.completion = completion }
    }
    public let mediaSessionId: String
    private let requestPort: WhiteboardMediaRequestPort
    private let worker = DispatchQueue(label:Defaults.queueLabel,qos:.userInitiated)
    private let lock = NSLock()
    private let now: () throws -> UInt64
    private let timeoutMs: Int
    // Gate/cache fields use lock; no Core, waiting or callbacks under lock.
    private var closed: SdkError?
    private var cache: [String:Any]?
    private var unsubscribe: (() -> Void)?
    private var reservations = 0
    private var wakeQueued = false
    // Worker only.
    private var waits: [UUID:Wait] = [:]
    private var refreshing = false
    private var pulsePending = false

    /// Ownership of requestPort transfers to this source. Close before replacing
    /// the SDK media session. All readiness/wake completions run on worker.
    public convenience init(requestPort: WhiteboardMediaRequestPort, timeoutMs: Int = WhiteboardMediaClockSource.defaultTimeoutMs,
                            subscribe: WhiteboardMediaRequestPort.Subscribe) throws {
        try self.init(requestPort:requestPort,timeoutMs:timeoutMs,now:WhiteboardMediaMonotonicClock.milliseconds,subscribe:subscribe)
    }
    init(requestPort: WhiteboardMediaRequestPort, timeoutMs: Int,
         now: @escaping () throws -> UInt64, subscribe: WhiteboardMediaRequestPort.Subscribe) throws {
        guard timeoutMs > 0, timeoutMs <= Defaults.maximumTimeoutMs, !requestPort.isClosed else {
            throw SdkError(code:.invalidArgument,message:"Invalid whiteboard media clock source options")
        }
        self.requestPort = requestPort; self.mediaSessionId = requestPort.mediaSessionId
        self.now = now; self.timeoutMs = timeoutMs
        do {
            let off = try subscribe { [weak self] _ in self?.pulse() }
            lock.lock(); let terminal = closed != nil
            if !terminal { unsubscribe = off }
            lock.unlock(); if terminal { off() }
        } catch { requestPort.close(); throw SdkError(code:.whiteboardProviderError,message:error.localizedDescription) }
        pulse() // Fetch an already-sampled Core clock without waiting for another UI callback.
    }
    deinit {
        unsubscribe?(); requestPort.close()
        let pending = Array(waits.values)
        for wait in pending { wait.timer?.setEventHandler {}; wait.timer?.cancel() }
        worker.async {
            for wait in pending where !wait.done { wait.done = true; wait.completion(.failure(Self.disposed())) }
        }
    }
    public var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed != nil }
    private static func disposed() -> SdkError { SdkError(code:.invalidState,message:"Whiteboard media clock source is closed") }
    private func pulse() {
        lock.lock()
        guard closed == nil, !wakeQueued else { lock.unlock(); return }
        wakeQueued = true; lock.unlock()
        worker.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); self.wakeQueued = false; let closed = self.closed; self.lock.unlock()
            guard closed == nil else { return }
            if self.refreshing { self.pulsePending = true } else { self.refresh() }
        }
    }
    private func refresh() {
        refreshing = true
        requestPort.request(["operation":"clock_sample"]) { [weak self] result in
            guard let self else { return }
            self.worker.async { [self] in
                self.refreshing = false
                guard !self.isClosed else { return }
                switch result {
                case .success(let value):
                    guard let envelope = value as? [String:Any], envelope.count == 2,
                          let available = envelope["available"] as? NSNumber,
                          CFGetTypeID(available) == CFBooleanGetTypeID(), envelope["sample"] != nil else {
                        self.close(SdkError(code:.contractMismatch,message:"Invalid SDK media clock availability")); return
                    }
                    if !available.boolValue {
                        guard envelope["sample"] is NSNull else {
                            self.close(SdkError(code:.contractMismatch,message:"Invalid unavailable SDK media clock")); return
                        }
                        self.lock.lock(); self.cache = nil; self.lock.unlock()
                        if self.pulsePending { self.pulsePending = false; self.refresh() }
                        return
                    }
                    guard let data = envelope["sample"] as? [String:Any], data.count == 4,
                          data["server_ms"] != nil, data["displayed_ms"] != nil, data["now_local_ms"] != nil,
                          let sampled = data["sample_local_ms"] as? NSNumber,
                          CFGetTypeID(sampled) != CFBooleanGetTypeID() else {
                        self.close(SdkError(code:.contractMismatch,message:"Invalid SDK media clock sample")); return
                    }
                    self.lock.lock()
                    let previous = self.cache?["sample_local_ms"] as? NSNumber
                    self.cache = data
                    self.lock.unlock()
                    if previous != sampled {
                        for (id,wait) in Array(self.waits) { self.finish(id,wait,.success(())) }
                    }
                case .failure(let failure):
                    self.close(failure.sdkError); return
                }
                if self.pulsePending { self.pulsePending = false; self.refresh() }
            }
        }
    }
    /// Use on the native Room worker, immediately before Core consumes the sample.
    /// Re-read the actual OS clock, including callback/queue delay and suspension.
    public func clockSample() throws -> [String:Any] {
        precondition(!Thread.isMainThread,"media_clock_requires_worker")
        lock.lock(); let failure = closed; var value = cache; lock.unlock()
        if let failure { throw failure }
        guard value != nil else { throw SdkError(code:.invalidState,message:"Whiteboard media clock sample unavailable") }
        value!["now_local_ms"] = try now()
        return value!
    }
    @discardableResult public func ready(completion: @escaping Completion) -> () -> Void { wait(immediate:true,completion:completion) }
    @discardableResult public func waitNext(completion: @escaping Completion) -> () -> Void { wait(immediate:false,completion:completion) }
    private func wait(immediate: Bool, completion: @escaping Completion) -> () -> Void {
        let id = UUID(), wait = Wait(completion)
        lock.lock(); let failure = closed; let full = reservations >= Defaults.maximumWaits
        if failure == nil && !full { reservations += 1 }
        lock.unlock()
        if let failure { worker.async { completion(.failure(failure)) }; return {} }
        if full { worker.async { completion(.failure(SdkError(code:.invalidState,message:"Whiteboard media clock waiter capacity reached"))) }; return {} }
        worker.async { [self,wait] in
            self.lock.lock(); let closed = self.closed; let available = self.cache != nil; self.lock.unlock()
            self.waits[id] = wait
            if let closed { self.finish(id,wait,.failure(closed)); return }
            if wait.lease.isCancelled { self.finish(id,wait,.failure(SdkError(code:.invalidState,message:"Whiteboard media clock wait cancelled"))); return }
            if immediate && available { self.finish(id,wait,.success(())); return }
            let timer = DispatchSource.makeTimerSource(queue:self.worker)
            timer.setEventHandler { [weak self,weak wait] in
                guard let self, let wait else { return }
                self.finish(id,wait,.failure(SdkError(code:.networkError,message:"Whiteboard media clock wait timed out")))
            }
            wait.timer = timer; timer.schedule(deadline:.now() + .milliseconds(self.timeoutMs)); timer.resume()
        }
        return { [weak self,weak wait] in
            guard let self, let wait else { return }; wait.lease.cancel()
            self.worker.async { [self,wait] in self.finish(id,wait,.failure(SdkError(code:.invalidState,message:"Whiteboard media clock wait cancelled"))) }
        }
    }
    private func finish(_ id: UUID, _ wait: Wait, _ result: Result<Void,SdkError>) {
        guard !wait.done else { return }; wait.done = true
        waits.removeValue(forKey:id); wait.timer?.setEventHandler {}; wait.timer?.cancel(); wait.timer = nil
        lock.lock(); reservations -= 1; let closed = self.closed; lock.unlock()
        if let closed { wait.completion(.failure(closed)) }
        else if wait.lease.isCancelled { wait.completion(.failure(SdkError(code:.invalidState,message:"Whiteboard media clock wait cancelled"))) }
        else { wait.completion(result) }
    }
    public func close() { close(Self.disposed()) }
    private func close(_ failure: SdkError) {
        lock.lock(); guard closed == nil else { lock.unlock(); return }
        closed = failure; cache = nil; let off = unsubscribe; unsubscribe = nil; lock.unlock()
        off?(); requestPort.close()
        worker.async { [self] in for (id,wait) in Array(waits) { finish(id,wait,.failure(failure)) } }
    }
}
