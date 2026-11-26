import Foundation

public extension WhiteboardMediaClockSource {
    /// Core's original monotonic sample is cached in the SDK. Clock events are
    /// wakeups only; no decoding, rebasing or Room planning occurs on main.
    convenience init(sdk: EduSdk, mediaSessionId: String, timeoutMs: Int = WhiteboardMediaClockSource.defaultTimeoutMs) throws {
        let port = try WhiteboardMediaRequestPort(sdk:sdk,mediaSessionId:mediaSessionId)
        try self.init(requestPort:port,timeoutMs:timeoutMs,subscribe:{ [weak sdk] listener in
            guard let sdk else { throw SdkError(code:.invalidState,message:"Whiteboard media SDK was released") }
            return sdk.observeWhiteboardMediaClockOnWorker(listener)
        })
        do { try sdk.registerWhiteboardMediaPort(self) }
        catch { close(); throw error }
    }
}
