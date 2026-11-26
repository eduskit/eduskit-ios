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

/// 关摄像头时不挂 RTC 摄像头层，避免断流后的最后一帧盖住头像。
/// 台下直播主流仍要挂容器，关摄像头时由头像遮罩盖住画面。
/// 节目音频和屏幕共享不看这个条件。
func showsParticipantCameraSurface(videoMuted: Bool) -> Bool {
    !videoMuted
}

/// 台下主流只要有流名就挂直播容器，与摄像头开关无关。
func showsParticipantLiveSurface(liveStreamName: String?) -> Bool {
    guard let liveStreamName else { return false }
    return !liveStreamName.isEmpty
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
    public var classroomView: ClassroomView = .empty
    public var continuation: ContinuationView?
    public var stageParticipants: [ClassroomParticipant] = []
    public var featuredTeacher: ClassroomParticipant?
    public var onStage: [StageUser] = []
    public var members: [ClassroomMember] = []
    public var memberCount: UInt32 = 0
    public var membersNextCursor: String?
    public var membersLoading: Bool = false
    public var messages: [ClassroomChatMessageView] = []
    public var historyLoading = false
    public var historyHasMore = true
    public var historyError = false
    public var busy: Bool = false
    public var badgeText: String = ""
    /// Core 判定本人应以直播观看台上画面（未上台、不进 RTC）。
    public var needLive: Bool = false
    /// 台下该播哪几路；台上为空。格子复用同一套布局，只是改挂播放器。
    public var liveStreams: [LiveStream] = []
    public var timerMode: ClassroomTimerMode = .hidden
    public var timerSeconds: Int64?
    public var errorMessage: String?
    public var themePrimary: String = "#000000"
    public var feedback: UiFeedback?
    /// Core 明确返回 permission_denied 的操作；仅用于 UI 禁用态。
    public var permissionDeniedActions: Set<String> = []
    /// 底部工具栏各入口的渲染结论，由 Core `interaction_policy` 投影而来。
    public var toolbarEntries: [String: ToolbarEntry] = [:]
    /// 本人是否已举手；按钮据此在举手 / 取消之间切换。
    public var handRaised: Bool = false
    /// 本端屏幕共享是否真的在推流（以 Vendor 回执为准，而非下发指令时刻）。
    public var localScreenSharing: Bool = false
    /// 正在共享屏幕的远端用户；台上成员据此订阅辅流。
    public var screenShareUserIds: [String] = []
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
