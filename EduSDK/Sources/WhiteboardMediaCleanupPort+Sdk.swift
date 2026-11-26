import Foundation

public extension WhiteboardMediaCleanupPort {
    /// The SDK retains the cleanup owner independently from business-port
    /// retirement and publishes its final prepared frame before Core release.
    convenience init(sdk:EduSdk,mediaSessionId:String) {
        self.init(mediaSessionId:mediaSessionId,call:{ [weak sdk] json,done in
            guard let sdk else {
                done(.failure(SdkError(code:.notInitialized,message:"Cleanup SDK was released")));return
            }
            sdk.invokeMediaCleanup(json,completion:done)
        })
        sdk.registerMediaCleanupSource(self)
    }
}
