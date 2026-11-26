import Foundation

public typealias ContinuationEnvironmentReport = (String, @escaping (Result<Void, Error>) -> Void) -> Void
public typealias ContinuationEnvironmentSubscribe = (@escaping ContinuationEnvironmentReport) throws -> (() -> Void)

/// Runtime-owned native IO ordering and retirement, without background policy.
final class ContinuationEnvironmentSubscription {
    private let worker = DispatchQueue(label: "edusdk.continuation.subscription")
    private let retired = DispatchWorkItem {}
    private var cleanup: (() -> Void)? // worker only
    private let deliver: (String) throws -> Void
    init(deliver: @escaping (String) throws -> Void) { self.deliver = deliver }
    private func requireActive() throws {
        if retired.isCancelled { throw NSError(domain: "EduSDK.ContinuationSubscriptionRetired", code: 1) }
    }
    func start(_ subscribe: @escaping ContinuationEnvironmentSubscribe) throws {
        do {
            try worker.sync {
                try requireActive()
                cleanup = try subscribe { [weak self] request, completion in
                    guard let self else {
                        completion(.failure(NSError(domain: "EduSDK.ContinuationSubscriptionRetired", code: 1)))
                        return
                    }
                    self.worker.async {
                        do { try self.requireActive(); try self.deliver(request); completion(.success(())) }
                        catch { completion(.failure(error)) }
                    }
                }
                try requireActive()
            }
        } catch { close(); throw error }
    }
    func close() {
        retired.cancel()
        worker.async {
            let value = self.cleanup; self.cleanup = nil
            value?()
        }
    }
}
