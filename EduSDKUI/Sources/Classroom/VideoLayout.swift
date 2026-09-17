import Foundation
import EduSDK

public enum VideoLayout: String, CaseIterable, Identifiable {
    case top
    case bottom
    case rightTop = "right-top"
    case rightBottom = "right-bottom"

    public var id: String { rawValue }

    public var isRight: Bool {
        self == .rightTop || self == .rightBottom
    }

    public var label: String {
        switch self {
        case .top: return EduI18n.text("layoutTop")
        case .bottom: return EduI18n.text("layoutBottom")
        case .rightTop: return EduI18n.text("layoutRightTop")
        case .rightBottom: return EduI18n.text("layoutRightBottom")
        }
    }
}

public enum InitStatus {
    case loading
    case ready
    case error
}

public struct UiSnapshot {
    public var initStatus: InitStatus = .loading
    public var phase: String = "idle"
    public var lifecycleStatus: ClassroomLifecycleStatus = .notStarted
    public var classroomId: String = ""
    public var classroomTitle: String = ""
    public var userId: String = ""
    public var displayName: String = ""
    public var localRole: String = ""
    public var onStage: [StageUser] = []
    public var members: [ClassroomMember] = []
    public var memberCount: UInt32 = 0
    public var membersNextCursor: String?
    public var membersLoading: Bool = false
    public var messages: [ImMessage] = []
    public var busy: Bool = false
    public var badgeText: String = ""
    /// Core 判定本人应以直播观看台上画面（未上台、不进 RTC）。
    public var needLive: Bool = false
    public var timerMode: ClassroomTimerMode = .hidden
    public var timerSeconds: Int64?
    public var errorMessage: String?
    public var themePrimary: String = "#000000"
    public var feedback: UiFeedback?
    /// Core 明确返回 permission_denied 的操作；仅用于 UI 禁用态。
    public var permissionDeniedActions: Set<String> = []
    /// Core `edit_whiteboard` 的当前裁决；false 时不挂载本地标注工具栏。
    public var canEditWhiteboard: Bool = false
    /// Core `end_class` 的当前裁决；操作栏据此在下课 / 离开之间切换。
    public var canEndClass: Bool = false
    /// 各能力域的推进状态；白板、RTC 失败时只做局部占位，不影响整场课堂
    public var joinProgress: JoinProgress = .idle
    /// join `teacherEduUserId`；纯视频课主舞台锚定此人
    public var teacherUserId: String?
    public var teacherDisplayName: String?
    public var teacherAvatarUrl: String?
    public var audioMuted: Bool = true
    public var videoMuted: Bool = true
    public var streamInfos: [StreamInfo] = []
    public var deviceCheckOpen: Bool = false
}

public extension JoinProgress {
    static let idle = JoinProgress(phase: .idle, im: .disabled, whiteboard: .disabled, rtc: .disabled)
}
