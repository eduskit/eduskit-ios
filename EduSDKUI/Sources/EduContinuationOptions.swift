import Foundation

@objc(EduContinuationDefaults)
public final class EduContinuationDefaults: NSObject {
    @objc public let autoWindow: Bool
    @objc public let backgroundAudio: Bool
    @objc public let backgroundMicrophone: Bool
    @objc public init(autoWindow: Bool = true, backgroundAudio: Bool = true, backgroundMicrophone: Bool = false) {
        self.autoWindow = autoWindow; self.backgroundAudio = backgroundAudio; self.backgroundMicrophone = backgroundMicrophone
    }
}

@objc(EduContinuationOptions)
public final class EduContinuationOptions: NSObject {
    @objc public let tenantId: String
    @objc public let deviceId: String
    @objc public let allowWindow: Bool
    @objc public let allowBackgroundAudio: Bool
    @objc public let allowBackgroundMicrophone: Bool
    @objc public let defaults: EduContinuationDefaults?
    @objc public init(tenantId: String, deviceId: String, allowWindow: Bool = true,
                     allowBackgroundAudio: Bool = true, allowBackgroundMicrophone: Bool = true,
                     defaults: EduContinuationDefaults? = nil) {
        self.tenantId = tenantId; self.deviceId = deviceId; self.allowWindow = allowWindow
        self.allowBackgroundAudio = allowBackgroundAudio; self.allowBackgroundMicrophone = allowBackgroundMicrophone
        self.defaults = defaults
    }
}
