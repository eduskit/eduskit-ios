import Foundation

/// DrawsKit payload 与 EduSDK Core JSON 同步通道之间的平台 Adapter。
/// 课堂校验、去重、分片与路由仍由 Rust Core 负责。
public final class WhiteboardSyncBridge {
    private var sender: ((String) throws -> Void)?
    private var liveStrokeSender: ((String) throws -> Void)?
    private var mediaSender: ((String) throws -> Void)?
    private var mediaSessionId: String?
    private var sendFailureHandler: ((Error) throws -> Void)?
    private var messageHandler: ((Any) -> Void)?
    private let workerQueue = DispatchQueue(label: "edusdk.whiteboard.bridge")
    private let stateLock = NSLock()
    private var generation: UInt64 = 0
    /// 等待投递的过程笔迹，由 stateLock 保护。
    private var pendingLiveStrokes: [Any] = []
    private var liveStrokeDeliveryScheduled = false

    public init() {}

    public func bindSender(
        _ next: ((String) throws -> Void)?,
        liveStroke: ((String) throws -> Void)? = nil,
        media: ((String) throws -> Void)? = nil,
        onFailure: ((Error) throws -> Void)? = nil
    ) {
        stateLock.lock()
        sender = next
        liveStrokeSender = liveStroke
        mediaSender = media
        sendFailureHandler = onFailure
        stateLock.unlock()
    }

    /// 当前白板媒体会话。播放包只在这个会话里收发。
    public func bindMediaSession(_ sessionId: String?) {
        stateLock.lock()
        mediaSessionId = sessionId.flatMap { $0.isEmpty ? nil : $0 }
        stateLock.unlock()
    }

    public func bindMessageHandler(_ next: ((Any) -> Void)?) {
        stateLock.lock()
        messageHandler = next
        stateLock.unlock()
    }

    public func send(_ payload: Any) {
        stateLock.lock()
        let epoch = generation
        stateLock.unlock()
        workerQueue.async { [weak self] in
            guard let self, self.isCurrent(epoch) else { return }
            if let raw = payload as? String {
                guard let data = raw.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) else { return }
                self.sendObject(object, raw: raw)
                return
            }
            guard JSONSerialization.isValidJSONObject(payload),
                  let data = try? JSONSerialization.data(withJSONObject: payload),
                  let raw = String(data: data, encoding: .utf8) else { return }
            self.sendObject(payload, raw: raw)
        }
    }

    /// 最终 op 入站。频率等于抬笔次数，保留 opId 诊断日志。
    public func receiveSync(_ payloadJson: String) {
        stateLock.lock()
        let epoch = generation
        stateLock.unlock()
        workerQueue.async { [weak self] in
            guard let self, self.isCurrent(epoch),
                  let data = payloadJson.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) else { return }
            let opId = (payload as? [String: Any])?["op_id"] as? String
            let loggedOpId = opId.flatMap { $0.isEmpty ? nil : $0 } ?? "<missing>"
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(epoch) else { return }
                self.stateLock.lock()
                let handler = self.messageHandler
                self.stateLock.unlock()
                NSLog(
                    "[edusdk/whiteboard] whiteboard sync UI → DrawsKit opId=%@ handlerBound=%@",
                    loggedOpId,
                    handler == nil ? "false" : "true"
                )
                handler?(payload)
            }
        }
    }

    /// 过程笔迹入站。
    ///
    /// 与 `receiveSync` 的差别都是为了不让 20–60Hz 的笔迹拖垮主线程：不打诊断日志
    /// （过程笔迹没有 `op_id`，逐包一条 `NSLog` 反而是最贵的一步）；解析在 worker 完成，
    /// 主线程闭包只调 DrawsKit handler；同一批到达的多个包合并成一次主线程投递。
    public func receiveLiveStroke(_ payloadJson: String) {
        stateLock.lock()
        let epoch = generation
        stateLock.unlock()
        workerQueue.async { [weak self] in
            guard let self, self.isCurrent(epoch),
                  let data = payloadJson.data(using: .utf8),
                  let payload = try? JSONSerialization.jsonObject(with: data) else { return }
            self.stateLock.lock()
            self.pendingLiveStrokes.append(payload)
            let alreadyScheduled = self.liveStrokeDeliveryScheduled
            self.liveStrokeDeliveryScheduled = true
            self.stateLock.unlock()
            guard !alreadyScheduled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.drainPendingLiveStrokes(epoch)
            }
        }
    }

    /// 课件播放入站。只把本会话的 payload 交给 DrawsKit，别的会话直接丢掉。
    public func receiveMedia(_ payloadJson: String) {
        stateLock.lock()
        let epoch = generation
        stateLock.unlock()
        workerQueue.async { [weak self] in
            guard let self, self.isCurrent(epoch),
                  let data = payloadJson.data(using: .utf8),
                  let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let incoming = envelope[MediaWire.sessionId] as? String,
                  let payload = envelope[MediaWire.payload]
            else { return }
            self.stateLock.lock()
            let expected = self.mediaSessionId
            self.stateLock.unlock()
            guard let expected, incoming == expected else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isCurrent(epoch) else { return }
                self.stateLock.lock()
                let handler = self.messageHandler
                self.stateLock.unlock()
                handler?(payload)
            }
        }
    }

    public func clear() {
        stateLock.lock()
        generation &+= 1
        sender = nil
        liveStrokeSender = nil
        mediaSender = nil
        mediaSessionId = nil
        sendFailureHandler = nil
        messageHandler = nil
        pendingLiveStrokes.removeAll()
        stateLock.unlock()
    }

    private func drainPendingLiveStrokes(_ epoch: UInt64) {
        stateLock.lock()
        liveStrokeDeliveryScheduled = false
        let stale = generation != epoch
        let handler = messageHandler
        let batch = stale || handler == nil ? [] : pendingLiveStrokes
        pendingLiveStrokes.removeAll()
        stateLock.unlock()
        guard let handler, !batch.isEmpty else { return }
        for payload in batch {
            handler(payload)
        }
    }

    private func sendObject(_ payload: Any, raw: String) {
        guard let object = payload as? [String: Any] else { return }
        if object[MediaWire.type] as? String == MediaWire.messageType {
            sendMedia(object)
            return
        }
        let live = (object["stroke_id"] as? String)?.isEmpty == false
            && (object["phase"] as? String)?.isEmpty == false
        let sync = (object["op_id"] as? String)?.isEmpty == false
            && object["op"] is [String: Any]
        guard live != sync else {
            reportSendFailure(WhiteboardSyncBridgeError.ambiguousPayload)
            return
        }
        stateLock.lock()
        let activeSender = live ? liveStrokeSender : sender
        stateLock.unlock()
        guard let activeSender else { return }
        do {
            try activeSender(raw)
        } catch {
            reportSendFailure(error)
        }
    }

    private func sendMedia(_ object: [String: Any]) {
        stateLock.lock()
        let sessionId = mediaSessionId
        let activeSender = mediaSender
        stateLock.unlock()
        guard let sessionId else {
            reportSendFailure(WhiteboardSyncBridgeError.missingMediaSession)
            return
        }
        guard let activeSender else { return }
        let envelope: [String: Any] = [
            MediaWire.sessionId: sessionId,
            MediaWire.payload: object,
        ]
        guard JSONSerialization.isValidJSONObject(envelope),
              let data = try? JSONSerialization.data(withJSONObject: envelope),
              let raw = String(data: data, encoding: .utf8) else {
            reportSendFailure(WhiteboardSyncBridgeError.missingMediaSession)
            return
        }
        do {
            try activeSender(raw)
        } catch {
            reportSendFailure(error)
        }
    }

    private func reportSendFailure(_ error: Error) {
        stateLock.lock()
        let handler = sendFailureHandler
        stateLock.unlock()
        guard let handler else { return }
        do {
            try handler(error)
        } catch {
            // Last-resort boundary: error reporting must not crash DrawsKit's callback.
        }
    }

    private func isCurrent(_ epoch: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == epoch
    }
}

private enum MediaWire {
    static let messageType = "drawskit_media_status"
    static let type = "type"
    static let sessionId = "session_id"
    static let payload = "payload"
}

private enum WhiteboardSyncBridgeError: LocalizedError {
    case ambiguousPayload
    case missingMediaSession

    var errorDescription: String? {
        switch self {
        case .ambiguousPayload: return "ambiguous DrawsKit sync payload"
        case .missingMediaSession: return "whiteboard media session is required"
        }
    }
}
