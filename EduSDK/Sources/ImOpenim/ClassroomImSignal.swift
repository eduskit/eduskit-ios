import Foundation

/// 与 edu_service CLASSROOM_IM_SIGNAL_DESC 对齐
public let CLASSROOM_IM_SIGNAL_DESC = "eduskit.classroom.signal"

/// 与 edu_service ClassroomImSignalType 对齐
public enum ClassroomImSignalType {
    public static let started = "classroom.started"
    public static let ended = "classroom.ended"
    public static let expired = "classroom.expired"
    public static let updated = "classroom.updated"
    /// 成员增量复用通道：进离房、上台、能力、设备状态
    public static let presence = "classroom.presence"
    /// 成员字段增量：麦克风/摄像头/权限等，水位在信封顶层的 ordering
    public static let memberFields = "classroom.member_fields"
    public static let whiteboardCoursewareAdded = "classroom.whiteboard_courseware_added"
    public static let mediaControl = "classroom.media_control"
    public static let whiteboardSync = "whiteboard.sync"
    public static let whiteboardSyncChunk = "whiteboard.sync_chunk"
    public static let whiteboardLiveStroke = "whiteboard.live_stroke"
    public static let whiteboardMedia = "whiteboard.media"

}

/// presence 成员条目内的 family 水位；主体恒为该成员本人
public struct ClassroomPresenceOrdering: Equatable {
    public var family: String
    public var generation: String
    public var revision: String

    public init(family: String, generation: String, revision: String) {
        self.family = family
        self.generation = generation
        self.revision = revision
    }

    var jsonObject: [String: Any] {
        [
            "family": family,
            "generation": generation,
            "revision": revision,
        ]
    }
}

/// 课堂信令信封（Desc === eduskit.classroom.signal）
public struct ClassroomImSignalEnvelope: Equatable {
    public var v: Int?
    public var signalId: String
    public var type: String
    public var classroomId: String?
    public var appId: String?
    public var ts: String?
    /// 接收侧由 IM SDK 注入，发送侧不得信任业务 payload 自报身份。
    public var senderId: String?
    public var data: [String: Any]
    /// 本层不认识的信封顶层字段，原样透传给 Core。
    ///
    /// `classroom.member_fields` 的水位 `ordering` 就在顶层：平台若只搬运已知字段，
    /// Core 取不到 ordering 会把整条判成协议不符，麦克风/摄像头/权限增量全部静默失效。
    /// 新增顶层字段不应再要求各平台跟着改一遍。
    public var extras: [String: Any]

    public init(
        v: Int? = nil,
        signalId: String,
        type: String,
        classroomId: String? = nil,
        appId: String? = nil,
        ts: String? = nil,
        senderId: String? = nil,
        data: [String: Any] = [:],
        extras: [String: Any] = [:]
    ) {
        self.v = v
        self.signalId = signalId
        self.type = type
        self.classroomId = classroomId
        self.appId = appId
        self.ts = ts
        self.senderId = senderId
        self.data = data
        self.extras = extras
    }

    public static func == (lhs: ClassroomImSignalEnvelope, rhs: ClassroomImSignalEnvelope) -> Bool {
        lhs.v == rhs.v
            && lhs.signalId == rhs.signalId
            && lhs.type == rhs.type
            && lhs.classroomId == rhs.classroomId
            && lhs.appId == rhs.appId
            && lhs.ts == rhs.ts
            && lhs.senderId == rhs.senderId
    }
}

/// 信封顶层的已知字段。其余键进 `ClassroomImSignalEnvelope.extras` 透传
public let classroomImSignalEnvelopeKeys: Set<String> = [
    "v",
    "signalId",
    "type",
    "classroomId",
    "appId",
    "ts",
    "senderId",
    "data",
]

/// 非信令聊天消息（文本等）
public struct OpenImChatMessage: Equatable {
    public var id: String
    public var senderId: String
    public var content: String
    public var sentAt: Int64?
    public var classroomId: String?

    public init(
        id: String,
        senderId: String,
        content: String,
        sentAt: Int64? = nil,
        classroomId: String? = nil
    ) {
        self.id = id
        self.senderId = senderId
        self.content = content
        self.sentAt = sentAt
        self.classroomId = classroomId
    }
}

public struct OpenImError {
    public var code: Any?
    public var message: String

    public init(code: Any? = nil, message: String) {
        self.code = code
        self.message = message
    }
}

public struct OpenImLoginParams {
    public var apiAddr: String
    public var wsAddr: String
    public var platformId: Int
    public var userId: String
    public var token: String

    public init(apiAddr: String, wsAddr: String, platformId: Int, userId: String, token: String) {
        self.apiAddr = apiAddr
        self.wsAddr = wsAddr
        self.platformId = platformId
        self.userId = userId
        self.token = token
    }
}
