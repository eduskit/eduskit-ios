import Foundation

/// UI-only native capability. Runs encoding, shared Rust and projection off the
/// main thread without constructing an EduSdk or starting a classroom session.
public final class EduFeedback {
    private let worker = DispatchQueue(label: "com.edukits.edusdk.feedback")
    private var generation: UInt64 = 0 // main-thread lifecycle ownership

    public init() {}

    public func evaluate<Output>(
        request: @escaping () throws -> [String: Any],
        project: @escaping ([String: Any]) throws -> Output,
        completion: @escaping (Result<Output, Error>) -> Void
    ) {
        dispatchPrecondition(condition: .onQueue(.main))
        let epoch = generation
        worker.async {
            let result = Result<Output, Error> {
                let data = try JSONSerialization.data(withJSONObject: request())
                let response = uiFeedback(requestJson: String(decoding: data, as: UTF8.self))
                guard let object = try JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any] else {
                    throw SdkError(code: .invalidArgument, message: "Invalid feedback response")
                }
                return try project(object)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == epoch else { return }
                completion(result)
            }
        }
    }

    /// Invalidates queued UI callbacks immediately. Does not affect the classroom.
    public func invalidate() {
        dispatchPrecondition(condition: .onQueue(.main))
        generation &+= 1
    }
}
