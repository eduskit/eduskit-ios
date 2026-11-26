import Foundation

/// Native IO ordering only. Core owns the playback decision.
final class NativePlaybackOutput {
    private let queue = DispatchQueue(label: "edusdk.rtc.output")
    private var allowed = true
    private var owner: AnyObject?
    private var apply: ((Bool) throws -> Void)?

    func attach(_ key: AnyObject, output: @escaping (Bool) throws -> Void,
                failed: @escaping (Error) -> Void) {
        queue.async { [self] in
            do {
                guard owner == nil || owner === key else { throw failure("Previous native output is not retired") }
                owner = key
                apply = output
                try output(allowed)
            } catch { failed(error) }
        }
    }

    private func performOnWorker<T>(_ work: () throws -> T) rethrows -> T {
        precondition(!Thread.isMainThread, "Native output waits are forbidden on the main/render thread")
        dispatchPrecondition(condition: .notOnQueue(queue))
        return try queue.sync(execute: work)
    }

    func setAllowed(_ value: Bool) throws {
        try performOnWorker {
            allowed = value
            try apply?(value)
        }
    }

    func perform<T>(_ key: AnyObject, work: () throws -> T) throws -> T {
        try performOnWorker {
            guard owner === key, let apply else { throw failure("Native output owner is retired") }
            try apply(allowed)
            return try work()
        }
    }

    func retire(_ key: AnyObject, release: () throws -> Void) throws {
        try performOnWorker {
            guard owner === key else { throw failure("Native output owner is retired") }
            try release() // Preserve ownership if native release fails.
            owner = nil
            apply = nil
        }
    }

    private func failure(_ message: String) -> Error {
        NSError(domain: "EduSDK.NativePlayback", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
