import Foundation
import EduSDK

@objc(EduThemeMode)
public enum EduThemeMode: Int {
    case system
    case light
    case dark
}

@objc(EduClassroomOptions)
public final class EduClassroomOptions: NSObject {
    @objc public let appId: String
    @objc public let backendUrl: String
    @objc public let classroomId: String
    @objc public let userId: String
    @objc public let displayName: String
    @objc public let inviteDemoUserId: String
    /// sdk-api Bearer；真实 join / onJoinSuccess 需要
    @objc public let userToken: String
    @objc public let themeMode: EduThemeMode
    /// BCP 47，例如 zh-CN / en-US；nil 表示跟随系统。
    @objc public let localeTag: String?
    @objc public let continuation: EduContinuationOptions?

    @objc public init(
        appId: String,
        backendUrl: String,
        classroomId: String,
        userId: String,
        displayName: String,
        userToken: String = "",
        inviteDemoUserId: String = "student-demo",
        themeMode: EduThemeMode = .system,
        localeTag: String? = nil,
        continuation: EduContinuationOptions? = nil
    ) {
        self.appId = appId
        self.backendUrl = backendUrl
        self.classroomId = classroomId
        self.userId = userId
        self.displayName = displayName
        self.userToken = userToken
        self.inviteDemoUserId = inviteDemoUserId
        self.themeMode = themeMode
        self.localeTag = localeTag
        self.continuation = continuation
    }
}
