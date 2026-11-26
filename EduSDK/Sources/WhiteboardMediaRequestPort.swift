import Foundation

/// Local transport outcome only. A cancelled/timed-out/disposed request may
/// already have been accepted by Room; keep requestJson for Core reconciliation.
public struct WhiteboardMediaRequestFailure: LocalizedError {
    public enum Kind: String { case cancelled, disposed, timeout, dispatch, wire, core, capacity }
    public let kind: Kind
    public let requestJson: String?
    public let coreResult: [String: Any]?
    public let sdkError: SdkError
    public var errorDescription: String? { sdkError.message }
}

/// One OS request/callback association per SDK media session. Authentication,
/// request validation and command acceptance remain in the existing Rust Core.
public final class WhiteboardMediaRequestPort {
    public static let defaultTimeoutMs = 20_000
    public typealias Completion = (Result<Any, WhiteboardMediaRequestFailure>) -> Void
    public typealias Subscribe = (@escaping (String) -> Void) throws -> (() -> Void)
    private enum Defaults {
        static let maximumTimeoutMs = 60_000
        static let maximumPending = 32
        static let maximumQueuedResults = 64
        static let maximumRequestBytes = 24 * 1024
        static let maximumResultBytes = 4 * 1024 * 1024
        static let dispatchLabel = "com.edukits.edusdk.whiteboard-media-dispatch"
        static let workerLabel = "com.edukits.edusdk.whiteboard-media-requests"
        static let failurePrefix = "Whiteboard media request failed: "
    }
    private final class Wait {
        let lease = DispatchWorkItem {}
        let completion: Completion
        var id: String?
        var json: String?
        var timer: DispatchSourceTimer?
        let dispatchLease = DispatchWorkItem {}
        var dispatchScheduled = false // worker only
        var dispatchRetired = false // worker only
        var done = false // worker only
        init(_ completion: @escaping Completion) { self.completion = completion }
    }
    public let mediaSessionId: String
    private let send: (String) throws -> Void
    private let worker = DispatchQueue(label: Defaults.workerLabel, qos: .userInitiated)
    private let dispatchQueue = DispatchQueue(label: Defaults.dispatchLabel, qos: .userInitiated)
    private let timeoutMs: Int
    // Gate fields are accessed under lock, never held while calling Core/listeners.
    private let lock = NSLock()
    private var closed = false
    private var closeKind: WhiteboardMediaRequestFailure.Kind = .disposed
    private var reservations = 0
    private var activeDispatches = 0
    private var queuedResults = 0
    private var unsubscribe: (() -> Void)?
    private var pending: [String: Wait] = [:] // worker only

    public init(mediaSessionId: String, timeoutMs: Int = WhiteboardMediaRequestPort.defaultTimeoutMs,
                send: @escaping (String) throws -> Void, subscribe: Subscribe) throws {
        guard !mediaSessionId.isEmpty, timeoutMs > 0, timeoutMs <= Defaults.maximumTimeoutMs else {
            throw SdkError(code: .invalidArgument, message: "Invalid whiteboard media request port options")
        }
        self.mediaSessionId = mediaSessionId
        self.timeoutMs = timeoutMs
        self.send = send
        do { self.unsubscribe = try subscribe { [weak self] json in self?.receive(json) } }
        catch { throw Self.failure(.wire).sdkError }
    }
    deinit {
        unsubscribe?()
        let waits = Array(pending.values)
        for wait in waits { wait.timer?.setEventHandler {}; wait.timer?.cancel(); wait.dispatchLease.cancel() }
        worker.async {
            for wait in waits where !wait.done { wait.done = true; wait.completion(.failure(Self.failure(.disposed,wait))) }
        }
    }
    public var isClosed: Bool { lock.lock(); defer { lock.unlock() }; return closed }
    private static func failure(_ kind: WhiteboardMediaRequestFailure.Kind, _ wait: Wait? = nil,
                                result: [String: Any]? = nil, underlying: Error? = nil) -> WhiteboardMediaRequestFailure {
        let error = underlying as? SdkError ?? SdkError(code: .whiteboardProviderError,
            message: Defaults.failurePrefix + kind.rawValue + (underlying.map { ": " + $0.localizedDescription } ?? ""))
        return WhiteboardMediaRequestFailure(kind: kind, requestJson: wait?.json, coreResult: result, sdkError: error)
    }

    /// Any caller thread. Encoding, SDK dispatch, timers and completion run on
    /// worker. Cancel is nonblocking and does not roll back a Room command.
    @discardableResult
    public func request(_ request: [String: Any], completion: @escaping Completion) -> () -> Void {
        let wait = Wait(completion)
        lock.lock()
        let rejected: WhiteboardMediaRequestFailure.Kind? = closed ? .disposed :
            (reservations >= Defaults.maximumPending || activeDispatches >= Defaults.maximumPending ? .capacity : nil)
        if rejected == nil { reservations += 1; activeDispatches += 1 }
        lock.unlock()
        if let rejected {
            worker.async { completion(.failure(Self.failure(rejected))) }
            return {}
        }
        worker.async { [self, wait] in
            if isClosed { finish(wait, .failure(Self.failure(.disposed, wait))); return }
            if wait.lease.isCancelled { finish(wait, .failure(Self.failure(.cancelled, wait))); return }
            do {
                let id = UUID().uuidString
                let envelope: [String:Any] = ["media_session_id":mediaSessionId,"request_id":id,"request":request]
                // Foundation can raise an Objective-C exception for unsupported
                // values, which Swift do/catch cannot catch. Reject before write.
                guard JSONSerialization.isValidJSONObject(envelope) else { throw Self.failure(.wire) }
                let bytes = try JSONSerialization.data(withJSONObject:envelope)
                guard bytes.count <= Defaults.maximumRequestBytes else { throw Self.failure(.wire) }
                wait.id = id; wait.json = String(decoding:bytes,as:UTF8.self)
                pending[id] = wait
                let timer = DispatchSource.makeTimerSource(queue:worker)
                timer.setEventHandler { [weak self, weak wait] in
                    guard let self, let wait else { return }
                    self.finish(wait,.failure(Self.failure(.timeout,wait)))
                }
                wait.timer = timer
                timer.schedule(deadline:.now() + .milliseconds(timeoutMs)); timer.resume()
                // Reservation and encoding may precede a synchronous close/cancel.
                if isClosed { finish(wait,.failure(Self.failure(.disposed,wait))); return }
                if wait.lease.isCancelled { finish(wait,.failure(Self.failure(.cancelled,wait))); return }
                wait.dispatchScheduled = true
                let encoded = wait.json!
                dispatchQueue.async { [self, wait] in
                    var failure: Error?
                    if !isClosed, !wait.dispatchLease.isCancelled, !wait.lease.isCancelled {
                        do { try send(encoded) } catch { failure = error }
                    }
                    let dispatchFailure = failure
                    worker.async { [self, wait] in
                        retireDispatch(wait)
                        if let dispatchFailure { finish(wait,.failure(Self.failure(.dispatch,wait,underlying:dispatchFailure))) }
                    }
                }
            } catch { finish(wait,.failure(Self.failure(.wire,wait,underlying:error))) }
        }
        return { [weak self, weak wait] in
            guard let self, let wait else { return }
            wait.lease.cancel()
            self.worker.async { [self, wait] in self.finish(wait,.failure(Self.failure(.cancelled,wait))) }
        }
    }
    private func finish(_ wait: Wait, _ result: Result<Any, WhiteboardMediaRequestFailure>) {
        guard !wait.done else { return }
        wait.done = true
        wait.dispatchLease.cancel()
        if !wait.dispatchScheduled { retireDispatch(wait) }
        if let id = wait.id { pending.removeValue(forKey:id) }
        wait.timer?.setEventHandler {}; wait.timer?.cancel(); wait.timer = nil
        lock.lock(); reservations -= 1; let closed = self.closed; let closeKind = self.closeKind; lock.unlock()
        // Queued success never reaches an old owner after close/cancel.
        if closed { wait.completion(.failure(Self.failure(closeKind,wait))) }
        else if wait.lease.isCancelled { wait.completion(.failure(Self.failure(.cancelled,wait))) }
        else { wait.completion(result) }
    }
    private func retireDispatch(_ wait: Wait) {
        guard !wait.dispatchRetired else { return }
        wait.dispatchRetired = true
        lock.lock(); activeDispatches -= 1; lock.unlock()
    }
    private func receive(_ json: String) {
        lock.lock()
        if closed || reservations == 0 { lock.unlock(); return }
        if queuedResults >= Defaults.maximumQueuedResults {
            lock.unlock(); close(kind:.wire); return
        }
        queuedResults += 1
        lock.unlock()
        worker.async { [self] in
            defer { lock.lock(); queuedResults -= 1; lock.unlock() }
            guard !isClosed else { return }
            do {
                guard json.utf8.count <= Defaults.maximumResultBytes,
                      let envelope = try JSONSerialization.jsonObject(with:Data(json.utf8)) as? [String:Any],
                      let scope = envelope["media_session_id"] as? String,
                      let result = envelope["result"] as? [String:Any],
                      let id = result["request_id"] as? String,
                      let ok = result["ok"] as? NSNumber, CFGetTypeID(ok) == CFBooleanGetTypeID(),
                      result[ok.boolValue ? "data" : "error"] != nil else {
                    throw Self.failure(.wire)
                }
                guard scope == mediaSessionId, let wait = pending[id] else { return }
                if ok.boolValue { finish(wait,.success(result["data"]!)) }
                else { finish(wait,.failure(Self.failure(.core,wait,result:result))) }
            } catch { close(kind:.wire) }
        }
    }
    public func close() { close(kind:.disposed) }
    private func close(kind: WhiteboardMediaRequestFailure.Kind) {
        lock.lock()
        guard !closed else { lock.unlock(); return }
        closed = true; closeKind = kind
        let unsubscribe = self.unsubscribe; self.unsubscribe = nil
        lock.unlock()
        unsubscribe?() // synchronously invalidate SDK listener, never wait for its worker.
        worker.async { [self] in
            for wait in Array(pending.values) { finish(wait,.failure(Self.failure(kind,wait))) }
        }
    }
}
