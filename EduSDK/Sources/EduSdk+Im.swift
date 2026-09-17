import Foundation

#if canImport(OpenIMCore)
import OpenIMCore
#endif

extension EduSdk {
    /// HostEffect 的可靠发送路径：仅在 OpenIM 真正回调成功后才向 Core 报完成。
    func executeWhiteboardEnvelope(_ json: String) throws {
        #if canImport(OpenIMCore)
        guard let adapter = imAdapter as? OpenImIosAdapter else {
            throw SdkError(code: .providerError, message: "IM classroom group is not ready")
        }
        guard let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let signalId = obj["signalId"] as? String,
              let type = obj["type"] as? String else {
            throw SdkError(code: .providerError, message: "invalid whiteboard signal envelope")
        }
        let envelope = ClassroomImSignalEnvelope(
            v: obj["v"] as? Int,
            signalId: signalId,
            type: type,
            classroomId: obj["classroomId"] as? String,
            appId: obj["appId"] as? String,
            ts: obj["ts"] as? String,
            data: obj["data"] as? [String: Any] ?? [:]
        )
        try adapter.sendClassroomSignal(envelope)
        #else
        throw SdkError(code: .providerError, message: "OpenIMCore is not linked")
        #endif
    }

    /// Host IM 编排：login → joinGroup；信令进 Core，文本走 onImMessageReceived。
    /// Adapter 源码编进 EduSDK 模块（ImOpenim/）；Vendor 由 Pod 透传，业务无需单独引入。
    func connectImEffect(
        generation: UInt64,
        apiAddr: String,
        wsAddr: String,
        platformId: Int,
        userId: String,
        token: String,
        classroomId: String,
    ) throws {
        #if canImport(OpenIMCore)
        guard !token.isEmpty, !apiAddr.isEmpty, !wsAddr.isEmpty, !userId.isEmpty else {
            throw SdkError(code: .imProviderError, message: "IM effect is missing credentials")
        }
        NSLog(
            "[edusdk] join ok; init IM adapter classroomId=%@ userId=%@ apiAddr=%@",
            classroomId,
            userId,
            apiAddr
        )
        teardownIm()
        imConnectionGeneration = generation
        let adapter = createOpenImIosAdapter(
            options: OpenImIosAdapterOptions(
                onSignal: { [weak self] envelope in
                    self?.handleImSignal(envelope, classroomId: classroomId)
                },
                onMessage: { [weak self] message in
                    NSLog("[edusdk] IM chat message id=%@ sender=%@", message.id, message.senderId)
                    self?.applyImMessage(
                        id: message.id,
                        senderId: message.senderId,
                        content: message.content,
                        sentAt: message.sentAt ?? Int64(Date().timeIntervalSince1970 * 1000),
                        conversationId: classroomId
                    )
                },
                onError: { [weak self] err in
                    let sdkErr = SdkError(code: .imProviderError, message: err.message)
                    DispatchQueue.main.async {
                        self?.errorListeners.forEach { $0(sdkErr) }
                    }
                },
                onConnection: { [weak self] status in
                    self?.dispatchImLifecycleEvent(["type": "im.connection", "generation": generation, "status": status])
                }
            )
        )
        imAdapter = adapter
        do {
            NSLog("[edusdk] IM login start classroomId=%@ userId=%@", classroomId, userId)
            try adapter.login(
                params: OpenImLoginParams(
                    apiAddr: apiAddr,
                    wsAddr: wsAddr,
                    platformId: platformId,
                    userId: userId,
                    token: token
                )
            )
            NSLog("[edusdk] IM login ok classroomId=%@", classroomId)
            try adapter.joinClassroomGroup(classroomId: classroomId)
            NSLog("[edusdk] IM joinClassroomGroup ok classroomId=%@", classroomId)
        } catch {
            let message = error.localizedDescription
            NSLog("[edusdk] IM connect failed classroomId=%@: %@", classroomId, message)
            let sdkErr = SdkError(code: .imProviderError, message: "IM connect failed: \(message)")
            DispatchQueue.main.async { [weak self] in
                self?.errorListeners.forEach { $0(sdkErr) }
            }
            teardownIm()
            throw error
        }
        #else
        throw SdkError(code: .imProviderError, message: "OpenIMCore is not linked")
        #endif
    }

    /// HostEffect 的可靠发送路径：失败必须抛出，Core 才能按 IM 域处理。
    func sendTextMessage(_ content: String) throws {
        #if canImport(OpenIMCore)
        guard let adapter = imAdapter as? OpenImIosAdapter,
              let conversationId = classroomId else {
            throw SdkError(code: .imProviderError, message: "IM classroom group is not ready")
        }
        try adapter.sendTextMessage(content)
        let userId = (try? withCore { try core.backendSnapshot().localUserId }) ?? "local"
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        applyImMessage(
            id: "local:\(userId):\(now)",
            senderId: userId,
            content: content,
            sentAt: now,
            conversationId: conversationId
        )
        #else
        throw SdkError(code: .imProviderError, message: "OpenIMCore is not linked")
        #endif
    }

    func applyImMessage(id: String, senderId: String, content: String, sentAt: Int64, conversationId: String) {
        let payload: [String: Any] = [
            "type": "im.message",
            "data": [
                "id": id,
                "conversation_id": conversationId,
                "sender_id": senderId,
                "content": content,
                "sent_at": sentAt,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        try? withCore { try core.applyProviderEvent(domain: "im", payloadJson: json) }
        pumpEvents()
    }

    func teardownIm() {
        imConnectionGeneration = nil
        imRecoveryWorkItem?.cancel()
        imRecoveryWorkItem = nil
        #if canImport(OpenIMCore)
        guard let adapter = imAdapter as? OpenImIosAdapter else {
            imAdapter = nil
            return
        }
        imAdapter = nil
        adapter.destroy()
        #else
        imAdapter = nil
        #endif
    }

    #if canImport(OpenIMCore)
    private func handleImSignal(_ envelope: ClassroomImSignalEnvelope, classroomId: String) {
        if let signalClassroomId = envelope.classroomId, !signalClassroomId.isEmpty,
           let current = self.classroomId, signalClassroomId != current {
            NSLog(
                "[edusdk] IM signal ignored (classroom mismatch) type=%@ signalId=%@",
                envelope.type,
                envelope.signalId
            )
            return
        }
        if envelope.type == ClassroomImSignalType.presence {
            // presence 一条可含多名成员，日志只留 eduUserId，避免刷屏
            let eduUserIds = (envelope.data["members"] as? [Any])?
                .compactMap { ($0 as? [String: Any])?["eduUserId"] as? String }
                .joined(separator: ",") ?? ""
            NSLog(
                "[edusdk] IM signal → Core type=%@ signalId=%@ members=%@",
                envelope.type,
                envelope.signalId,
                eduUserIds
            )
        } else {
            NSLog(
                "[edusdk] IM signal → Core type=%@ signalId=%@",
                envelope.type,
                envelope.signalId
            )
        }
        do {
            try withCore {
                try core.applyProviderEvent(domain: "im", payloadJson: envelopeToJson(envelope))
            }
            pumpEvents()
        } catch {
            NSLog(
                "[edusdk] IM signal rejected by Core type=%@ signalId=%@: %@",
                envelope.type,
                envelope.signalId,
                error.localizedDescription
            )
        }
    }

    private func envelopeToJson(_ envelope: ClassroomImSignalEnvelope) -> String {
        var obj: [String: Any] = [
            "signalId": envelope.signalId,
            "type": envelope.type,
            "data": envelope.data,
        ]
        if let v = envelope.v { obj["v"] = v }
        if let classroomId = envelope.classroomId { obj["classroomId"] = classroomId }
        if let appId = envelope.appId { obj["appId"] = appId }
        if let ts = envelope.ts { obj["ts"] = ts }
        if let senderId = envelope.senderId, !senderId.isEmpty { obj["senderId"] = senderId }
        guard let data = try? JSONSerialization.data(withJSONObject: obj),
              let str = String(data: data, encoding: .utf8) else {
            return "{\"signalId\":\"\(envelope.signalId)\",\"type\":\"\(envelope.type)\"}"
        }
        return str
    }
    #endif
}
