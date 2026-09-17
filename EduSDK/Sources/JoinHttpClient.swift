import Foundation

struct HostHttpFailure: LocalizedError {
    let statusCode: Int
    let message: String
    var errorDescription: String? { message }
}

/// Host 侧调用 sdk-api：`POST /v1/classrooms/:id/join`。
enum JoinHttpClient {
    private enum Tokens {
        static let timeoutSeconds: TimeInterval = 30
        static let codeField = "code"
        static let messageField = "message"
        static let traceIdField = "traceId"
        static let traceIdAltField = "trace_id"
        static let traceIdHeader = "x-trace-id"
    }

    struct JoinWhiteboardCreds {
        let token: String
        let roomId: String
        let userId: String
        let role: String?
        let expiresIn: Int64?
        let expiresAt: String?
        let appId: String
    }

    struct JoinTeacher {
        let userId: String
        let displayName: String?
        let avatarUrl: String?
    }

    struct JoinClassroom {
        let classroomId: String
        let name: String?
        let status: String?
        let startsAt: String?
        let endsAt: String?
        let actualStartedAt: String?
        let teacher: JoinTeacher?
    }

    struct JoinSelf {
        let role: String?
        let stageStatus: String?
        let canUseMicrophone: Bool?
        let canUseCamera: Bool?
        let canSendMessage: Bool?
        let canUseWhiteboard: Bool?
        let canScreenShare: Bool?
    }

    struct JoinSession {
        let eduUserId: String?
        let nickname: String?
        let avatar: String?
    }

    struct JoinOnStageMember {
        let userId: String
        let displayName: String?
    }

    struct JoinPayload {
        let session: JoinSession
        let classroom: JoinClassroom
        let selfMember: JoinSelf
        let onStageMembers: [JoinOnStageMember]
        let whiteboard: JoinWhiteboardCreds?
        let coursewares: [Courseware]
        let telemetryIngestUrl: String?
        let serverTime: String?
        let rawDataJson: String

        var eduUserId: String? { session.eduUserId }
    }

    static func executeEffect(
        method: String,
        url: String,
        headers: [[String]],
        body: String?
    ) throws -> Any {
        requireBackgroundThread("executeEffect")
        guard let endpoint = URL(string: url) else {
            throw SdkError(code: .invalidState, message: "invalid effect URL")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = method
        request.timeoutInterval = Tokens.timeoutSeconds
        headers.forEach { pair in
            if pair.count == 2 { request.setValue(pair[1], forHTTPHeaderField: pair[0]) }
        }
        request.httpBody = body?.data(using: .utf8)
        let semaphore = DispatchSemaphore(value: 0)
        var capturedData: Data?
        var capturedResponse: URLResponse?
        var capturedError: Error?
        HostHttpSession.shared.dataTask(with: request) { data, response, error in
            capturedData = data
            capturedResponse = response
            capturedError = error
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + Tokens.timeoutSeconds) != .timedOut else {
            throw SdkError(code: .networkError, message: "effect HTTP timeout")
        }
        if let capturedError { throw capturedError }
        let http = capturedResponse as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let text = capturedData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw HostHttpFailure(
                statusCode: status,
                message: formatHttpErrorMessage(
                    status: status,
                    body: text,
                    headerTraceId: http?.value(forHTTPHeaderField: Tokens.traceIdHeader)
                )
            )
        }
        guard let data = capturedData, !data.isEmpty else { return NSNull() }
        return try JSONSerialization.jsonObject(with: data)
    }

    static func parseJoinEffect(_ object: Any) throws -> JoinPayload {
        let data = try JSONSerialization.data(withJSONObject: object)
        return try parseJoinPayload(String(decoding: data, as: UTF8.self))
    }

    private static func encodePath(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? value
    }

    /// 本文件的 HTTP 都用信号量同步等待，最长阻塞 `Tokens.timeoutSeconds`。
    /// 在主线程调用会把课堂 UI 整体冻住，因此 Debug 直接断言，Release 留下可排查的日志。
    private static func requireBackgroundThread(_ operation: String) {
        guard Thread.isMainThread else { return }
        assertionFailure("JoinHttpClient.\(operation) blocks its caller and must not run on the main thread")
        NSLog("[edusdk] JoinHttpClient.%@ was called on the main thread", operation)
    }

    private static func requestJson(
        backendUrl: String,
        userToken: String,
        path: String,
        method: String
    ) throws -> [String: Any] {
        requireBackgroundThread("requestJson")
        let base = backendUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard let url = URL(string: "\(base)\(path)") else {
            throw SdkError(code: .invalidState, message: "invalid backend URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(userToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Tokens.timeoutSeconds
        if method == "POST" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
        }
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var response: URLResponse?
        var responseError: Error?
        HostHttpSession.shared.dataTask(with: request) { data, result, error in
            responseData = data
            response = result
            responseError = error
            semaphore.signal()
        }.resume()
        guard semaphore.wait(timeout: .now() + Tokens.timeoutSeconds) != .timedOut else {
            throw SdkError(code: .networkError, message: "\(method) \(path) timeout")
        }
        if let responseError {
            throw SdkError(code: .networkError, message: responseError.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        guard (200...299).contains(status) else {
            let text = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            throw SdkError(
                code: .networkError,
                message: formatHttpErrorMessage(
                    status: status,
                    body: text,
                    headerTraceId: http?.value(forHTTPHeaderField: Tokens.traceIdHeader)
                )
            )
        }
        guard let responseData, !responseData.isEmpty,
              let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return [:]
        }
        return try unwrapApiEnvelope(object)
    }

    /// GET /v1/coursewares/:id/manifest?classroomId= → opaque JSON string
    static func fetchCoursewareManifest(
        backendUrl: String,
        userToken: String,
        classroomId: String,
        coursewareId: String
    ) throws -> String {
        requireBackgroundThread("fetchCoursewareManifest")
        let normalizedBase = backendUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        let token = userToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let roomId = classroomId.trimmingCharacters(in: .whitespacesAndNewlines)
        let cwId = coursewareId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBase.isEmpty else {
            throw SdkError(code: .invalidState, message: "backendUrl is required")
        }
        guard !token.isEmpty else {
            throw SdkError(code: .invalidState, message: "userToken is required")
        }
        guard !roomId.isEmpty else {
            throw SdkError(code: .invalidState, message: "classroomId is required")
        }
        guard !cwId.isEmpty else {
            throw SdkError(code: .invalidState, message: "coursewareId is required")
        }

        let encodedCw = cwId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? cwId
        let encodedCls = roomId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? roomId
        guard let url = URL(
            string: "\(normalizedBase)/v1/coursewares/\(encodedCw)/manifest?classroomId=\(encodedCls)"
        ) else {
            throw SdkError(code: .invalidState, message: "invalid courseware manifest URL")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = Tokens.timeoutSeconds

        let semaphore = DispatchSemaphore(value: 0)
        var capturedData: Data?
        var capturedResponse: URLResponse?
        var capturedError: Error?

        HostHttpSession.shared.dataTask(with: request) { data, response, error in
            capturedData = data
            capturedResponse = response
            capturedError = error
            semaphore.signal()
        }.resume()

        if semaphore.wait(timeout: .now() + Tokens.timeoutSeconds) == .timedOut {
            throw SdkError(code: .networkError, message: "coursewareManifest failed: timeout")
        }
        if let capturedError {
            throw SdkError(
                code: .networkError,
                message: "coursewareManifest failed: \(capturedError.localizedDescription)"
            )
        }
        let http = capturedResponse as? HTTPURLResponse
        let code = http?.statusCode ?? 0
        let text = capturedData.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        guard (200...299).contains(code) else {
            throw SdkError(
                code: .networkError,
                message: formatHttpErrorMessage(
                    status: code,
                    body: text,
                    headerTraceId: http?.value(forHTTPHeaderField: Tokens.traceIdHeader)
                )
            )
        }
        if code == 204 || text.isEmpty {
            return "{}"
        }
        guard let data = text.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SdkError(code: .internal, message: "coursewareManifest: invalid JSON response")
        }
        let payload = try unwrapApiEnvelope(root)
        if let d = try? JSONSerialization.data(withJSONObject: payload),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return "{}"
    }

    private static func parseJoinPayload(_ raw: String) throws -> JoinPayload {
        guard let data = raw.data(using: .utf8),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SdkError(code: .internal, message: "join: invalid JSON response")
        }
        var payload = try unwrapApiEnvelope(root)

        let sessionObj = payload["session"] as? [String: Any]
        let session = JoinSession(
            eduUserId: nonEmpty(sessionObj?["eduUserId"] as? String),
            nickname: nonEmpty(sessionObj?["nickname"] as? String),
            avatar: nonEmpty(sessionObj?["avatar"] as? String)
        )

        guard var classroomObj = payload["classroom"] as? [String: Any] else {
            throw SdkError(code: .internal, message: "join: missing classroom")
        }
        guard let classroomId = nonEmpty(classroomObj["classroomId"] as? String) else {
            throw SdkError(code: .internal, message: "join: missing classroom.classroomId")
        }
        let teacherObj = classroomObj["teacher"] as? [String: Any]
        let teacherId = nonEmpty(classroomObj["teacherEduUserId"] as? String)
            ?? nonEmpty(teacherObj?["eduUserId"] as? String)
        let rawStatus = nonEmpty(classroomObj["status"] as? String)
        let startsAt = nonEmpty(classroomObj["startsAt"] as? String)
        let endsAt = nonEmpty(classroomObj["endsAt"] as? String)
        let actualStartedAt = nonEmpty(classroomObj["actualStartedAt"] as? String)
        let effectiveStatus = resolveEffectiveClassroomStatus(
            status: rawStatus,
            startsAt: startsAt,
            endsAt: endsAt
        )
        classroomObj["status"] = effectiveStatus
        payload["classroom"] = classroomObj

        let classroom = JoinClassroom(
            classroomId: classroomId,
            name: nonEmpty(classroomObj["name"] as? String),
            status: effectiveStatus,
            startsAt: startsAt,
            endsAt: endsAt,
            actualStartedAt: actualStartedAt,
            teacher: teacherId.map {
                JoinTeacher(
                    userId: $0,
                    displayName: nonEmpty(teacherObj?["nickname"] as? String),
                    avatarUrl: nonEmpty(teacherObj?["avatar"] as? String)
                )
            }
        )

        let selfObj = payload["self"] as? [String: Any]
        let perms = selfObj?["permissions"] as? [[String: Any]]
        let selfMember = JoinSelf(
            role: nonEmpty(selfObj?["role"] as? String),
            stageStatus: nonEmpty(selfObj?["stageStatus"] as? String),
            canUseMicrophone: permAllowed(perms, key: "microphone"),
            canUseCamera: permAllowed(perms, key: "camera"),
            canSendMessage: permAllowed(perms, key: "chat"),
            canUseWhiteboard: permAllowed(perms, key: "whiteboard"),
            canScreenShare: permAllowed(perms, key: "screen_share")
        )
        NSLog(
            "[edusdk] join self permissions role=%@ stage=%@ microphone=%@ camera=%@ chat=%@ whiteboard=%@ screen_share=%@",
            capabilityLogText(selfMember.role),
            capabilityLogText(selfMember.stageStatus),
            capabilityLogFlag(selfMember.canUseMicrophone),
            capabilityLogFlag(selfMember.canUseCamera),
            capabilityLogFlag(selfMember.canSendMessage),
            capabilityLogFlag(selfMember.canUseWhiteboard),
            capabilityLogFlag(selfMember.canScreenShare)
        )

        var onStage: [JoinOnStageMember] = []
        if let arr = payload["onStageMembers"] as? [[String: Any]] {
            for m in arr {
                guard let id = nonEmpty(m["eduUserId"] as? String) else { continue }
                onStage.append(JoinOnStageMember(
                    userId: id,
                    displayName: nonEmpty(m["nickname"] as? String)
                ))
            }
        }

        var whiteboard: JoinWhiteboardCreds?
        if let wbObj = payload["whiteboard"] as? [String: Any] {
            let token = nonEmpty(wbObj["token"] as? String) ?? ""
            let roomId = nonEmpty(wbObj["roomId"] as? String) ?? ""
            let userId = nonEmpty(wbObj["userId"] as? String) ?? ""
            let appId = nonEmpty(wbObj["appId"] as? String) ?? ""
            if !token.isEmpty, !roomId.isEmpty, !userId.isEmpty, !appId.isEmpty {
                let expiresIn: Int64?
                if let n = wbObj["expiresIn"] as? Int64 {
                    expiresIn = n
                } else if let n = wbObj["expiresIn"] as? Int {
                    expiresIn = Int64(n)
                } else {
                    expiresIn = nil
                }
                whiteboard = JoinWhiteboardCreds(
                    token: token,
                    roomId: roomId,
                    userId: userId,
                    role: nonEmpty(wbObj["role"] as? String),
                    expiresIn: expiresIn,
                    expiresAt: nonEmpty(wbObj["expiresAt"] as? String),
                    appId: appId
                )
            }
        }

        let rawDataJson: String
        if let d = try? JSONSerialization.data(withJSONObject: payload),
           let s = String(data: d, encoding: .utf8) {
            rawDataJson = s
        } else {
            rawDataJson = "{}"
        }

        let coursewares = parseCoursewares(payload["coursewares"] as? [[String: Any]])
        let ingestUrl = nonEmpty((payload["telemetry"] as? [String: Any])?["ingestUrl"] as? String)

        return JoinPayload(
            session: session,
            classroom: classroom,
            selfMember: selfMember,
            onStageMembers: onStage,
            whiteboard: whiteboard,
            coursewares: coursewares,
            telemetryIngestUrl: ingestUrl,
            serverTime: nonEmpty(payload["serverTime"] as? String),
            rawDataJson: rawDataJson
        )
    }

    private static func parseCoursewares(_ list: [[String: Any]]?) -> [Courseware] {
        guard let list else { return [] }
        var out: [Courseware] = []
        for item in list {
            guard let id = nonEmpty(item["coursewareId"] as? String) else { continue }
            let originalName = nonEmpty(item["originalName"] as? String)
            let name = nonEmpty(item["name"] as? String) ?? originalName ?? id
            let progress: Int
            if let n = item["progress"] as? Int {
                progress = n
            } else if let n = item["progress"] as? Double {
                progress = Int(n)
            } else {
                progress = 0
            }
            let sizeBytes: Int64?
            if let n = item["sizeBytes"] as? Int64 {
                sizeBytes = n > 0 ? n : nil
            } else if let n = item["sizeBytes"] as? Int {
                sizeBytes = n > 0 ? Int64(n) : nil
            } else {
                sizeBytes = nil
            }
            out.append(
                Courseware(
                    id: id,
                    name: name,
                    originalName: originalName,
                    format: nonEmpty(item["format"] as? String),
                    status: nonEmpty(item["status"] as? String) ?? "",
                    progress: progress,
                    sizeBytes: sizeBytes,
                    errorMessage: nonEmpty(item["errorMessage"] as? String),
                    wbCoursewareId: nonEmpty(item["wbCoursewareId"] as? String)
                )
            )
        }
        return out
    }

    private static func permAllowed(_ list: [[String: Any]]?, key: String) -> Bool? {
        guard let list else { return nil }
        guard let hit = list.first(where: { ($0["permission"] as? String) == key }) else {
            return nil
        }
        return hit["allowed"] as? Bool
    }

    private static let capabilityUnset = "unset"

    private static func capabilityLogFlag(_ value: Bool?) -> String {
        switch value {
        case .some(true): return "true"
        case .some(false): return "false"
        case .none: return capabilityUnset
        }
    }

    private static func capabilityLogText(_ value: String?) -> String {
        nonEmpty(value) ?? capabilityUnset
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let t = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? nil : t
    }

    private static func formatHttpErrorMessage(
        status: Int,
        body: String,
        headerTraceId: String?
    ) -> String {
        let parsed = body.data(using: .utf8).flatMap {
            try? JSONSerialization.jsonObject(with: $0) as? [String: Any]
        }
        let message = nonEmpty(parsed?[Tokens.messageField] as? String) ?? "HTTP \(status)"
        let code: String
        if let number = parsed?[Tokens.codeField] as? Int {
            code = String(number)
        } else if let text = nonEmpty(parsed?[Tokens.codeField] as? String) {
            code = text
        } else {
            code = String(status)
        }
        let traceId = nonEmpty(parsed?[Tokens.traceIdField] as? String)
            ?? nonEmpty(parsed?[Tokens.traceIdAltField] as? String)
            ?? nonEmpty(headerTraceId)
        var lines = ["\(message)", "\(Tokens.codeField): \(code)"]
        if let traceId {
            lines.append("\(Tokens.traceIdField): \(traceId)")
        }
        return lines.joined(separator: "\n")
    }

    private static func unwrapApiEnvelope(_ body: [String: Any]) throws -> [String: Any] {
        guard body["code"] != nil, body["data"] != nil else { return body }
        let code = body["code"] as? Int ?? -1
        guard code == 0 else {
            let message = nonEmpty(body["message"] as? String) ?? "backend code \(code)"
            let traceId = nonEmpty(body["traceId"] as? String) ?? nonEmpty(body["trace_id"] as? String)
            var lines = [message, "\(Tokens.codeField): \(code)"]
            if let traceId {
                lines.append("\(Tokens.traceIdField): \(traceId)")
            }
            throw SdkError(code: .networkError, message: lines.joined(separator: "\n"))
        }
        return body["data"] as? [String: Any] ?? [:]
    }
}

extension JoinHttpClient.JoinPayload {
    func toJoinSuccessInfo() -> JoinSuccessInfo {
        let classroomId = classroom.classroomId
        let title = classroom.name
        return JoinSuccessInfo(
            classroom: JoinSuccessClassroom(
                classroomId: classroomId,
                name: classroom.name,
                status: classroom.status,
                serverTime: serverTime,
                startsAt: classroom.startsAt,
                actualStartedAt: classroom.actualStartedAt,
                teacher: classroom.teacher.map {
                    JoinSuccessTeacher(
                        userId: $0.userId,
                        displayName: $0.displayName,
                        avatarUrl: $0.avatarUrl
                    )
                }
            ),
            selfInfo: JoinSuccessSelf(
                userId: session.eduUserId ?? "unknown",
                displayName: session.nickname,
                avatarUrl: session.avatar,
                role: selfMember.role,
                stageStatus: selfMember.stageStatus,
                canUseMicrophone: selfMember.canUseMicrophone,
                canUseCamera: selfMember.canUseCamera,
                canSendMessage: selfMember.canSendMessage,
                canUseWhiteboard: selfMember.canUseWhiteboard,
                canScreenShare: selfMember.canScreenShare
            ),
            onStageUsers: {
                var users = onStageMembers.map {
                    StageUser(userId: $0.userId, displayName: $0.displayName, onStage: true)
                }
                if selfMember.stageStatus == "on", let localId = session.eduUserId,
                   !localId.isEmpty, !users.contains(where: { $0.userId == localId }) {
                    users.append(StageUser(userId: localId, displayName: session.nickname, onStage: true))
                }
                return users
            }(),
            classInfo: ClassInfo(
                classroomId: classroomId,
                phase: mapClassroomStatusToPhase(classroom.status),
                lifecycleStatus: mapClassroomLifecycleStatus(classroom.status),
                title: title
            ),
            whiteboard: whiteboard.map {
                JoinSuccessWhiteboard(
                    token: $0.token,
                    roomId: $0.roomId,
                    userId: $0.userId,
                    appId: $0.appId,
                    role: $0.role,
                    expiresIn: $0.expiresIn,
                    expiresAt: $0.expiresAt
                )
            }
        )
    }
}

/// 后台 status 是课堂生命周期唯一真相源；端侧不得按本地时钟推导 expired。
func resolveEffectiveClassroomStatus(
    status: String?,
    startsAt: String? = nil,
    endsAt: String? = nil,
    now: Date = Date(timeIntervalSince1970: 0)
) -> String {
    _ = startsAt
    _ = endsAt
    _ = now
    let raw = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
    return raw.isEmpty ? "pending" : raw
}

/// sdk-api `classroom.status` → ClassPhase（与 Core / Web 对齐）
func mapClassroomStatusToPhase(_ status: String?) -> ClassPhase {
    switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "live": return .inClass
    case "ended", "expired": return .ended
    default: return .entered
    }
}

func mapClassroomLifecycleStatus(_ status: String?) -> ClassroomLifecycleStatus {
    switch status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "live": return .inProgress
    case "ended": return .ended
    case "expired": return .expired
    default: return .notStarted
    }
}
