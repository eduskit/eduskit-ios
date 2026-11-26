import Foundation

public enum ClassroomRole: String, Codable {
    case teacher, student, assistant, observer
}

public enum ClassPhase: String, Codable {
    case idle, entered, inClass = "in_class", ended
}

public enum ClassroomLifecycleStatus: String, Codable {
    case notStarted = "not_started"
    case inProgress = "in_progress"
    case ended
    case expired
}

/// Native window IO only. Called on a worker; dispatch UI work asynchronously.
/// Report strict ContinuationEvent JSON from any thread after actual OS completion.
public protocol ContinuationWindowPort: AnyObject {
    func dispatch(requestJson: String, report: @escaping (String) -> Void) throws
}

public struct EduSdkCreateOptions {
    public let appId: String
    public let backendUrl: String
    /// sdk-api Bearer；进课 join / IM 凭证拉取需要
    public let userToken: String?
    /// 集成方 App 版本，用于遥测区分「哪个 App 版本开始变差」
    public let appVersion: String?
    /// 遥测摄取根地址（log-ingest-svc），与 backendUrl 分离；join.ingestUrl 会覆盖
    public let telemetryUrl: String?
    public let liveLicenseUrl: String?
    public let liveLicenseKey: String?
    public let continuationWindow: ContinuationWindowPort?
    /// Worker-only initialization factory returning strict configure JSON, before joining.
    public let continuation: (() throws -> String)?
    public let continuationEnvironment: ContinuationEnvironmentSubscribe?
    public let liveSupportsLeb: Bool

    public init(
        appId: String,
        backendUrl: String,
        userToken: String? = nil,
        appVersion: String? = nil,
        telemetryUrl: String? = nil,
        liveLicenseUrl: String? = nil,
        liveLicenseKey: String? = nil,
        liveSupportsLeb: Bool = true,
        continuationWindow: ContinuationWindowPort? = nil,
        continuation: (() throws -> String)? = nil,
        continuationEnvironment: ContinuationEnvironmentSubscribe? = nil
    ) {
        self.appId = appId
        self.backendUrl = backendUrl
        self.userToken = userToken
        self.appVersion = appVersion
        self.telemetryUrl = telemetryUrl
        self.liveLicenseUrl = liveLicenseUrl
        self.liveLicenseKey = liveLicenseKey
        self.continuationWindow = continuationWindow
        self.continuation = continuation
        self.continuationEnvironment = continuationEnvironment
        self.liveSupportsLeb = liveSupportsLeb
    }
}

public struct InitializeConfig {
    public var appId: String?
    public var backendUrl: String?

    public init(appId: String? = nil, backendUrl: String? = nil) {
        self.appId = appId
        self.backendUrl = backendUrl
    }
}

public struct EnterClassroomParams {
    public let classroomId: String
    public let userId: String
    public let displayName: String
    public let role: ClassroomRole?
    /// 覆盖 EduSdkCreateOptions.userToken
    public let userToken: String?

    public init(
        classroomId: String,
        userId: String,
        displayName: String,
        role: ClassroomRole? = nil,
        userToken: String? = nil
    ) {
        self.classroomId = classroomId
        self.userId = userId
        self.displayName = displayName
        self.role = role
        self.userToken = userToken
    }
}

public struct ClassroomMember: Codable {
    public let userId: String
    public var role: String?
    public var stageStatus: String?
    public var canUseMicrophone: Bool?
    public var canUseCamera: Bool?
    public var joinedAt: String?
    public var displayName: String?
    public var avatarUrl: String?

    public init(
        userId: String,
        role: String? = nil,
        stageStatus: String? = nil,
        canUseMicrophone: Bool? = nil,
        canUseCamera: Bool? = nil,
        joinedAt: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil
    ) {
        self.userId = userId
        self.role = role
        self.stageStatus = stageStatus
        self.canUseMicrophone = canUseMicrophone
        self.canUseCamera = canUseCamera
        self.joinedAt = joinedAt
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

public struct Courseware: Codable {
    public let id: String
    public var name: String
    public var originalName: String?
    public var format: String?
    public var status: String
    public var progress: Int
    public var sizeBytes: Int64?
    public var errorMessage: String?
    /// 白板转码侧 fileId（cw_fcv_*），用于刷新历史课件资源。
    public var wbCoursewareId: String?

    public init(
        id: String,
        name: String,
        originalName: String? = nil,
        format: String? = nil,
        status: String,
        progress: Int = 0,
        sizeBytes: Int64? = nil,
        errorMessage: String? = nil,
        wbCoursewareId: String? = nil
    ) {
        self.id = id
        self.name = name
        self.originalName = originalName
        self.format = format
        self.status = status
        self.progress = progress
        self.sizeBytes = sizeBytes
        self.errorMessage = errorMessage
        self.wbCoursewareId = wbCoursewareId
    }
}

public struct UserProfile: Codable {
    public let userId: String
    public var displayName: String?
    public var avatarUrl: String?
    public var role: ClassroomRole?

    public init(
        userId: String,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        role: ClassroomRole? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.role = role
    }
}

public struct StageUser: Codable {
    public let userId: String
    public var displayName: String?
    public let onStage: Bool

    public init(userId: String, displayName: String? = nil, onStage: Bool) {
        self.userId = userId
        self.displayName = displayName
        self.onStage = onStage
    }
}

public struct UserPermission: Codable {
    public let userId: String
    public var canUseMicrophone: Bool?
    public var canUseCamera: Bool?
    public var canSendMessage: Bool?
    public var canUseWhiteboard: Bool?
    public var canScreenShare: Bool?
}

public struct StreamInfo: Codable {
    public let userId: String
    public var audioMuted: Bool?
    public var videoMuted: Bool?
    public var streamId: String?

    public init(
        userId: String,
        audioMuted: Bool? = nil,
        videoMuted: Bool? = nil,
        streamId: String? = nil
    ) {
        self.userId = userId
        self.audioMuted = audioMuted
        self.videoMuted = videoMuted
        self.streamId = streamId
    }
}

public struct MediaDevice: Codable {
    public let deviceId: String
    public let label: String
    public let kind: String

    public init(deviceId: String, label: String, kind: String) {
        self.deviceId = deviceId
        self.label = label
        self.kind = kind
    }
}

public struct MediaDeviceList {
    public var cameras: [MediaDevice]
    public var microphones: [MediaDevice]
    public var speakers: [MediaDevice]

    public init(
        cameras: [MediaDevice] = [],
        microphones: [MediaDevice] = [],
        speakers: [MediaDevice] = []
    ) {
        self.cameras = cameras
        self.microphones = microphones
        self.speakers = speakers
    }
}

public enum MediaOpenHintAudience: String, Sendable {
    case teacher
    case student
}

public struct MediaOpenHint: Sendable {
    public var visible: Bool
    public var audience: MediaOpenHintAudience

    public init(visible: Bool, audience: MediaOpenHintAudience) {
        self.visible = visible
        self.audience = audience
    }
}

public struct DeviceCheckSelection {
    public var cameraId: String?
    public var microphoneId: String?
    public var speakerId: String?

    public init(cameraId: String? = nil, microphoneId: String? = nil, speakerId: String? = nil) {
        self.cameraId = cameraId
        self.microphoneId = microphoneId
        self.speakerId = speakerId
    }
}

public struct ImMessage: Codable {
    public let id: String
    public let senderId: String
    public let content: String
    public var sentAt: Int64?

    public init(id: String, senderId: String, content: String, sentAt: Int64? = nil) {
        self.id = id
        self.senderId = senderId
        self.content = content
        self.sentAt = sentAt
    }
}

public struct ImHistoryError: Codable { public let code: Int32; public let message: String }
public struct ImHistoryState: Codable {
    public let loading: Bool
    public let page: ImHistoryPage?
    public let error: ImHistoryError?
    public init(loading: Bool = false, page: ImHistoryPage? = nil, error: ImHistoryError? = nil) {
        self.loading = loading; self.page = page; self.error = error
    }
}

public struct ImHistoryPage: Codable {
    public let messages: [ImMessage]
    public let nextCursor: String?
    public let hasMore: Bool
}

public struct ImHistoryOptions {
    public var cursor: String?
    public var limit: Int32?
    public init(cursor: String? = nil, limit: Int32? = nil) { self.cursor = cursor; self.limit = limit }
}

public struct ClassInfo: Codable {
    public let classroomId: String
    public let phase: ClassPhase
    public var lifecycleStatus: ClassroomLifecycleStatus
    public var title: String?
    public var timerMode: ClassroomTimerMode?
    public var timerSeconds: Int64?

    public init(classroomId: String, phase: ClassPhase, lifecycleStatus: ClassroomLifecycleStatus, title: String? = nil, timerMode: ClassroomTimerMode? = nil, timerSeconds: Int64? = nil) {
        self.classroomId = classroomId
        self.phase = phase
        self.lifecycleStatus = lifecycleStatus
        self.title = title
        self.timerMode = timerMode
        self.timerSeconds = timerSeconds
    }
}

public enum ClassroomTimerMode: String, Codable {
    case hidden
    case countdown
    case elapsed
}

public struct ActionAvailability: Codable {
    public let action: String
    /// 入口是否应出现在界面上；false 必须隐藏而不是置灰。
    public let visible: Bool
    public let available: Bool
    public var reason: String?
}

/// 视频槽位。同一个用户可以同时有摄像头与屏幕共享两条轨道，
/// 纯 userId 作键会让共享画面覆盖掉对方的摄像头绑定。
public struct VideoSlot: Hashable {
    private static let separator = "\u{0}"

    public let userId: String
    public let streamType: EduStreamType

    public init(userId: String, streamType: EduStreamType) {
        self.userId = userId
        self.streamType = streamType
    }

    public init?(key: String) {
        guard let range = key.range(of: Self.separator, options: .backwards),
              let streamType = EduStreamType(rawValue: String(key[range.upperBound...]))
        else { return nil }
        self.userId = String(key[key.startIndex..<range.lowerBound])
        self.streamType = streamType
    }

    public var key: String { "\(userId)\(Self.separator)\(streamType.rawValue)" }
}

/// 台下一路可播流。`url` 已由 Core 按本端能力挑好协议，宿主直接喂给播放器。
public struct LiveStream: Equatable {
    public let streamName: String
    public let publisherUserId: String
    /// `LiveStreamType` 的线值
    public let streamType: String
    public let url: String
    /// 混音模式下视频路静音，声音走 audio 路
    public let muted: Bool
    public let expiresAt: String
    /// 厂商已回报出画
    public let playing: Bool

    public init(
        streamName: String,
        publisherUserId: String,
        streamType: String,
        url: String,
        muted: Bool,
        expiresAt: String,
        playing: Bool
    ) {
        self.streamName = streamName
        self.publisherUserId = publisherUserId
        self.streamType = streamType
        self.url = url
        self.muted = muted
        self.expiresAt = expiresAt
        self.playing = playing
    }
}

/// 台下流的用途。主流一人一路占一格，辅流是屏幕共享，audio 是全场混音。
public enum LiveStreamType: String {
    case main
    case aux
    case audio
}

/// Atomic immutable projection published from the Core event queue. UI must subscribe instead of
/// synchronously crossing the Core/FFI boundary from a render callback.
public struct SdkSnapshot {
    public internal(set) var continuation: ContinuationView?
    public let classroomView: ClassroomView
    public internal(set) var generation: UInt64
    public let classInfo: ClassInfo?
    public let onStageUsers: [StageUser]
    public let members: [ClassroomMember]
    public let memberCount: UInt32
    public let membersNextCursor: String?
    public let interactionPolicy: [ActionAvailability]
    public let imMessages: [ImMessage]
    public let imHistoryState: ImHistoryState
    /// Core 判定的可绑远端视频用户；绑定路径只查表，不自行推导。
    public let bindableRemoteVideoUserIds: Set<String>
    /// Core 判定的本地预览是否可绑；不得自行对 localVideoMuted 取反。
    public let localVideoBindable: Bool
    /// 本端是否正在推屏幕共享辅流；以 Vendor 采集回执为准。
    public let localScreenSharing: Bool
    /// Core 判定的可绑远端屏幕共享用户，语义同 `bindableRemoteVideoUserIds`。
    public let bindableRemoteScreenUserIds: Set<String>
    /// 进行中且本人未上台：不进 RTC，改拉台上直播流。
    public let needLive: Bool
    /// 台下该播哪几路；台上为空。一人一路主流，屏幕共享一路辅流，另加一路纯音频混流。
    public let liveStreams: [LiveStream]
    /// 与 `classroom.live_relay_changed` 对齐的集合版本，用于丢弃迟到下发。
    public let liveRelayVersion: Int64

    public init(
        continuation: ContinuationView? = nil,
        classroomView: ClassroomView = .empty,
        generation: UInt64 = 0,
        classInfo: ClassInfo? = nil,
        onStageUsers: [StageUser] = [],
        members: [ClassroomMember] = [],
        memberCount: UInt32 = 0,
        membersNextCursor: String? = nil,
        interactionPolicy: [ActionAvailability] = [],
        imMessages: [ImMessage] = [],
        imHistoryState: ImHistoryState = ImHistoryState(),
        bindableRemoteVideoUserIds: Set<String> = [],
        localVideoBindable: Bool = false,
        localScreenSharing: Bool = false,
        bindableRemoteScreenUserIds: Set<String> = [],
        needLive: Bool = false,
        liveStreams: [LiveStream] = [],
        liveRelayVersion: Int64 = 0
    ) {
        self.continuation = continuation
        self.classroomView = classroomView
        self.generation = generation
        self.classInfo = classInfo
        self.onStageUsers = onStageUsers
        self.members = members
        self.memberCount = memberCount
        self.membersNextCursor = membersNextCursor
        self.interactionPolicy = interactionPolicy
        self.imMessages = imMessages
        self.imHistoryState = imHistoryState
        self.bindableRemoteVideoUserIds = bindableRemoteVideoUserIds
        self.localVideoBindable = localVideoBindable
        self.localScreenSharing = localScreenSharing
        self.bindableRemoteScreenUserIds = bindableRemoteScreenUserIds
        self.needLive = needLive
        self.liveStreams = liveStreams
        self.liveRelayVersion = liveRelayVersion
    }
}

public struct JoinSuccessTeacher: Codable {
    public let userId: String
    public var displayName: String?
    public var avatarUrl: String?

    public init(userId: String, displayName: String? = nil, avatarUrl: String? = nil) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

public struct JoinSuccessClassroom: Codable {
    public let classroomId: String
    public var name: String?
    public var status: String?
    public var serverTime: String?
    public var startsAt: String?
    public var actualStartedAt: String?
    public var teacher: JoinSuccessTeacher?

    public init(
        classroomId: String,
        name: String? = nil,
        status: String? = nil,
        serverTime: String? = nil,
        startsAt: String? = nil,
        actualStartedAt: String? = nil,
        teacher: JoinSuccessTeacher? = nil
    ) {
        self.classroomId = classroomId
        self.name = name
        self.status = status
        self.serverTime = serverTime
        self.startsAt = startsAt
        self.actualStartedAt = actualStartedAt
        self.teacher = teacher
    }
}

public struct JoinSuccessSelf: Codable {
    public let userId: String
    public var displayName: String?
    public var avatarUrl: String?
    public var role: String?
    public var stageStatus: String?
    public var canUseMicrophone: Bool?
    public var canUseCamera: Bool?
    public var canSendMessage: Bool?
    public var canUseWhiteboard: Bool?
    public var canScreenShare: Bool?

    public init(
        userId: String,
        displayName: String? = nil,
        avatarUrl: String? = nil,
        role: String? = nil,
        stageStatus: String? = nil,
        canUseMicrophone: Bool? = nil,
        canUseCamera: Bool? = nil,
        canSendMessage: Bool? = nil,
        canUseWhiteboard: Bool? = nil,
        canScreenShare: Bool? = nil
    ) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.role = role
        self.stageStatus = stageStatus
        self.canUseMicrophone = canUseMicrophone
        self.canUseCamera = canUseCamera
        self.canSendMessage = canSendMessage
        self.canUseWhiteboard = canUseWhiteboard
        self.canScreenShare = canScreenShare
    }
}

public struct JoinSuccessWhiteboard: Codable {
    public let token: String
    public let roomId: String
    public let userId: String
    public let appId: String
    public var role: String?
    public var expiresIn: Int64?
    public var expiresAt: String?

    public init(
        token: String,
        roomId: String,
        userId: String,
        appId: String,
        role: String? = nil,
        expiresIn: Int64? = nil,
        expiresAt: String? = nil
    ) {
        self.token = token
        self.roomId = roomId
        self.userId = userId
        self.appId = appId
        self.role = role
        self.expiresIn = expiresIn
        self.expiresAt = expiresAt
    }
}

/// Host join 成功后对外快照（不含 IM Token / RTC UserSig；whiteboard 供 UI Kit 初始化 DrawsKit）
public struct JoinSuccessInfo: Codable {
    public let classroom: JoinSuccessClassroom
    public let selfInfo: JoinSuccessSelf
    public let onStageUsers: [StageUser]
    public let classInfo: ClassInfo
    public var whiteboard: JoinSuccessWhiteboard?

    public init(
        classroom: JoinSuccessClassroom,
        selfInfo: JoinSuccessSelf,
        onStageUsers: [StageUser],
        classInfo: ClassInfo,
        whiteboard: JoinSuccessWhiteboard? = nil
    ) {
        self.classroom = classroom
        self.selfInfo = selfInfo
        self.onStageUsers = onStageUsers
        self.classInfo = classInfo
        self.whiteboard = whiteboard
    }
}

public struct MyStageStatus: Codable {
    public let onStage: Bool
    public var handRaised: Bool?

    public init(onStage: Bool, handRaised: Bool? = nil) {
        self.onStage = onStage
        self.handRaised = handRaised
    }
}

/// 进课阶段，对齐 Core `JoinPhase`。
public enum JoinPhase: String, Codable {
    case idle
    case backendJoining = "backend_joining"
    case domainsInitializing = "domains_initializing"
    case joined
    case unwinding

    init(wire: String) {
        self = JoinPhase(rawValue: wire) ?? .idle
    }
}

/// 单个能力域的推进状态，对齐 Core `DomainState`。
public enum DomainState: String, Codable {
    case disabled, pending, ready, failed

    init(wire: String) {
        self = DomainState(rawValue: wire) ?? .disabled
    }
}

/// 进课进度。`onJoinSuccess` 只在必要域就绪时回调一次；白板、RTC 这类可选域的推进
/// 靠本结构单独暴露，UI 才能只对失败的那一块做占位与重试。
public struct JoinProgress: Codable {
    public let phase: JoinPhase
    public let im: DomainState
    public let whiteboard: DomainState
    public let rtc: DomainState

    public init(phase: JoinPhase, im: DomainState, whiteboard: DomainState, rtc: DomainState) {
        self.phase = phase
        self.im = im
        self.whiteboard = whiteboard
        self.rtc = rtc
    }
}

/// Core 下发的白板凭证；`nil` 表示本次课堂不需要白板或白板已关闭。
public struct WhiteboardCredentials: Codable {
    public let mediaSessionId: String
    public let appId: String
    public let roomId: String
    public let userId: String
    public let token: String
    /// 白板 sdk-api 根地址，来自 join `whiteboard.serverHost`，按部署环境下发。
    public let serverHost: String
    public var role: String?
    public var expiresAt: String?

    public init(
        mediaSessionId: String,
        appId: String,
        roomId: String,
        userId: String,
        token: String,
        serverHost: String,
        role: String? = nil,
        expiresAt: String? = nil
    ) {
        self.mediaSessionId = mediaSessionId
        self.appId = appId
        self.roomId = roomId
        self.userId = userId
        self.token = token
        self.serverHost = serverHost
        self.role = role
        self.expiresAt = expiresAt
    }
}

public struct WhiteboardSyncReloadRequest: Codable, Equatable {
    public let coursewareId: String
    public let serverSeq: Int64

    public init(coursewareId: String, serverSeq: Int64) {
        self.coursewareId = coursewareId
        self.serverSeq = serverSeq
    }
}

public struct WhiteboardRecoveryRequest: Codable, Equatable {
    public let roomId: String
    public let generation: Int64

    public init(roomId: String, generation: Int64) {
        self.roomId = roomId
        self.generation = generation
    }
}

/// 占位：课件 metadata 等 object 字段
public struct AnyCodable: Codable {}
