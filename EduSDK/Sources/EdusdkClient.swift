import Foundation

func uiFeedback(requestJson: String) -> String {
    preconditionFailure("UI feedback policy requires the generated Rust binding")
}

func nativeLiveLicencePrepare(url: String, key: String) -> String {
    preconditionFailure("Native licence policy requires the generated Rust binding")
}
func nativeLiveLicenceComplete(generation: UInt64, code: Int32, message: String) -> String? {
    preconditionFailure("Native licence policy requires the generated Rust binding")
}

// MARK: - UniFFI 占位（make build-mobile 后由生成代码替换）

enum RoomPhase {
    case idle, joining, inRoom, leaving, reconnecting
}

enum MobileClassPhase {
    case idle, entered, inClass, ended
}

enum MobileClassroomLifecycleStatus {
    case notStarted, inProgress, ended, expired
}

enum MobileClassroomTimerMode {
    case hidden, countdown, elapsed
}

struct ClassroomTimerSnapshot {
    let mode: MobileClassroomTimerMode
    var seconds: UInt64?
}

// 变体与顺序对齐 crates/edusdk-headless/src/lib.rs；make check 会校验。
enum EdusdkEventKind {
    case sessionReady, sessionShutdown, roomJoining, roomJoined, roomLeft
    case joinProgressChanged
    case localAudioMuted, localVideoMuted
    case streamInfoChanged, teacherMutedMyMicrophone, teacherMutedMyCamera
    case classPhaseChanged, classroomLifecycleChanged
    case onStageUsersChanged, raisedHandListChanged, membersChanged, userPermissionsChanged, myStageStatusChanged
    case mediaOpenHintChanged
    case localScreenShareChanged, screenShareUsersChanged
    case livePlaybackStatsUpdated
    case livePlaybackEvent
    case liveChanged
    case whiteboardSyncOutbound, whiteboardSyncReceived
    case whiteboardLiveStrokeOutbound, whiteboardLiveStrokeReceived, whiteboardMediaReceived
    case whiteboardSyncReloadRequested
    case whiteboardRecoveryRequested
    case whiteboardMediaClock
    case imMessageOutbound, imMessageReceived
    case teachingToolsUpdated
    case whiteboardMediaProgramResult
    case error
}

enum ErrorCode {
    case ok, notInitialized, alreadyInitialized, invalidArgument, invalidState
    case roomNotFound, contractMismatch, joinAborted
    case classroomNotStarted, classroomEnded, classroomExpired
    case providerNotRegistered, providerError
    case imProviderError, whiteboardProviderError, rtcProviderError, liveProviderError
    case uiResourceError, notImplemented, `internal`
    case permissionDenied, networkError
}

struct InitConfig {
    let appId: String
    let backendBaseUrl: String
    let rtcProvider: String
    let imProvider: String
    let liveProvider: String
    let whiteboardProvider: String
    var userToken: String? = nil
    // 遥测信封维度；字段必须与生成绑定一致，否则 EduSdk 在 stub 模式下编译不过。
    var deviceId: String? = nil
    var platform: String? = nil
    var sdkVersion: String? = nil
    var appVersion: String? = nil
    var liveSupportsLeb: Bool = false
}

struct RoomState {
    let roomId: String?
    let phase: RoomPhase
    let localAudioMuted: Bool
    let localVideoMuted: Bool
    let bindableRemoteVideoUserIds: [String]
    let localVideoBindable: Bool
    let localScreenSharing: Bool
    let bindableRemoteScreenUserIds: [String]
}

struct ClassroomMemberSnapshot {
    let userId: String
    var role: String?
    var stageStatus: String?
    var joinedAt: String?
    var displayName: String?
    var avatarUrl: String?
    var microphoneStatus: String?
    var cameraStatus: String?
}

struct BackendSnapshot {
    let classroomId: String?
    let classPhase: MobileClassPhase
    let lifecycleStatus: MobileClassroomLifecycleStatus
    let localUserId: String?
    let onStageUserIds: [String]
    let raisedHandUserIds: [String]
    var classroomTitle: String?
    var needLive: Bool
    var members: [ClassroomMemberSnapshot]
    var memberCount: UInt32
    var membersNextCursor: String?
    var toolsJson: String? = nil
    var liveStreams: [LiveStreamSnapshot] = []
    var liveRelayVersion: Int64 = 0
}

struct LiveStreamSnapshot {
    let streamName: String
    let publisherUserId: String
    let streamType: String
    let url: String
    let muted: Bool
    let expiresAt: String
    let playing: Bool
}

struct ErrorInfo {
    let code: ErrorCode
    let message: String
}

struct ImMessageSnapshot {
    let id: String
    let conversationId: String
    let senderId: String
    let content: String
    let sentAt: UInt64
}

/// Stub 抛错（对齐 UniFFI flat EdusdkError.Failure）。
enum EdusdkError: Error {
    case failure(message: String)

    init(code: ErrorCode, message: String) {
        self = .failure(message: "\(code): \(message)")
    }
}

struct MobileRuntimeUpdate {
    let epoch: UInt64
    let revision: UInt64
    let events: [Event]
    let hostEffects: [String]
    let telemetryEffects: [String]
    let backendSnapshot: BackendSnapshot?
    let roomState: RoomState?
    let classroomTimer: ClassroomTimerSnapshot?
    let interactionPolicyJson: String?
    let classroomViewJson: String?
    let mediaOpenHintJson: String?
    let continuationJson: String?
    let imMessages: [ImMessageSnapshot]?
    let imHistoryJson: String?
    let nextWakeDelayMs: UInt64?
    let hasMoreWork: Bool
    let shutdownComplete: Bool
    let shutdownTimedOut: Bool
}

struct Event {
    let kind: EdusdkEventKind
    let roomId: String?
    let muted: Bool?
    let error: ErrorInfo?
    var title: String? = nil
    var classPhase: MobileClassPhase? = nil
    var payloadJson: String? = nil
}

final class EdusdkClient {
    func pollRuntimeUpdate(forceSnapshot: Bool) throws -> MobileRuntimeUpdate {
        throw EdusdkError(code: .notImplemented, message: "Runtime update requires the generated Rust binding")
    }
    private var initialized = false
    private var inRoom = false
    private var roomId: String?
    private var classPhase: MobileClassPhase = .idle
    /// 生命周期状态独立持有：`MobileClassPhase` 把 ended 与 expired 压成一个值，
    /// 从相位反推永远产不出 expired。
    private var lifecycleStatus: MobileClassroomLifecycleStatus = .notStarted
    private var onStage: [String] = []
    private var localUserId: String?
    private var classroomTitle: String?

    func `init`(config: InitConfig) throws {
        initialized = true
    }

    func beginShutdown() throws {
        throw EdusdkError(code: .notImplemented, message: "Runtime shutdown requires the generated Rust binding")
    }

    func shutdown() throws {
        initialized = false
        inRoom = false
        roomId = nil
        classPhase = .idle
        lifecycleStatus = .notStarted
        onStage = []
        localUserId = nil
        classroomTitle = nil
    }

    func joinRoom(roomId: String, userId: String, displayName: String) throws {
        guard initialized else { throw EdusdkError(code: .notInitialized, message: "not initialized") }
        self.roomId = roomId
        inRoom = true
        if classPhase == .idle {
            classPhase = .entered
        }
        if localUserId == nil || localUserId?.isEmpty == true {
            localUserId = userId
        }
    }

    func leaveRoom() throws {
        inRoom = false
        roomId = nil
        classPhase = .idle
        lifecycleStatus = .notStarted
        onStage = []
    }

    func muteAudio(muted: Bool) throws {}

    func muteVideo(muted: Bool) throws {}

    func dismissMediaOpenHint() throws {}

    func startScreenShare() throws {}

    func stopScreenShare() throws {}

    func startClass() throws { classPhase = .inClass; lifecycleStatus = .inProgress }
    func endClass() throws { classPhase = .ended; lifecycleStatus = .ended; onStage = [] }
    func loadMembers(cursor: String) throws {}
    func requestTeachingTools(requestJson: String) throws {}

    func requestWhiteboardMediaProgram(requestJson: String) throws {}
    func whiteboardMediaCleanup(requestJson: String) throws -> String {
        throw EdusdkError(code:.notImplemented,message:"Media cleanup requires the generated native Core binding")
    }
    func requestClassroomContinuation(requestJson: String) throws {}
    func prepareTeachingToolAuthoring(requestJson: String) throws -> String {
        throw EdusdkError(code: .notImplemented, message: "Authoring requires the generated native Core binding")
    }
    func inviteUserOnStage(userId: String) throws {
        if !onStage.contains(userId) { onStage.append(userId) }
    }
    func removeUserFromStage(userId: String) throws { onStage.removeAll { $0 == userId } }
    func userRaiseHand() throws {}
    func userCancelHand() throws {}
    func userLeaveStage() throws {
        if let localUserId { onStage.removeAll { $0 == localUserId } }
    }

    func approveUserOnStage(userId: String) throws { try inviteUserOnStage(userId: userId) }
    func rejectUserOnStage(userId: String) throws {}
    func grantMicrophonePermission(userId: String) throws {}
    func revokeMicrophonePermission(userId: String) throws {}
    func grantCameraPermission(userId: String) throws {}
    func revokeCameraPermission(userId: String) throws {}
    func muteUserMicrophone(userId: String) throws {}
    func muteUserCamera(userId: String) throws {}
    func promptUserOpenMicrophone(userId: String) throws {}
    func promptUserOpenCamera(userId: String) throws {}
    func revokeUserMessagePermission(userId: String) throws {}
    func grantUserMessagePermission(userId: String) throws {}
    func revokeAllMessagePermission() throws {}
    func liftAllMessageMute() throws {}
    func grantWhiteboardPermission(userId: String) throws {}
    func revokeWhiteboardPermission(userId: String) throws {}
    func grantScreenSharePermission(userId: String) throws {}
    func revokeScreenSharePermission(userId: String) throws {}
    func sendWhiteboardSync(payloadJson: String) throws {}
    func sendWhiteboardLiveStroke(payloadJson: String) throws {}
    func sendWhiteboardMedia(payloadJson: String) throws {}
    func sendImMessage(content: String) throws {}
    func loadImMessageHistory(cursor: String?, limit: UInt32) throws { throw EdusdkError.failure(message: "NotImplemented: IM history requires native Core") }
    func imHistoryJson() throws -> String { "{\"loading\":false,\"page\":null,\"error\":null}" }

    func imMessages() throws -> [ImMessageSnapshot] { [] }


    // stub 不编排副作用；签名必须与生成绑定一致，否则 EduSdk 在 stub 模式下编译不过。

    func completeHostEffect(resultJson: String) throws {}


    func completeTelemetryEffect(resultJson: String) {}

    func flushTelemetry() {}

    func roomState() throws -> RoomState {
        RoomState(
            roomId: roomId,
            phase: inRoom ? .inRoom : .idle,
            localAudioMuted: false,
            localVideoMuted: false,
            bindableRemoteVideoUserIds: [],
            localVideoBindable: false,
            localScreenSharing: false,
            bindableRemoteScreenUserIds: []
        )
    }

    func backendSnapshot() throws -> BackendSnapshot {
        BackendSnapshot(
            classroomId: roomId,
            classPhase: classPhase,
            lifecycleStatus: lifecycleStatus,
            localUserId: localUserId,
            onStageUserIds: onStage,
            raisedHandUserIds: [],
            classroomTitle: classroomTitle,
            needLive: false,
            members: [],
            memberCount: 0,
            membersNextCursor: nil
        )
    }

    /// Stub 没有权限裁决能力，必须 fail-closed 返回完整动作表，
    /// 否则 UI 会把“策略缺失”误读成“没有任何限制”。
    /// 动作名与 schema/edusdk-sdk.yaml 的 ClassroomAction 由 validate-stub-parity 守门。
    func interactionPolicyJson() throws -> String {
        let items = Self.failClosedActions.map {
            "{\"action\":\"\($0)\",\"visible\":true,\"available\":false,\"reason\":\"capability_not_ready\"}"
        }
        return "[" + items.joined(separator: ",") + "]"
    }

    /// schema/edusdk-sdk.yaml 的 ClassroomAction 全集。
    private static let failClosedActions = [
        "start_class", "end_class", "send_message", "use_microphone", "use_camera",
        "raise_hand", "manage_own_stage", "manage_stage", "manage_remote_media",
        "manage_permissions", "edit_whiteboard", "share_screen", "operate_courseware",
    ]
    func memberActionPolicyJson(userId: String) throws -> String { "[]" }
    func loadMemberPermissions(userId: String) throws {}

    func mediaOpenHintJson() throws -> String { "{\"visible\":false,\"audience\":\"student\"}" }

    func classroomViewJson() throws -> String { #"{"runtime":{"mode":"active","resources":{},"canLoadHistory":true,"canInspectDevices":true,"historyNotice":null},"chatMessages":[],"teacherVideoStage":false,"teacher":null,"participants":[],"memberDirectory":[],"toolCatalog":[],"coursewareItems":[],"screenPresenter":null,"handRaised":false,"networkStatus":"unknown","emptySeatCount":0,"canManageStage":false,"classroomKind":""}"# }

    func classroomTimer() throws -> ClassroomTimerSnapshot {
        ClassroomTimerSnapshot(mode: .hidden, seconds: nil)
    }

    /// Host join 入口（对齐 Web applyBackendJoin）。
    func applyBackendJoin(payloadJson: String) throws {
        guard initialized else { throw EdusdkError(code: .notInitialized, message: "not initialized") }
        guard let data = payloadJson.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // 回退粗解析
            if let cid = extractNested(payloadJson, objectKey: "classroom", field: "classroomId") {
                roomId = cid
            }
            classroomTitle = extractNested(payloadJson, objectKey: "classroom", field: "name")
            classPhase = .entered
            return
        }
        if let classroom = root["classroom"] as? [String: Any] {
            if let cid = classroom["classroomId"] as? String, !cid.isEmpty {
                roomId = cid
            }
            if let name = classroom["name"] as? String, !name.isEmpty {
                classroomTitle = name
            }
            classPhase = Self.mapClassroomStatus(classroom["status"] as? String)
            lifecycleStatus = Self.mapClassroomLifecycle(classroom["status"] as? String)
        }
        if let session = root["session"] as? [String: Any],
           let uid = session["eduUserId"] as? String, !uid.isEmpty {
            localUserId = uid
        }
        onStage = []
        if let members = root["onStageMembers"] as? [[String: Any]] {
            for m in members {
                if let id = m["eduUserId"] as? String, !id.isEmpty, !onStage.contains(id) {
                    onStage.append(id)
                }
            }
        }
    }

    private static func mapClassroomStatus(_ status: String?) -> MobileClassPhase {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "live": return .inClass
        case "ended", "expired": return .ended
        default: return .entered
        }
    }

    private static func mapClassroomLifecycle(_ status: String?) -> MobileClassroomLifecycleStatus {
        switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "live": return .inProgress
        case "ended": return .ended
        case "expired": return .expired
        default: return .notStarted
        }
    }

    /// Host IM 信令入口（对齐 Web core.applyProviderEvent）。
    func applyProviderEvent(domain: String, payloadJson: String) throws {
        guard domain == "im" else { return }
        guard let type = extractJsonString(payloadJson, key: "type") else { return }
        switch type {
        case "classroom.started":
            classPhase = .inClass
            lifecycleStatus = .inProgress
        case "classroom.ended", "classroom.expired":
            classPhase = .ended
            lifecycleStatus = type == "classroom.expired" ? .expired : .ended
            onStage = []
        default:
            break
        }
    }

    private func extractNested(_ json: String, objectKey: String, field: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\"\(objectKey)\"\\s*:\\s*\\{([^}]*)\\}",
            options: []
        ) else { return nil }
        let range = NSRange(json.startIndex..<json.endIndex, in: json)
        guard let match = regex.firstMatch(in: json, options: [], range: range),
              match.numberOfRanges > 1,
              let blockRange = Range(match.range(at: 1), in: json) else {
            return nil
        }
        return extractJsonString("{\(json[blockRange])}", key: field)
    }

    private func extractArrayBlock(_ json: String, key: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\"\(key)\"\\s*:\\s*\\[(.*?)]",
            options: [.dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(json.startIndex..<json.endIndex, in: json)
        guard let match = regex.firstMatch(in: json, options: [], range: range),
              match.numberOfRanges > 1,
              let blockRange = Range(match.range(at: 1), in: json) else {
            return nil
        }
        return String(json[blockRange])
    }

    private func extractAllJsonStrings(_ json: String, key: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "\"\(key)\"\\s*:\\s*\"([^\"]+)\"",
            options: []
        ) else { return [] }
        let range = NSRange(json.startIndex..<json.endIndex, in: json)
        return regex.matches(in: json, options: [], range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let valueRange = Range(match.range(at: 1), in: json) else { return nil }
            return String(json[valueRange])
        }
    }

    private func extractJsonString(_ json: String, key: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\"\(key)\"\\s*:\\s*\"([^\"]+)\"",
            options: []
        ) else { return nil }
        let range = NSRange(json.startIndex..<json.endIndex, in: json)
        guard let match = regex.firstMatch(in: json, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: json) else {
            return nil
        }
        return String(json[valueRange])
    }
}
