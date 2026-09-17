import Foundation
import CryptoKit
import OpenIMCore

public protocol OpenImIosAdapter: AnyObject {
    func login(params: OpenImLoginParams) throws
    func joinClassroomGroup(classroomId: String) throws
    func sendClassroomSignal(_ envelope: ClassroomImSignalEnvelope) throws
    func sendTextMessage(_ content: String) throws
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
    func onError(_ errCode: Int32, errMsg: String?) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = .failure(OpenImAdapterError.operationFailed(code: errCode, message: "OpenIM operation failed"))
        lock.unlock(); semaphore.signal()
    }
    func onSuccess(_ data: String?) {
        lock.lock()
        guard result == nil else { lock.unlock(); return }
        result = .success(data ?? ""); lock.unlock(); semaphore.signal()
    }
    func onProgress(_ progress: Int) {}
    func wait() throws -> String {
        guard semaphore.wait(timeout: .now() + OpenImTokens.operationTimeout) == .success else {
            throw OpenImAdapterError.invalidArgument("OpenIM operation timeout")
        }
        lock.lock(); defer { lock.unlock() }
        return try result!.get()
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
        let callback = OpenImResult(); start(callback, UUID().uuidString); return try callback.wait()
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
    private func send(_ message: String, onlineOnly: Bool) throws {
        lock.lock(); let group = groupId; lock.unlock()
        guard let group else { throw OpenImAdapterError.notLoggedIn }
        _ = try operation { Open_im_sdkSendMessage($0, $1, message, "", group, "{}", onlineOnly) }
    }
    func sendClassroomSignal(_ envelope: ClassroomImSignalEnvelope) throws {
        var payload: [String: Any] = ["signalId": envelope.signalId, "type": envelope.type, "data": envelope.data]
        if let value = envelope.v { payload["v"] = value }
        if let value = envelope.classroomId { payload["classroomId"] = value }
        if let value = envelope.appId { payload["appId"] = value }
        if let value = envelope.ts { payload["ts"] = value }
        let message = Open_im_sdkCreateCustomMessage(UUID().uuidString, try json(payload), "", CLASSROOM_IM_SIGNAL_DESC)
        try send(message, onlineOnly: true)
    }
    func sendTextMessage(_ content: String) throws {
        try send(Open_im_sdkCreateTextMessage(UUID().uuidString, content), onlineOnly: false)
    }
    func logout() { destroy() }
    func destroy() {
        lock.lock(); active = false; groupId = nil; connectionFactSequence &+= 1
        let sync = initialSync; initialSync = nil; lock.unlock()
        sync?.onError(-1, errMsg: "OpenIM initial synchronization cancelled")
        guard initialized else { return }
        _ = try? operation { Open_im_sdkLogout($0, $1) }
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
