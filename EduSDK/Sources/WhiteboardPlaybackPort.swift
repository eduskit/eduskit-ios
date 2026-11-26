import Foundation

/// Attach a prepared, initially muted native Room session; no waits on Main.
public final class WhiteboardPlaybackPort: WhiteboardMediaPortLifetime {
    public let mediaSessionId: String
    private let retired = DispatchWorkItem {}
    private let output: WhiteboardPlaybackOutput
    public var isClosed: Bool { retired.isCancelled }
    init(mediaSessionId: String, output: WhiteboardPlaybackOutput) {
        self.mediaSessionId = mediaSessionId; self.output = output
    }
    public convenience init(sdk: EduSdk, mediaSessionId: String) throws {
        self.init(mediaSessionId: mediaSessionId, output: sdk.whiteboardPlaybackOutput)
        do { try sdk.registerWhiteboardMediaPort(self) } catch { close(); throw error }
    }
    public func attach(_ apply: @escaping (String, Bool, @escaping (Result<[String:Any],Error>) -> Void) -> Void,
                       completion: @escaping (Result<Void,Error>) -> Void) {
        output.attach(self, output: { [weak self] target, done in
            guard let self, !self.isClosed else { done(.failure(CancellationError())); return }
            apply(target.requestId, target.allowed) { [weak self] result in
                do {
                    guard let self, !self.isClosed else { throw CancellationError() }
                    let reply = try result.get()
                    guard reply["ok"] as? Bool == true,
                          let receipt = reply["playback_output"] as? [String:Any],
                          receipt["request_id"] as? String == target.requestId,
                          receipt["allowed"] as? Bool == target.allowed,
                          receipt["applied"] as? Bool == true else {
                        throw NSError(domain: "EduSDK.WhiteboardPlayback", code: -1,
                                      userInfo: [NSLocalizedDescriptionKey:"Whiteboard playback was not applied"])
                    }
                    done(.success(()))
                } catch { done(.failure(error)) }
            }
        }, completion: completion)
    }
    public func close() { retired.cancel(); output.detach(self) }
}
