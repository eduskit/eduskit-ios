import Foundation
import Darwin
import CryptoKit
import OpenIMCore

public protocol OpenImIosAdapter: AnyObject {
    func login(params: OpenImLoginParams) throws
    func joinClassroomGroup(classroomId: String) throws
    func sendClassroomSignal(_ envelope: ClassroomImSignalEnvelope) throws
    func sendTextMessage(_ content: String) throws -> OpenImChatMessage
    func loadHistory(cursor: String?, limit: Int) throws -> [String: Any]
    func logout()
    func destroy()
}
public struct OpenImIosAdapterOptions {
    public var onSignal: ((ClassroomImSignalEnvelope) -> Void)?
    public var onMessage: ((OpenImChatMessage) -> Void)?
    public var onError: ((OpenImError) -> Void)?
    public var onConnection: ((String) -> Void)?
    public init(onSignal: ((ClassroomImSignalEnvelope) -> Void)? = nil,
                onMessage: ((OpenImChatMessage) -> Void)? = nil,
                onError: ((OpenImError) -> Void)? = nil,
                onConnection: ((String) -> Void)? = nil) {
        self.onSignal = onSignal; self.onMessage = onMessage; self.onError = onError
        self.onConnection = onConnection
    }
}
private enum OpenImTokens {
    static let platformId = 1
    static let groupSession = 3
    static let textMessage = 101
    static let customMessage = 110
    static let logError = 2
    static let operationTimeout: TimeInterval = 30
}
public func createOpenImIosAdapter(options: OpenImIosAdapterOptions = OpenImIosAdapterOptions()) -> OpenImIosAdapter {
    OpenImIosAdapterImpl(options: options)
}
private final class OpenImResult: NSObject, Open_im_sdk_callbackBaseProtocol, Open_im_sdk_callbackSendMsgCallBackProtocol {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Result<String, Error>?
    private var waiterQoS: qos_class_t = QOS_CLASS_UNSPECIFIED

    /// 必须在发起厂商调用之前记录。回调可能在 `wait` 之前就回到另一条线程。
    func captureWaiter() {
        lock.lock()
        waiterQoS = qos_class_self()
        lock.unlock()
    }

    func onError(_ errCode: Int32, errMsg: String?) {
        complete(.failure(OpenImAdapterError.operationFailed(code: errCode, message: "OpenIM operation failed")))
    }
    func onSuccess(_ data: String?) {
        complete(.success(data ?? ""))
    }
    func onProgress(_ progress: Int) {}
    func wait() throws -> String {
        lock.lock()
        waiterQoS = qos_class_self()
        lock.unlock()
        guard semaphore.wait(timeout: .now() + OpenImTokens.operationTimeout) == .success else {
            throw OpenImAdapterError.invalidArgument("OpenIM operation timeout")
        }
        lock.lock(); defer { lock.unlock() }
        return try result!.get()
    }

    private func complete(_ value: Result<String, Error>) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = value
        let needed = waiterQoS
        lock.unlock()
        OpenImBlockingSignal.signal(semaphore, waiterQoS: needed)
    }
}
private final class OpenImIosAdapterImpl: NSObject, OpenImIosAdapter,
    Open_im_sdk_callbackOnConnListenerProtocol, Open_im_sdk_callbackOnAdvancedMsgListenerProtocol,
    Open_im_sdk_callbackOnConversationListenerProtocol {
    private let options: OpenImIosAdapterOptions
    private let lock = NSLock()
    private let callbackQueue = DispatchQueue(label: "edusdk.openim.callbacks")
    private var active = false
    private var groupId: String?
    private var initialized = false
    private var initialSync: OpenImResult?
    private var connectionFactSequence: UInt64 = 0
    init(options: OpenImIosAdapterOptions) { self.options = options; super.init() }
    private func operation(_ start: (OpenImResult, String) -> Void) throws -> String {
        guard !Thread.isMainThread else { throw OpenImAdapterError.invalidArgument("OpenIM operations must run off main") }
        let callback = OpenImResult()
        callback.captureWaiter()
        start(callback, UUID().uuidString)
        return try callback.wait()
    }
    private func json(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value)
        return String(decoding: data, as: UTF8.self)
    }
    func login(params: OpenImLoginParams) throws {
        guard params.platformId == OpenImTokens.platformId, !params.userId.isEmpty, !params.token.isEmpty,
              !params.apiAddr.isEmpty, !params.wsAddr.isEmpty else {
            throw OpenImAdapterError.invalidArgument("OpenIM iOS credentials require platform 1")
        }
        if initialized { destroy() }
        let key = SHA256.hash(data: Data("\(params.apiAddr)\n\(params.userId)".utf8)).map { String(format: "%02x", $0) }.joined()
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let storage = root.appendingPathComponent("openim/\(key)", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        let config = try json(["platformID": params.platformId, "apiAddr": params.apiAddr, "wsAddr": params.wsAddr,
                               "dataDir": storage.path, "logLevel": OpenImTokens.logError, "isLogStandardOutput": false])
        let sync = OpenImResult()
        sync.captureWaiter()
        lock.lock(); active = true; groupId = nil; initialSync = sync; lock.unlock()
        initialized = Open_im_sdkInitSDK(self, UUID().uuidString, config)
        guard initialized else { throw OpenImAdapterError.invalidArgument("OpenIM initSDK failed") }
        Open_im_sdkSetAdvancedMsgListener(self)
        Open_im_sdkSetConversationListener(self)
        do {
            _ = try operation { Open_im_sdkLogin($0, $1, params.userId, params.token) }
            _ = try sync.wait()
            lock.lock(); let stillActive = active; initialSync = nil; lock.unlock()
            guard stillActive else { throw OpenImAdapterError.notLoggedIn }
        }
        catch { destroy(); throw error }
    }
    func joinClassroomGroup(classroomId: String) throws {
        guard initialized else { throw OpenImAdapterError.notLoggedIn }
        let response = try operation { Open_im_sdkIsJoinGroup($0, $1, classroomId) }
        guard response == "true" else { throw OpenImAdapterError.invalidArgument("OpenIM classroom membership is missing") }
        lock.lock(); groupId = classroomId; lock.unlock()
    }
    private func send(_ message: String, onlineOnly: Bool) throws -> String {
        lock.lock(); let group = groupId; lock.unlock()
        guard let group else { throw OpenImAdapterError.notLoggedIn }
        return try operation { Open_im_sdkSendMessage($0, $1, message, "", group, "{}", onlineOnly) }
    }
    func sendClassroomSignal(_ envelope: ClassroomImSignalEnvelope) throws {
        // 顶层未知字段先写，已知字段随后覆盖，保证平台搬运不会改写协议语义
        var payload: [String: Any] = envelope.extras.filter {
            !classroomImSignalEnvelopeKeys.contains($0.key)
        }
        payload["signalId"] = envelope.signalId
        payload["type"] = envelope.type
        payload["data"] = envelope.data
        if let value = envelope.v { payload["v"] = value }
        if let value = envelope.classroomId { payload["classroomId"] = value }
        if let value = envelope.appId { payload["appId"] = value }
        if let value = envelope.ts { payload["ts"] = value }
        let message = Open_im_sdkCreateCustomMessage(UUID().uuidString, try json(payload), "", CLASSROOM_IM_SIGNAL_DESC)
        _ = try send(message, onlineOnly: true)
    }
    func loadHistory(cursor: String?, limit: Int) throws -> [String: Any] {
        lock.lock(); let group = groupId; lock.unlock()
        guard let group else { throw OpenImAdapterError.notLoggedIn }
        let conversationRaw = try operation { Open_im_sdkGetOneConversation($0, $1, Int32(OpenImTokens.groupSession), group) }
        guard let conversation = try JSONSerialization.jsonObject(with: Data(conversationRaw.utf8)) as? [String: Any],
              let conversationId = conversation["conversationID"] as? String else { throw OpenImAdapterError.invalidArgument("missing OpenIM conversation") }
        let params = try json(["conversationID": conversationId, "startClientMsgID": cursor ?? "", "count": limit, "viewType": 0])
        let raw = try operation { Open_im_sdkGetAdvancedHistoryMessageList($0, $1, params) }
        guard let page = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let code = page["errCode"] as? Int, code == 0,
              let isEnd = page["isEnd"] as? Bool, let messages = page["messageList"] as? [[String: Any]] else {
            throw OpenImAdapterError.invalidArgument("invalid OpenIM history result")
        }
        let records: [[String: Any]] = messages.map { message in
            ["id": message["clientMsgID"] ?? NSNull(), "conversation_id": message["groupID"] ?? NSNull(),
             "sender_id": message["sendID"] ?? NSNull(), "sent_at": message["sendTime"] ?? NSNull(),
             "sequence": message["seq"] ?? NSNull(),
             "content": message["contentType"] as? Int == OpenImTokens.textMessage && message["sessionType"] as? Int == OpenImTokens.groupSession
                ? ((message["textElem"] as? [String: Any])?["content"] ?? NSNull()) : NSNull()]
        }
        return ["records": records, "has_more": !isEnd]
    }

    func sendTextMessage(_ content: String) throws -> OpenImChatMessage {
        let raw = try send(Open_im_sdkCreateTextMessage(UUID().uuidString, content), onlineOnly: false)
        guard let message = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any],
              let id = message["clientMsgID"] as? String, let sender = message["sendID"] as? String,
              let group = message["groupID"] as? String,
              let text = (message["textElem"] as? [String: Any])?["content"] as? String,
              let time = message["sendTime"] as? NSNumber else { throw OpenImAdapterError.invalidArgument("missing confirmed OpenIM message") }
        return OpenImChatMessage(id: id, senderId: sender, content: text, sentAt: time.int64Value, classroomId: group)
    }
    func logout() { destroy() }
    func destroy() {
        lock.lock(); active = false; groupId = nil; connectionFactSequence &+= 1
        let sync = initialSync; initialSync = nil; lock.unlock()
        sync?.onError(-1, errMsg: "OpenIM initial synchronization cancelled")
        guard initialized else { return }
        // Core closes classroom presence independently; local transport teardown
        // must not wait for a remote logout response.
        Open_im_sdkUnInitSDK(UUID().uuidString)
        initialized = false
    }
    private func dispatch(_ block: @escaping () -> Void) {
        callbackQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock(); let active = self.active; self.lock.unlock()
            if active { block() }
        }
    }
    private func receive(_ raw: String?) {
        guard let raw, let data = raw.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) else { return }
        let messages = (object as? [[String: Any]]) ?? ((object as? [String: Any]).map { [$0] } ?? [])
        for message in messages {
            lock.lock(); let group = groupId; lock.unlock()
            guard let group, message["groupID"] as? String == group,
                  message["sessionType"] as? Int == OpenImTokens.groupSession,
                  let sender = message["sendID"] as? String, !sender.isEmpty else { continue }
            switch message["contentType"] as? Int {
            case OpenImTokens.customMessage:
                guard let custom = message["customElem"] as? [String: Any],
                      custom["description"] as? String == CLASSROOM_IM_SIGNAL_DESC,
                      var envelope = SignalParser.parseSignalEnvelope(string: custom["data"] as? String),
                      envelope.classroomId == nil || envelope.classroomId == "" || envelope.classroomId == group else { continue }
                envelope.classroomId = group; envelope.senderId = sender
                let value = envelope
                dispatch { [weak self] in self?.options.onSignal?(value) }
            case OpenImTokens.textMessage:
                guard let text = (message["textElem"] as? [String: Any])?["content"] as? String,
                      let id = message["clientMsgID"] as? String, !id.isEmpty else { continue }
                let value = OpenImChatMessage(id: id, senderId: sender, content: text,
                    sentAt: (message["sendTime"] as? NSNumber)?.int64Value, classroomId: group)
                dispatch { [weak self] in self?.options.onMessage?(value) }
            default: continue
            }
        }
    }
    private func report(_ event: String, code: Int32? = nil) {
        dispatch { [weak self] in self?.options.onError?(OpenImError(code: code, message: "OpenIM \(event)")) }
    }
    private func connection(_ status: String, code: Int32? = nil, expectedSequence: UInt64? = nil) {
        lock.lock()
        guard active, expectedSequence == nil || expectedSequence == connectionFactSequence else { lock.unlock(); return }
        connectionFactSequence &+= 1
        // Queue under the same lock as the revision check, preserving vendor fact order.
        dispatch { [weak self] in
            guard let self else { return }
            if let callback = self.options.onConnection { callback(status) }
            else if status != "connecting" && status != "connected" {
                self.options.onError?(OpenImError(code: code, message: "OpenIM \(status)"))
            }
        }
        lock.unlock()
    }
    private func failInitialSync() {
        lock.lock(); let sync = initialSync; lock.unlock()
        sync?.onError(-1, errMsg: "OpenIM synchronization interrupted")
    }
    func onConnectFailed(_ errCode: Int32, errMsg: String?) { connection("disconnected", code: errCode) }
    func onConnectSuccess() {}
    func onConnecting() { connection("connecting") }
    func onKickedOffline() { failInitialSync(); connection("kicked") }
    func onUserTokenExpired() { failInitialSync(); connection("token_expired") }
    func onUserTokenInvalid(_ errMsg: String?) { failInitialSync(); connection("token_invalid") }
    func onSyncServerStart(_ reinstalled: Bool) { connection("connecting") }
    func onSyncServerFailed(_ reinstalled: Bool) { failInitialSync(); connection("disconnected") }
    func onSyncServerFinish(_ reinstalled: Bool) {
        lock.lock()
        guard active else { lock.unlock(); return }
        let sync = initialSync
        let expectedGroup = groupId
        connectionFactSequence &+= 1
        let sequence = connectionFactSequence
        lock.unlock()
        sync?.onSuccess("synchronized")
        guard let expectedGroup else { connection("connected"); return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let member = try? self.operation { Open_im_sdkIsJoinGroup($0, $1, expectedGroup) }
            self.connection(member == "true" ? "connected" : "disconnected", expectedSequence: sequence)
        }
    }
    func onConversationChanged(_ conversationList: String?) {}
    func onConversationUserInputStatusChanged(_ change: String?) {}
    func onNewConversation(_ conversationList: String?) {}
    func onSyncServerProgress(_ progress: Int) {}
    func onTotalUnreadMessageCountChanged(_ totalUnreadCount: Int32) {}
    func onRecvNewMessage(_ message: String?) { receive(message) }
    func onRecvOfflineNewMessage(_ message: String?) { receive(message) }
    func onRecvOnlineOnlyMessage(_ message: String?) { receive(message) }
    func onMsgDeleted(_ message: String?) {}
    func onNewRecvMessageRevoked(_ messageRevoked: String?) {}
    func onRecvC2CReadReceipt(_ msgReceiptList: String?) {}
}
