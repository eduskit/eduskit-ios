import Foundation

enum HostMainCallError: LocalizedError {
    case dispatchThreadWait
    case dispatcherRejected
    case unconfirmed

    var errorDescription: String? {
        switch self {
        case .dispatchThreadWait: return "Host main call cannot wait on the dispatch thread"
        case .dispatcherRejected: return "Host main dispatcher rejected the operation"
        case .unconfirmed: return "Host main operation timed out or was cancelled; completion unconfirmed"
        }
    }
}

private final class HostMainCallResult<T> {
    var value: Result<T, Error>?
}

/// The worker waits for the submitted item, never the UI thread. A timed-out queued item is cancelled.
func awaitHostMainCall<T>(
    onDispatchThread: Bool,
    timeout: DispatchTimeInterval = .seconds(5),
    enqueue: (DispatchWorkItem) -> Bool,
    operation: @escaping () throws -> T
) throws -> T {
    guard !onDispatchThread else { throw HostMainCallError.dispatchThreadWait }
    let result = HostMainCallResult<T>()
    let work = DispatchWorkItem { result.value = Result(catching: operation) }
    guard enqueue(work) else {
        work.cancel()
        throw HostMainCallError.dispatcherRejected
    }
    guard work.wait(timeout: .now() + timeout) == .success else {
        work.cancel()
        throw HostMainCallError.unconfirmed
    }
    guard let value = result.value else { throw HostMainCallError.unconfirmed }
    return try value.get()
}
