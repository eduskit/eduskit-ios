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
            data: obj["data"] as? [String: Any] ?? [:],
            extras: obj.filter { !classroomImSignalEnvelopeKeys.contains($0.key) }
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
        let hostGeneration = currentHostEffectGeneration()
        imConnectionGeneration = generation
        let adapter = createOpenImIosAdapter(
            options: OpenImIosAdapterOptions(
                onSignal: { [weak self] envelope in
                    guard self?.currentHostEffectGeneration() == hostGeneration else { return }
                    self?.handleImSignal(envelope, classroomId: classroomId)
                },
                onMessage: { [weak self] message in
                    guard self?.currentHostEffectGeneration() == hostGeneration else { return }
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
                    guard self?.currentHostEffectGeneration() == hostGeneration else { return }
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
        } catch {
            throw failImConnect(phase: "im.login_failed", classroomId: classroomId, error: error)
        }
        do {
            guard currentHostEffectGeneration() == hostGeneration else { adapter.destroy(); return }
            NSLog("[edusdk] IM login ok classroomId=%@", classroomId)
            try adapter.joinClassroomGroup(classroomId: classroomId)
            guard currentHostEffectGeneration() == hostGeneration else { adapter.destroy(); return }
            NSLog("[edusdk] IM joinClassroomGroup ok classroomId=%@", classroomId)
        } catch {
            throw failImConnect(phase: "im.group_join_failed", classroomId: classroomId, error: error)
        }
        #else
        throw SdkError(code: .imProviderError, message: "OpenIMCore is not linked")
        #endif
    }

    private func failImConnect(phase: String, classroomId: String, error: Error) -> Error {
        let message = error.localizedDescription
        NSLog("[edusdk] %@ classroomId=%@: %@", phase, classroomId, message)
        let sdkErr = SdkError(code: .imProviderError, message: "\(phase): \(message)")
        // Core receives the failure receipt and owns bounded recovery / terminal errors.
        teardownIm()
        return sdkErr
    }

    /// HostEffect 的可靠发送路径：失败必须抛出，Core 才能按 IM 域处理。
    func sendTextMessage(_ content: String) throws -> [String: Any] {
        #if canImport(OpenIMCore)
        guard let adapter = imAdapter as? OpenImIosAdapter else {
            throw SdkError(code: .imProviderError, message: "IM classroom group is not ready")
        }
        let message = try adapter.sendTextMessage(content)
        let sentAt: Any = message.sentAt.map { NSNumber(value: $0) as Any } ?? NSNull()
        return ["message_id": message.id, "sent_at": sentAt]
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
        // 顶层未知字段先写，已知字段随后覆盖，保证平台搬运不会改写协议语义
        var obj: [String: Any] = envelope.extras.filter {
            !classroomImSignalEnvelopeKeys.contains($0.key)
        }
        obj["signalId"] = envelope.signalId
        obj["type"] = envelope.type
        obj["data"] = envelope.data
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
