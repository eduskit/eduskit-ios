import Foundation

/// Bridges a native asynchronous stop to the SDK's FIFO effect worker.
/// It never waits on Main or reinterprets a Core resource/lease outcome.
enum WhiteboardNativeStopReceipt {
    typealias Completion = (Result<Void,Error>) -> Void
    enum Failure: LocalizedError {
        case mainThread, timeout
        var errorDescription:String? {
            switch self {
            case .mainThread:return "Whiteboard stop must run on the SDK worker"
            case .timeout:return "Native whiteboard stop timed out"
            }
        }
    }
    private enum Defaults { static let timeoutSeconds:TimeInterval = 5 }
    private final class Receipt {
        let lock=NSLock()
        let signal=DispatchSemaphore(value:0)
        var result:Result<Void,Error>?
        var retired=false
        func complete(_ value:Result<Void,Error>) {
            lock.lock();defer {lock.unlock()}
            guard !retired,result == nil else{return}
            result=value;signal.signal()
        }
        func take(timedOut:Bool) throws {
            lock.lock();defer {lock.unlock()}
            retired=true
            guard !timedOut,let result else{throw Failure.timeout}
            try result.get()
        }
    }
    static func wait(timeout:TimeInterval = Defaults.timeoutSeconds,
                     start: (@escaping Completion) -> Void) throws {
        guard !Thread.isMainThread else{throw Failure.mainThread}
        let receipt=Receipt()
        start { value in
            DispatchQueue.global(qos:.userInitiated).async { receipt.complete(value) }
        }
        let timedOut = receipt.signal.wait(timeout:.now()+timeout) == .timedOut
        try receipt.take(timedOut:timedOut)
    }
}
