import Foundation

public extension WhiteboardMediaRequestPort {
    /// Uses the existing SDK command/event path. No Room token or HTTP is built
    /// here; credentials and media-session validity are checked by Rust Core.
    convenience init(sdk: EduSdk, mediaSessionId: String, timeoutMs: Int = WhiteboardMediaRequestPort.defaultTimeoutMs) throws {
        try self.init(mediaSessionId:mediaSessionId,timeoutMs:timeoutMs,send:{ [weak sdk] json in
            guard let sdk else { throw SdkError(code:.invalidState,message:"Whiteboard media SDK was released") }
            try sdk.requestWhiteboardMediaProgram(json)
        },subscribe:{ [weak sdk] listener in
            guard let sdk else { throw SdkError(code:.invalidState,message:"Whiteboard media SDK was released") }
            return sdk.onWhiteboardMediaProgramResult(listener)
        })
        do { try sdk.registerWhiteboardMediaPort(self) }
        catch { close(); throw error }
    }
}
