import Foundation

/// Serial native IO delivery; supplied targets are selected exclusively by Core.
final class WhiteboardPlaybackOutput {
    struct Target { let requestId: String; let allowed: Bool }
    typealias Completion = (Result<Void,Error>) -> Void
    typealias Apply = (Target, @escaping Completion) -> Void
    private let queue = DispatchQueue(label: "edusdk.whiteboard.output")
    private var latest = Target(requestId: "initial-output", allowed: true)
    private var owner: AnyObject?
    private var apply: Apply?
    private func deliver(_ output: Apply, _ target: Target) throws {
        let settled = DispatchSemaphore(value: 0)
        var result: Result<Void,Error>!
        output(target) { value in result = value; settled.signal() }
        settled.wait()
        try result.get()
    }
    func set(_ target: Target) throws {
        precondition(!Thread.isMainThread)
        dispatchPrecondition(condition: .notOnQueue(queue))
        try queue.sync {
            latest = target
            if let apply { try deliver(apply, target) }
        }
    }
    func attach(_ key: AnyObject, output: @escaping Apply, completion: @escaping Completion) {
        queue.async { [self] in
            do {
                guard owner == nil || owner === key else { throw CancellationError() }
                owner = key; apply = output
                try deliver(output, latest)
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }
    func detach(_ key: AnyObject) {
        queue.async { [self] in if owner === key { owner = nil; apply = nil } }
    }
}
