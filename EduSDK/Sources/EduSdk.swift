import Foundation
#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
final class WeakRtcVideoView {
    weak var value: UIView?

    init(_ value: UIView) {
        self.value = value
    }
}
#endif

/// 无 UI SDK 对外入口。契约见 schema/edusdk-sdk.yaml。
/// 内部包装 UniFFI EdusdkClient；未实现 Method 抛出 SdkError.notImplemented。
public final class EduSdk {
    let createOptions: EduSdkCreateOptions
    let core = EdusdkClient()
    private let toolSound = TeachingToolSound()
    private var initialized = false
    var classroomId: String?
    private var pollTimer: DispatchSourceTimer?
    private let runtimeOutput = RuntimeOutputMailbox()
    private let shutdownCompletion = DispatchSemaphore(value: 0)
    private let destroyQueue = DispatchQueue(label: Tokens.destroyQueueLabel)
    private var destroyReceipt: NativeSdkDestroyReceipt? // created under destroyStateLock when teardown starts
    private var shutdownFinished = false // guarded by destroyStateLock
    private var whiteboardCredentialRefreshWorkItem: DispatchWorkItem?
    private var currentWhiteboardCredentials: WhiteboardCredentials?
    private let eventLoopQueue = DispatchQueue(label: Tokens.eventLoopQueueLabel, qos: .userInitiated)
    /// 事件解析与派发的串行队列。
    ///
    /// 去重状态（`lastEmittedClassKey`、`pendingJoinSuccess`）只在这条队列上读写，
    /// 因此 `coreQueue` 不必为了串行化而覆盖整个事件循环。
    private let eventPumpQueue = DispatchQueue(label: Tokens.eventPumpQueueLabel, qos: .userInitiated)
    private var eventPump: SerialEventPump!
    private static let coreQueueKey = DispatchSpecificKey<UInt8>()
    private let coreQueue = DispatchQueue(label: Tokens.coreQueueLabel)
    /// 通道由 Core 随副作用下发（`HostEffect.lane`），平台不再按 action 类型前缀推断。
    ///
    /// `liveStroke` 必须独立于 `im`：IM 登录、聊天和最终白板 op 都要等回执，
    /// 共用一条队列会让书写时的高频笔迹排在一次 IM 往返之后，反之亦然。
    let effectQueues: [String: DispatchQueue] = [
        "playback": DispatchQueue(label: "edusdk.effects.playback"),
        "preferences": DispatchQueue(label: "edusdk.effects.preferences"),
        HostEffectLanes.backend: DispatchQueue(label: Tokens.backendEffectQueueLabel),
        HostEffectLanes.backendQuery: DispatchQueue(label: Tokens.backendQueryEffectQueueLabel),
        HostEffectLanes.backendCommand: DispatchQueue(label: Tokens.backendCommandEffectQueueLabel),
        HostEffectLanes.im: DispatchQueue(label: Tokens.imEffectQueueLabel),
        HostEffectLanes.rtc: DispatchQueue(label: Tokens.rtcEffectQueueLabel),
        HostEffectLanes.whiteboard: DispatchQueue(label: Tokens.whiteboardEffectQueueLabel),
        HostEffectLanes.live: DispatchQueue(label: Tokens.liveEffectQueueLabel),
        HostEffectLanes.liveStroke: DispatchQueue(label: Tokens.liveStrokeEffectQueueLabel),
    ]
    /// 后台冲刷副作用队列的串行队列。必须独立于 `effectQueues`：`drainHostEffects`
    /// 会把副作用派发给它们并等待完成，在同一个串行队列上再次进入就会自锁。
    private let effectPumpQueue = DispatchQueue(label: Tokens.effectPumpQueueLabel)
    private var effectPump: SerialEventPump!
    /// DrawsKit 高频发送只入队；Core 与 IM 回执等待不得占用主线程。
    private let whiteboardSendQueue = DispatchQueue(label: Tokens.whiteboardSendQueueLabel)
    /// 过程笔迹出站入口队列。与 `whiteboardSendQueue` 分开：最终 op 的发送会同步等
    /// IM 回执，共用队列时每次抬笔都会把后续笔迹堵住一次往返。
    private let liveStrokeSendQueue = DispatchQueue(label: Tokens.liveStrokeSendQueueLabel)
    /// 遥测独占一条队列：复用业务域队列会让上报排在进课副作用之后，
    /// 甚至被 IM 登录的长超时拖住；遥测是尽力而为的旁路，必须完全让路。
    private let telemetryQueue = DispatchQueue(label: Tokens.telemetryQueueLabel)
    private var historyRequestEpoch: UInt64 = 0 // guarded by destroyStateLock
    private var livePlaybackDelivery = DispatchWorkItem {} // guarded by destroyStateLock; UI only checks cancellation
    private let queryQueue = DispatchQueue(label: "com.edukits.edusdk.query", qos: .userInitiated)
    private let telemetryHost = TelemetryHost()
    private let continuationStorage = ContinuationStorage()
    private var telemetryPump: SerialEventPump!
    private let destroyStateLock = NSLock()
    private var destroyStarted = false
    private let sdkLifetime = DispatchWorkItem {}
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    /// 持有 OpenImIosAdapter（AnyObject 避免 SPM 无 Adapter 时编译失败）
    var imAdapter: AnyObject?
    var imConnectionGeneration: UInt64?
    var imRecoveryWorkItem: DispatchWorkItem?
    var sessionHeartbeatWorkItem: DispatchWorkItem?
    var mediaClockWorkItem: DispatchWorkItem?
    /// 持有 TencentTrtcIosAdapter（由 SwiftPM 解析 Vendor binary target）
    let rtcPlaybackOutput = NativePlaybackOutput()
    let whiteboardPlaybackOutput = WhiteboardPlaybackOutput()
    var rtcAdapter: AnyObject?
    var liveAdapter: TencentLiveIosAdapter?
    var liveCredentialRefreshWorkItem: DispatchWorkItem?
    #if os(iOS)
    var liveViews: [String: WeakRtcVideoView] = [:]
    /// 转推流回调代际。离课/销毁时自增，用于丢掉上一次会话迟到的播放器回调
    var liveEventEpoch: UInt64 = 0
    let liveEventEpochLock = NSLock()
    #endif
    #if os(iOS)
    var rtcLocalUserId: String?
    var localVideoPlaceholder: UIView?
    /// A user can temporarily have multiple SwiftUI hosts during layout transitions.
    /// TRTC renders into the most recently bound live view; older hosts remain as
    /// fallbacks until their `UIViewRepresentable` lifecycle dismantles them.
    var videoViews: [String: [WeakRtcVideoView]] = [:]
    var boundVideoViews: [String: WeakRtcVideoView] = [:]
    var videoBindEpoch: UInt64 = 0
    let videoBindLock = NSLock()
    #endif
    /// join 响应已落地但必要域尚未就绪时暂存，等 Core 的 RoomJoined 再回调。
    var pendingJoinPayload: JoinHttpClient.JoinPayload?
    /// Core 已判定 RoomJoined，等本轮 Core 快照产出权威 ClassInfo 后再回调。
    var joinSuccessDue = false

    private var continuationListeners: [UUID: (ContinuationView?) -> Void] = [:]
    var classInfoListeners: [(ClassInfo) -> Void] = []
    private var whiteboardSuspendHandler: ((String, @escaping (Result<Void,Error>) -> Void) -> Void)?
    /// Scoped native capability. Complete after players and synchronization stop;
    /// the SDK waits only on its whiteboard worker, with a bounded OS deadline.
    public func setWhiteboardSuspendHandler(_ handler: ((String, @escaping (Result<Void,Error>) -> Void) -> Void)?) {
        whiteboardSuspendHandler = handler
    }
    var onStageUsersListeners: [([StageUser]) -> Void] = []
    var membersListeners: [([ClassroomMember]) -> Void] = []
    var userPermissionsListeners: [([UserPermission]) -> Void] = []
    var myStageStatusListeners: [(MyStageStatus) -> Void] = []
    var userProfileListeners: [(UserProfile) -> Void] = []
    var imMessageListeners: [(ImMessage) -> Void] = []
    /// Swift订阅对象及队列由独立worker管理；主线程仅发布已准备回调。
    private var whiteboardMediaEvents: WhiteboardMediaEventListeners { whiteboardClassroomEvents.media }
    private let whiteboardClassroomEvents = WhiteboardClassroomEventListeners()
    private let mediaRequestPorts = WhiteboardMediaPortRegistry()
    private lazy var cleanupSources=WhiteboardMediaCleanupSources(ownerQueue:coreQueue)


    func registerMediaCleanupSource(_ port:WhiteboardMediaCleanupPort) {
        effectPumpQueue.async { [weak self,weak port] in
            guard let port else{return}
            guard let self else{port.ownerFinished();return}
            self.withCore {
                guard self.initialized else{port.ownerFinished();return}
                self.cleanupSources.register(port) { request in
                    try self.core.whiteboardMediaCleanup(requestJson:request)
                }
            }
        }
    }
    func invokeMediaCleanup(_ json:String,completion:@escaping(Result<String,Error>)->Void) {
        effectPumpQueue.async { [weak self] in
            guard let self else {completion(.failure(SdkError(code:.notInitialized,message:"Cleanup SDK was released")));return}
            do {
                let value=try self.withCore { () throws -> String in
                    guard self.initialized else{throw SdkError(code:.notInitialized,message:"Cleanup runtime was released")}
                    let result=try self.core.whiteboardMediaCleanup(requestJson:json)
                    try self.ingestRuntimeUpdate()
                    return result
                }
                completion(.success(value))
            } catch {completion(.failure(WhiteboardMediaCleanupSources.boundaryError(error)))}
        }
    }
    /// Runs even when the turn has no public event/state/revision change.
    /// Publish before shutdownCompletion can release the runtime owner.
    private func publishMediaCleanupSources() {
        cleanupSources.publish { request in
            try core.whiteboardMediaCleanup(requestJson:request)
        }
    }

    func registerWhiteboardMediaPort(_ port: WhiteboardMediaPortLifetime) throws {
        try mediaRequestPorts.register(port)
    }
    private var cachedLivePlaybackStats: [LivePlaybackStats] = []
    private var livePlaybackStatsListeners: [UUID: ([LivePlaybackStats]) -> Void] = [:]
    private var livePlaybackEventListeners: [UUID: (LivePlaybackEvent) -> Void] = [:]
    public func getLivePlaybackStats() -> [LivePlaybackStats] { cachedLivePlaybackStats }
    public func onLivePlaybackStatsUpdated(_ listener: @escaping ([LivePlaybackStats]) -> Void) -> () -> Void {
        let id = UUID(); livePlaybackStatsListeners[id] = listener
        return { [weak self] in self?.livePlaybackStatsListeners.removeValue(forKey: id) }
    }
    public func onLivePlaybackEvent(_ listener: @escaping (LivePlaybackEvent) -> Void) -> () -> Void {
        let id = UUID(); livePlaybackEventListeners[id] = listener
        return { [weak self] in self?.livePlaybackEventListeners.removeValue(forKey: id) }
    }
    var teachingToolsListeners: [(String) -> Void] = []
    var errorListeners: [(SdkError) -> Void] = []
    var mediaOpenHintListeners: [(MediaOpenHint) -> Void] = []
    var localScreenShareListeners: [(Bool) -> Void] = []
    var screenShareUsersListeners: [([String]) -> Void] = []
    var streamInfoListeners: [([StreamInfo]) -> Void] = []
    var teacherMutedMicListeners: [() -> Void] = []
    var teacherMutedCameraListeners: [() -> Void] = []
    private var cachedStreamInfos: [StreamInfo] = []
    private var cachedMediaOpenHint = MediaOpenHint(visible: false, audience: .student)
    var lastClassroomTitle: String?
    private var lastEmittedClassKey: String?
    private var classroomCourseware: [Courseware] = []
    /// Render-facing getters read only this precomputed value. Core/JSON work stays on eventPumpQueue.
    private var snapshotPublication: SnapshotPublication<SdkSnapshot>!

    private let continuationWindowLock = NSLock()
    private var continuationWindowBound = false
    private var boundContinuationWindow: ContinuationWindowPort?

    /// Replace the view-owned window port without recreating the classroom session.
    public func bindContinuationWindow(_ port: ContinuationWindowPort?) {
        continuationWindowLock.lock()
        boundContinuationWindow = port
        continuationWindowBound = true
        continuationWindowLock.unlock()
    }

    private var activeContinuationWindow: ContinuationWindowPort? {
        continuationWindowLock.lock()
        defer { continuationWindowLock.unlock() }
        return continuationWindowBound ? boundContinuationWindow : createOptions.continuationWindow
    }

    private init(createOptions: EduSdkCreateOptions) {
        self.createOptions = createOptions
        continuationEnvironment = ContinuationEnvironmentSubscription { [weak self] request in
            guard let self else { throw SdkError(code: .invalidState, message: "SDK is destroyed") }
            try self.withCore {
                guard !self.sdkLifetime.isCancelled else { throw SdkError(code: .invalidState, message: "SDK is destroyed") }
                try self.core.requestClassroomContinuation(requestJson: request)
            }
            try self.drainHostEffects()
            self.pumpEvents()
        }
        coreQueue.setSpecific(key: Self.coreQueueKey, value: 1)
        snapshotPublication = SnapshotPublication(initial: SdkSnapshot(), worker: eventPumpQueue, revision: { $0.generation })
        eventPump = SerialEventPump(queue: eventPumpQueue) { [weak self] in self?.drainCoreEvents() }
        effectPump = SerialEventPump(queue: effectPumpQueue) { [weak self] in self?.drainScheduledEffects() }
        telemetryPump = SerialEventPump(queue: telemetryQueue) { [weak self] in self?.runTelemetryEffects() }
    }

    public static func create(options: EduSdkCreateOptions) -> EduSdk {
        let sdk = EduSdk(createOptions: options)
        sdk.telemetryHost.ingestEndpoint = options.telemetryUrl?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if sdk.telemetryHost.ingestEndpoint?.isEmpty == true {
            sdk.telemetryHost.ingestEndpoint = nil
        }
        return sdk
    }

    // MARK: - Callbacks

    @discardableResult
    public func onJoinSuccess(_ listener: @escaping (JoinSuccessInfo) -> Void) -> () -> Void {
        whiteboardClassroomEvents.joinSuccess.add(.event, listener: listener)
    }

    @discardableResult
    public func onJoinProgress(_ listener: @escaping (JoinProgress) -> Void) -> () -> Void {
        whiteboardClassroomEvents.joinProgress.add(.event, listener: listener)
    }

    /// Core 判定需要白板时下发凭证；关闭或不需要白板时回调 `nil`。
    @discardableResult
    public func onWhiteboardCredentials(
        _ listener: @escaping (WhiteboardCredentials?) -> Void
    ) -> () -> Void {
        whiteboardClassroomEvents.credentials.add(.event, listener: listener)
    }

    @discardableResult
    public func onClassInfoChanged(_ listener: @escaping (ClassInfo) -> Void) -> () -> Void {
        classInfoListeners.append(listener)
        return { [weak self] in
            self?.classInfoListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    /// Delivers immutable snapshots on the main queue. The callback never runs while holding a
    /// Core or snapshot lock, so SwiftUI/UIKit rendering cannot block Core progress.
    @discardableResult
    public func onSdkSnapshot(_ listener: @escaping (SdkSnapshot) -> Void) -> () -> Void {
        snapshotPublication.subscribe(listener)
    }

    @discardableResult
    public func onOnStageUsersChanged(_ listener: @escaping ([StageUser]) -> Void) -> () -> Void {
        onStageUsersListeners.append(listener)
        return { [weak self] in
            self?.onStageUsersListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onMembersChanged(_ listener: @escaping ([ClassroomMember]) -> Void) -> () -> Void {
        membersListeners.append(listener)
        return { [weak self] in
            self?.membersListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onUserPermissionsChanged(_ listener: @escaping ([UserPermission]) -> Void) -> () -> Void {
        userPermissionsListeners.append(listener)
        return { [weak self] in
            self?.userPermissionsListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onMyStageStatusChanged(_ listener: @escaping (MyStageStatus) -> Void) -> () -> Void {
        myStageStatusListeners.append(listener)
        return { [weak self] in
            self?.myStageStatusListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onUserProfileUpdated(_ listener: @escaping (UserProfile) -> Void) -> () -> Void {
        userProfileListeners.append(listener)
        return { [weak self] in
            self?.userProfileListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onImMessageReceived(_ listener: @escaping (ImMessage) -> Void) -> () -> Void {
        imMessageListeners.append(listener)
        return { [weak self] in
            self?.imMessageListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onWhiteboardSyncReceived(_ listener: @escaping (String) -> Void) -> () -> Void {
        whiteboardClassroomEvents.sync.add(.event, listener: listener)
    }

    @discardableResult
    public func onWhiteboardMediaClock(_ listener: @escaping (String) -> Void) -> () -> Void {
        whiteboardMediaEvents.add(.clock, listener: listener)
    }

    /// Internal OS capability subscription; public clock publication stays main.
    func observeWhiteboardMediaClockOnWorker(_ listener: @escaping (String) -> Void) -> () -> Void {
        whiteboardMediaEvents.add(.clock,onWorker:true,listener:listener)
    }

    @discardableResult
    public func onWhiteboardLiveStrokeReceived(_ listener: @escaping (String) -> Void) -> () -> Void {
        whiteboardClassroomEvents.liveStroke.add(.event, listener: listener)
    }

    @discardableResult
    public func onWhiteboardMediaReceived(_ listener: @escaping (String) -> Void) -> () -> Void {
        whiteboardMediaEvents.add(.media, listener: listener)
    }

    @discardableResult
    public func onWhiteboardSyncReloadRequested(
        _ listener: @escaping (WhiteboardSyncReloadRequest) -> Void
    ) -> () -> Void {
        whiteboardClassroomEvents.syncReload.add(.event, listener: listener)
    }

    @discardableResult
    public func onTeachingToolsUpdated(_ listener: @escaping (String) -> Void) -> () -> Void {
        teachingToolsListeners.append(listener)
        return { [weak self] in self?.teachingToolsListeners.removeAll { $0 as AnyObject === listener as AnyObject } }
    }

    public func onWhiteboardMediaProgramResult(_ listener: @escaping (String) -> Void) -> () -> Void {
        whiteboardMediaEvents.add(.programResult, listener: listener)
    }

    @discardableResult
    public func onWhiteboardRecoveryRequested(
        _ listener: @escaping (WhiteboardRecoveryRequest) -> Void
    ) -> () -> Void {
        whiteboardClassroomEvents.recovery.add(.event, listener: listener)
    }

    @discardableResult
    public func onError(_ listener: @escaping (SdkError) -> Void) -> () -> Void {
        errorListeners.append(listener)
        return { [weak self] in
            self?.errorListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    public func onMediaOpenHintChanged(_ listener: @escaping (MediaOpenHint) -> Void) -> () -> Void {
        mediaOpenHintListeners.append(listener)
        return { [weak self] in
            self?.mediaOpenHintListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    /// 本端屏幕共享是否真的在推流；以 Vendor 采集回执为准。
    @discardableResult
    public func onLocalScreenShareChanged(_ listener: @escaping (Bool) -> Void) -> () -> Void {
        localScreenShareListeners.append(listener)
        return { [weak self] in
            self?.localScreenShareListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    /// 当前正在共享屏幕的远端用户；UI 据此决定是否渲染共享画面。
    @discardableResult
    public func onScreenShareUsersChanged(_ listener: @escaping ([String]) -> Void) -> () -> Void {
        screenShareUsersListeners.append(listener)
        return { [weak self] in
            self?.screenShareUsersListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onStreamInfoChanged(_ listener: @escaping ([StreamInfo]) -> Void) -> () -> Void {
        streamInfoListeners.append(listener)
        return { [weak self] in
            self?.streamInfoListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onTeacherMutedMyMicrophone(_ listener: @escaping () -> Void) -> () -> Void {
        teacherMutedMicListeners.append(listener)
        return { [weak self] in
            self?.teacherMutedMicListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onTeacherMutedMyCamera(_ listener: @escaping () -> Void) -> () -> Void {
        teacherMutedCameraListeners.append(listener)
        return { [weak self] in
            self?.teacherMutedCameraListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    // MARK: - Lifecycle

    private let continuationConfigured = DispatchWorkItem {}
    private var continuationEnvironment: ContinuationEnvironmentSubscription!

    public func initialize(config: InitializeConfig = InitializeConfig()) throws {
        guard createOptions.continuationEnvironment == nil || createOptions.continuation != nil else {
            throw SdkError(code: .invalidState, message: "Continuation environment subscription requires configuration")
        }
        if createOptions.continuation != nil && Thread.isMainThread {
            throw SdkError(code: .invalidState, message: "Continuation configuration requires a worker")
        }
        try withCore {
            guard !sdkLifetime.isCancelled else { throw SdkError(code: .invalidState, message: "SDK is destroyed") }
            guard !initialized else { throw SdkError(code: .invalidState, message: "SDK is already initialized") }
            let appId = config.appId ?? createOptions.appId
            let backendUrl = config.backendUrl ?? createOptions.backendUrl
            LiveLicence.shared.apply(
                url: createOptions.liveLicenseUrl ?? "",
                key: createOptions.liveLicenseKey ?? "",
                owner: self
            ) { [weak self] state in
                self?.reportLiveLicence(state)
            }
            try core.`init`(config: InitConfig(
                appId: appId,
                backendBaseUrl: backendUrl,
                rtcProvider: "mock",
                imProvider: "openim",
                liveProvider: "live_cdn",
                whiteboardProvider: "mock",
                userToken: createOptions.userToken,
                deviceId: telemetryHost.deviceId,
                platform: telemetryHost.platform,
                sdkVersion: telemetryHost.sdkVersion,
                appVersion: createOptions.appVersion,
                liveSupportsLeb: createOptions.liveSupportsLeb
            ))
            initialized = true
            observeBackground()
        }
        do {
            if let configure = createOptions.continuation {
                let request = try configure()
                try withCore {
                    guard !sdkLifetime.isCancelled else { throw SdkError(code: .invalidState, message: "SDK is destroyed") }
                    try core.requestClassroomContinuation(requestJson: request)
                }
            }
            if let subscribe = createOptions.continuationEnvironment { try continuationEnvironment.start(subscribe) }
            continuationConfigured.cancel()
        } catch {
            destroy()
            throw error
        }
        startEventLoop()
        // Core 在 init 时会请求读取上次遗留的落盘批次，这里把它执行掉。
        drainTelemetryEffects()
        try drainHostEffects()
        pumpEvents()
    }

    /// Optional native completion runs on a background queue after the teardown
    /// job. Core cleanup may have failed/timed out; this is not a success ACK.
    public func destroy(completion: (() -> Void)? = nil) {
        LiveLicence.shared.detach(owner: self)
        destroyStateLock.lock()
        let receipt:NativeSdkDestroyReceipt
        if let existing=destroyReceipt {receipt=existing}
        else {receipt=NativeSdkDestroyReceipt();destroyReceipt=receipt}
        if let completion { receipt.notify(completion) }
        if destroyStarted {
            destroyStateLock.unlock()
            return
        }
        destroyStarted = true
        sdkLifetime.cancel()
        continuationEnvironment.close()
        mediaRequestPorts.destroy()
        whiteboardClassroomEvents.close()
        snapshotPublication.close()
        historyRequestEpoch += 1
        livePlaybackDelivery.cancel()
        livePlaybackDelivery = DispatchWorkItem {}
        destroyStateLock.unlock()
        toolSound.reset(final: true)
        let clearListeners: () -> Void = { [weak self] in self?.clearPublicListeners() }
        if Thread.isMainThread {
            clearListeners()
        } else {
            DispatchQueue.main.async(execute: clearListeners)
        }
        // The effect pump and every lane remain available until Core confirms cleanup.
        destroyQueue.async { [self,receipt] in
            defer { receipt.complete() }
            destroyBlocking()
        }
    }

    private func destroyBlocking() {
        let ownsRuntime = withCore { initialized }
        whiteboardCredentialRefreshWorkItem?.cancel()
        whiteboardCredentialRefreshWorkItem = nil
        sessionHeartbeatWorkItem?.cancel()
        sessionHeartbeatWorkItem = nil
        mediaClockWorkItem?.cancel()
        mediaClockWorkItem = nil
        // Keep the scoped native capability until Core finishes shutdown effects.
        // Clearing credentials here would turn the required OS stop into a no-op.
        // 先解绑：通知晚于 shutdown 触发就会碰到已销毁的 Core。
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
            self.backgroundObserver = nil
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        if ownsRuntime {
            do {
                try withCore { try core.beginShutdown() }
                pumpEvents()
                // Deadline policy is in Core; this dedicated worker does not own any lane.
                shutdownCompletion.wait()
            } catch {
                let failure = SdkError(code: .internal, message: error.localizedDescription)
                DispatchQueue.main.async { [weak self] in self?.errorListeners.forEach { $0(failure) } }
            }
        }
        currentWhiteboardCredentials = nil
        whiteboardSuspendHandler = nil
        stopEventLoop()
        effectDispatchLock.lock()
        hostEffectGeneration &+= 1
        effectDispatchLock.unlock()
        requiredEffects.cancelAll()
        eventPump.close()
        effectPump.close()
        telemetryPump.close()
        invalidateVideoBinds()
        invalidateLiveBinds()
        liveAdapter?.stopAllPlay()
        teardownIm()
        teardownRtc()
        pendingJoinPayload = nil
        joinSuccessDue = false
        withCore {
            if initialized {
                try? core.shutdown()
                initialized = false
            }
            cleanupSources.finishOwner()
        }
        classroomId = nil
        lastClassroomTitle = nil
        lastEmittedClassKey = nil
        classroomCourseware = []
    }

    /// Listener 属于 UI-facing 状态，只在主线程增删，避免后台销毁与回调遍历并发修改数组。
    private func clearPublicListeners() {
        continuationListeners.removeAll()
        classInfoListeners.removeAll()
        onStageUsersListeners.removeAll()
        membersListeners.removeAll()
        myStageStatusListeners.removeAll()
        userProfileListeners.removeAll()
        imMessageListeners.removeAll()
        teachingToolsListeners.removeAll()
        whiteboardClassroomEvents.close()
        livePlaybackStatsListeners.removeAll()
        livePlaybackEventListeners.removeAll()
        cachedLivePlaybackStats = []
        errorListeners.removeAll()
        mediaOpenHintListeners.removeAll()
        localScreenShareListeners.removeAll()
        screenShareUsersListeners.removeAll()
        streamInfoListeners.removeAll()
        teacherMutedMicListeners.removeAll()
        teacherMutedCameraListeners.removeAll()
        cachedStreamInfos = []
        cachedMediaOpenHint = MediaOpenHint(visible: false, audience: .student)
    }

    // MARK: - Classroom

    public func enterClassroom(params: EnterClassroomParams) throws {
        try ensureInitialized()
        classroomId = params.classroomId
        do {
            try withCore {
                try core.joinRoom(
                    roomId: params.classroomId,
                    userId: params.userId,
                    displayName: params.displayName.isEmpty ? params.userId : params.displayName
                )
            }
            // drain 必须在 core 队列之外：各域回执时要短暂占用该队列。
            try drainHostEffects()
            pumpEvents()
        } catch let err as SdkError {
            DispatchQueue.main.async { [weak self] in
                self?.errorListeners.forEach { $0(err) }
            }
            throw err
        } catch {
            let err = SdkError(code: .networkError, message: error.localizedDescription)
            DispatchQueue.main.async { [weak self] in
                self?.errorListeners.forEach { $0(err) }
            }
            throw err
        }
    }

    public func startClass() throws {
        try ensureInitialized()
        try withCore { try core.startClass() }
        try drainHostEffects()
        pumpEvents()
    }

    public func requestTeachingTools(_ requestJson: String) throws {
        try ensureInitialized()
        try withCore { try core.requestTeachingTools(requestJson: requestJson) }
        try drainHostEffects()
        pumpEvents()
    }

    public func requestWhiteboardMediaProgram(_ requestJson: String) throws {
        try ensureInitialized()
        try withCore { try core.requestWhiteboardMediaProgram(requestJson: requestJson) }
        try drainHostEffects()
        pumpEvents()
    }

    public func requestClassroomContinuation(_ requestJson: String) throws {
        try ensureInitialized()
        try withCore { try core.requestClassroomContinuation(requestJson: requestJson) }
        try drainHostEffects()
        pumpEvents()
    }

    public func loadMembers(_ cursor: String? = nil) throws {
        try ensureInitialized()
        try withCore { try core.loadMembers(cursor: cursor ?? "") }
        try drainHostEffects()
        pumpEvents()
    }

    public func leaveClassroom() throws {
        destroyStateLock.lock()
        historyRequestEpoch += 1
        livePlaybackDelivery.cancel()
        livePlaybackDelivery = DispatchWorkItem {}
        destroyStateLock.unlock()
        toolSound.reset()
        cachedMediaOpenHint = MediaOpenHint(visible: false, audience: .student)
        try ensureInitialized()
        invalidateVideoBinds()
        invalidateLiveBinds()
        try withCore { try core.leaveRoom() }
        try drainHostEffects()
        pumpEvents()
        // 兜底停播：离课补偿若因 Core 侧状态未记账而没下发 live_stop_all_play，
        // 播放器就会带着已销毁的渲染视图活到下一次进课，届时同名流只换地址、不出画。
        liveAdapter?.stopAllPlay()
        classroomId = nil
        classroomCourseware = []
    }

    /// 离课/销毁时作废转推流的渲染视图。
    /// 这些视图属于上一次会话的 UI，留着会让下一次进课的播放器绑到已销毁的 View。
    func invalidateLiveBinds() {
        #if os(iOS)
        liveEventEpochLock.lock()
        liveEventEpoch += 1
        liveEventEpochLock.unlock()
        liveViews.removeAll()
        #endif
    }

    #if os(iOS)
    private func currentLiveEventEpoch() -> UInt64 {
        liveEventEpochLock.lock()
        defer { liveEventEpochLock.unlock() }
        return liveEventEpoch
    }
    #endif

    func invalidateVideoBinds() {
        #if os(iOS)
        videoBindLock.lock()
        videoBindEpoch += 1
        videoViews.removeAll()
        boundVideoViews.removeAll()
        rtcLocalUserId = nil
        videoBindLock.unlock()
        #endif
    }

    func isVideoBindActive() -> Bool {
        destroyStateLock.lock()
        let started = destroyStarted
        destroyStateLock.unlock()
        return !started && initialized
    }

    /// SwiftUI can create its RTC host views before `initialize()` and before the
    /// RTC adapter exists. Keep those weak hosts so `connectRtcEffect` can bind
    /// them once the room connection is ready; only a destroyed SDK rejects them.
    func canRetainVideoBinds() -> Bool {
        destroyStateLock.lock()
        let started = destroyStarted
        destroyStateLock.unlock()
        return !started
    }

    public func endClass() throws {
        toolSound.reset()
        try ensureInitialized()
        try withCore { try core.endClass() }
        try drainHostEffects()
        pumpEvents()
    }

    public func userRaiseHand() throws {
        try ensureInitialized()
        try withCore { try core.userRaiseHand() }
        try drainHostEffects()
        pumpEvents()
    }

    public func userCancelHand() throws {
        try ensureInitialized()
        try withCore { try core.userCancelHand() }
        try drainHostEffects()
        pumpEvents()
    }

    public func userLeaveStage() throws {
        try ensureInitialized()
        try withCore { try core.userLeaveStage() }
        try drainHostEffects()
        pumpEvents()
    }

    public func grantMicrophonePermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.grantMicrophonePermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func revokeMicrophonePermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.revokeMicrophonePermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func grantCameraPermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.grantCameraPermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func revokeCameraPermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.revokeCameraPermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    /// DrawsKitImTransport 出站入口；由 Rust Core 统一校验、归并并生成 IM 信令。
    public func sendWhiteboardSync(payloadJson: String) throws {
        try ensureInitialized()
        whiteboardSendQueue.async { [weak self] in
            guard let self else { return }
            self.reportWhiteboardSendFailure {
                try self.withCore {
                    guard self.initialized else { return }
                    try self.core.sendWhiteboardSync(payloadJson: payloadJson)
                }
                try self.drainHostEffects()
                self.pumpEvents()
            }
        }
    }

    /// 过程笔迹出站。
    ///
    /// 与最终 op 的关键差别是**不在这里冲刷副作用、也不泵事件**：那会让每一个笔迹包都
    /// 同步等一次 IM 回执（`DispatchGroup.wait`），再加一次全量事件轮询（含 Core 快照读取）。
    /// DrawsKit 的采样频率远高于 IM 吞吐，逐包等待会让发送队列无界堆积、`coreQueue` 常态
    /// 占用，最终表现为书写时主线程拿不到队列而掉帧。副作用交给已经存在的后台泵。
    public func sendWhiteboardLiveStroke(payloadJson: String) throws {
        try ensureInitialized()
        liveStrokeSendQueue.async { [weak self] in
            guard let self else { return }
            self.reportWhiteboardSendFailure {
                try self.withCore {
                    guard self.initialized else { return }
                    try self.core.sendWhiteboardLiveStroke(payloadJson: payloadJson)
                }
                self.scheduleEffectPump()
            }
        }
    }

    public func sendWhiteboardMedia(payloadJson: String) throws {
        try ensureInitialized()
        liveStrokeSendQueue.async { [weak self] in
            guard let self else { return }
            self.reportWhiteboardSendFailure {
                try self.withCore {
                    guard self.initialized else { return }
                    try self.core.sendWhiteboardMedia(payloadJson: payloadJson)
                }
                self.scheduleEffectPump()
            }
        }
    }

    private func reportWhiteboardSendFailure(_ body: () throws -> Void) {
        do {
            try body()
        } catch {
            let sdkError = error as? SdkError ?? SdkError(
                code: .whiteboardProviderError,
                message: error.localizedDescription
            )
            DispatchQueue.main.async { [weak self] in
                self?.errorListeners.forEach { $0(sdkError) }
            }
        }
    }

    public func sendImMessage(content: String) throws {
        try ensureInitialized()
        try withCore { try core.sendImMessage(content: content) }
        try drainHostEffects()
        pumpEvents()
    }

    public func getClassroomCourseware() throws -> [Courseware] {
        try ensureInitialized()
        return classroomCourseware
    }

    public func getMemberList() throws -> [ClassroomMember] {
        try ensureInitialized()
        return readUiSnapshot().members
    }

    public func getMemberCount() throws -> UInt32 {
        try ensureInitialized()
        return readUiSnapshot().memberCount
    }

    public func getMembersNextCursor() throws -> String? {
        try ensureInitialized()
        return readUiSnapshot().membersNextCursor
    }

    public func getImMessageList() throws -> [ImMessage] {
        try ensureInitialized()
        return readUiSnapshot().imMessages
    }

    public func getImHistoryState() -> ImHistoryState { readUiSnapshot().imHistoryState }

    public func loadImMessageHistory(options: ImHistoryOptions = ImHistoryOptions()) async throws -> ImHistoryPage {
        let (epoch, effectError): (UInt64, Error?) = try await runQuery { [self] in
            try ensureInitialized()
            guard options.limit == nil || (1...100).contains(options.limit!) else { throw SdkError(code: .invalidArgument, message: "history limit must be 1...100") }
            let epoch = currentHistoryRequestEpoch()
            try withCore { try core.loadImMessageHistory(cursor: options.cursor, limit: UInt32(options.limit ?? 50)) }
            var effectError: Error?
            do { try drainHostEffects() } catch { effectError = error }
            pumpEvents()
            return (epoch, effectError)
        }
        while true {
            let state: ImHistoryState = try await runQuery { [self] in
                try ensureInitialized()
                return try withCore {
                    guard epoch == currentHistoryRequestEpoch() else { throw SdkError(code: .invalidState, message: "IM history request was cancelled") }
                    let raw = try core.imHistoryJson()
                    return try JSONDecoder().decode(ImHistoryState.self, from: Data(raw.utf8))
                }
            }
            if let error = state.error { throw SdkError(code: SdkErrorCode(rawValue: Int(error.code)) ?? .internal, message: error.message) }
            if let error = effectError { throw (error as? SdkError ?? SdkError(code: .imProviderError, message: error.localizedDescription)) }
            if !state.loading {
                guard let page = state.page else { throw SdkError(code: .invalidState, message: "IM history request was cancelled") }
                return page
            }
            // Await Core completion without holding the query queue or resubmitting the request.
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func currentHistoryRequestEpoch() -> UInt64 {
        destroyStateLock.lock()
        defer { destroyStateLock.unlock() }
        return historyRequestEpoch
    }

    public func getUserCourseware() throws -> [Courseware] {
        try getClassroomCourseware()
    }

    public func getAppCourseware() throws -> [Courseware] {
        try getClassroomCourseware()
    }

    /// Host GET …/manifest?classroomId= → opaque JSON string
    public func getCoursewareManifest(coursewareId: String) async throws -> String {
        try await runQuery { [self] in
        try ensureInitialized()
        let id = coursewareId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else {
            throw sdkError(.invalidState, "coursewareId is required")
        }
        let clsId = classroomId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !clsId.isEmpty else {
            throw sdkError(.invalidState, "classroomId is required")
        }
        let token = createOptions.userToken?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let backendUrl = createOptions.backendUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !backendUrl.isEmpty else {
            throw sdkError(.invalidState, "backendUrl is required")
        }
        guard !token.isEmpty else {
            throw sdkError(.invalidState, "userToken is required")
        }
        return try JoinHttpClient.fetchCoursewareManifest(
            backendUrl: backendUrl,
            userToken: token,
            classroomId: clsId,
            coursewareId: id
        )
        }
    }

    public func inviteUserOnStage(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.inviteUserOnStage(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func removeUserFromStage(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.removeUserFromStage(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func approveUserOnStage(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.approveUserOnStage(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func rejectUserOnStage(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.rejectUserOnStage(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func getOnStageUserList() throws -> [StageUser] {
        try ensureInitialized()
        return readUiSnapshot().onStageUsers
    }

    public func getClassInfo() throws -> ClassInfo {
        try ensureInitialized()
        return readUiSnapshot().classInfo ?? ClassInfo(
            classroomId: classroomId ?? "",
            phase: .idle,
            lifecycleStatus: .notStarted
        )
    }

    public func getClassroomInteractionPolicy() throws -> [ActionAvailability] {
        try ensureInitialized()
        return readUiSnapshot().interactionPolicy
    }

    public func getMemberActionPolicy(userId: String) throws -> String {
        try ensureInitialized()
        try withCore { try core.loadMemberPermissions(userId: userId) }
        try drainHostEffects()
        pumpEvents()
        return try withCore { try core.memberActionPolicyJson(userId: userId) }
    }

    public func loadMemberPermissions(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.loadMemberPermissions(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func muteUserMicrophone(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.muteUserMicrophone(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func muteUserCamera(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.muteUserCamera(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func promptUserOpenMicrophone(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.promptUserOpenMicrophone(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func promptUserOpenCamera(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.promptUserOpenCamera(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func revokeUserMessagePermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.revokeUserMessagePermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func grantUserMessagePermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.grantUserMessagePermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func grantWhiteboardPermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.grantWhiteboardPermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func revokeWhiteboardPermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.revokeWhiteboardPermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func grantScreenSharePermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.grantScreenSharePermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func revokeScreenSharePermission(userId: String) throws {
        try ensureInitialized()
        try withCore { try core.revokeScreenSharePermission(userId: userId) }
        try drainHostEffects()
        pumpEvents()
    }

    public func setLocalAudioMuted(muted: Bool) throws {
        try ensureInitialized()
        try withCore { try core.muteAudio(muted: muted) }
        try drainHostEffects()
        pumpEvents()
    }

    public func setLocalVideoMuted(muted: Bool) throws {
        try ensureInitialized()
        try withCore { try core.muteVideo(muted: muted) }
        try drainHostEffects()
        pumpEvents()
    }

    public func listMediaDevices() -> MediaDeviceList {
        #if os(iOS)
        guard let adapter = ensureRtcAdapter() else {
            return MediaDeviceList()
        }
        let devices = adapter.listMediaDevices()
        return MediaDeviceList(
            cameras: devices.cameras.map { MediaDevice(deviceId: $0.deviceId, label: $0.label, kind: $0.kind) },
            microphones: devices.microphones.map { MediaDevice(deviceId: $0.deviceId, label: $0.label, kind: $0.kind) },
            speakers: devices.speakers.map { MediaDevice(deviceId: $0.deviceId, label: $0.label, kind: $0.kind) }
        )
        #else
        return MediaDeviceList()
        #endif
    }

    #if os(iOS)
    public func startLocalPreview(view: UIView, cameraId: String? = nil) {
        guard classroomView().runtime.canInspectDevices else { return }
        guard canRetainVideoBinds() else { return }
        let adapter = ensureRtcAdapter()
        adapter?.startLocalPreview(view: view, cameraId: cameraId)
    }
    #endif

    public func stopLocalPreview() {
        #if os(iOS)
        (rtcAdapter as? TencentTrtcIosAdapter)?.stopLocalPreview()
        #endif
    }

    public func startLocalAudioPreview(microphoneId: String? = nil) {
        guard classroomView().runtime.canInspectDevices else { return }
        #if os(iOS)
        ensureRtcAdapter()?.startLocalAudioPreview(microphoneId: microphoneId)
        #endif
    }

    public func stopLocalAudioPreview() {
        #if os(iOS)
        (rtcAdapter as? TencentTrtcIosAdapter)?.stopLocalAudioPreview()
        #endif
    }

    public func setLocalAudioLevelListener(_ listener: ((Int) -> Void)?) {
        guard classroomView().runtime.canInspectDevices else { return }
        #if os(iOS)
        ensureRtcAdapter()?.setLocalAudioLevelListener(listener)
        #endif
    }

    public func playTestTone() {
        guard classroomView().runtime.canInspectDevices else { return }
        #if os(iOS)
        ensureRtcAdapter()?.playTestTone()
        #endif
    }

    public func confirmDeviceCheck(selection: DeviceCheckSelection = DeviceCheckSelection()) throws {
        try ensureInitialized()
        #if os(iOS)
        (rtcAdapter as? TencentTrtcIosAdapter)?.setPreferredDevices(
            TrtcDeviceSelection(
                cameraId: selection.cameraId,
                microphoneId: selection.microphoneId,
                speakerId: selection.speakerId
            )
        )
        #endif
    }

    public func dismissMediaOpenHint() throws {
        try ensureInitialized()
        try withCore { try core.dismissMediaOpenHint() }
        try drainHostEffects()
        pumpEvents()
    }

    public func onClassroomContinuationChanged(_ listener: @escaping (ContinuationView?) -> Void) -> () -> Void {
        let id = UUID()
        continuationListeners[id] = listener
        return { [weak self] in self?.continuationListeners.removeValue(forKey: id) }
    }

    public func getClassroomContinuationView() -> ContinuationView? { readUiSnapshot().continuation }

    public func classroomView() -> ClassroomView { readUiSnapshot().classroomView }

    public func mediaOpenHint() -> MediaOpenHint {
        cachedMediaOpenHint
    }

    /// 开始屏幕共享。Core 校验「已上台 + 有 screen_share 权限」后下发采集，
    /// 真实推流状态以 onLocalScreenShareChanged 回调为准。
    public func startScreenShare() throws {
        try ensureInitialized()
        try withCore { try core.startScreenShare() }
        try drainHostEffects()
        pumpEvents()
    }

    public func stopScreenShare() throws {
        try ensureInitialized()
        try withCore { try core.stopScreenShare() }
        try drainHostEffects()
        pumpEvents()
    }

    func localVideoCaptureMuted() -> Bool {
        !readUiSnapshot().localVideoBindable
    }

    public func getUserStreamInfo(userId: String? = nil) throws -> StreamInfo {
        try ensureInitialized()
        let trimmed = userId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        #if os(iOS)
        let localId = rtcLocalUserId
        #else
        let localId: String? = nil
        #endif
        let id = trimmed.isEmpty ? (localId ?? "local") : trimmed
        if let cached = cachedStreamInfos.first(where: { $0.userId == id }) {
            return cached
        }
        let state = try withCore { try core.roomState() }
        if id == localId || id == "local" {
            return StreamInfo(
                userId: id,
                audioMuted: state.localAudioMuted,
                videoMuted: state.localVideoMuted
            )
        }
        return StreamInfo(userId: id, audioMuted: true, videoMuted: true)
    }

    // MARK: - Internal

    /// 同通道串行、跨通道并发。
    ///
    /// Core 在 join 落地后会把 IM、白板、RTC 同批下发；串行执行会让 IM 登录的数十秒
    /// 超时把白板和 RTC 一起拖住，进课耗时变成各通道之和。
    ///
    /// 等待点由 Core 下发的 `delivery` 决定，不再由平台按域名猜测：可选能力失败由 Core
    /// 降级并通过 joinProgress 呈现，易失的过程笔迹更不能让调用方等一次 IM 往返。
    ///
    /// 必须在 core 队列之外调用：各通道线程回执时要短暂占用 core 队列。
    private let effectDispatchLock = NSRecursiveLock()
    private var hostEffectGeneration: UInt64 = 0
    private var terminalEffectQueues: [String: DispatchQueue] = [:]
    func currentHostEffectGeneration() -> UInt64 {
        effectDispatchLock.lock(); defer { effectDispatchLock.unlock() }
        return hostEffectGeneration
    }
    private let requiredEffects = RequiredEffectTracker()
    private func drainHostEffects(waitForRequired: Bool = true) throws {
        if Thread.isMainThread { scheduleEffectPump(); return }
        var waiter: RequiredEffectTracker.Waiter?
        defer { if let waiter { requiredEffects.endWait(waiter) } }
        var firstError: Error?
        while true {
            if waiter?.cancelled == true { break }
            effectDispatchLock.lock()
            let effects: [HostEffectEnvelope]
            let required: [RequiredEffectTracker.Completion]
            do {
                (effects, required) = try withCore {
                    try ingestRuntimeUpdate()
                    if waitForRequired && waiter == nil { waiter = requiredEffects.beginWait() }
                    defer { runtimeOutput.effects.removeAll() }
                    return (try runtimeOutput.effects.map(Self.parseHostEffect), requiredEffects.snapshot())
                }
            }
            catch { effectDispatchLock.unlock(); throw error }
            let barrier = effects.first { $0.action["type"] as? String == "classroom_stop_tasks" }
            if let barrier {
                hostEffectGeneration &+= 1
                terminalEffectQueues.removeAll()
                _ = runLaneChain([barrier], generation: hostEffectGeneration)
            }
            let generation = hostEffectGeneration
            let buckets = Dictionary(grouping: effects.filter { $0.id != barrier?.id }, by: \.lane)
            for (lane, bucket) in buckets {
                let queue: DispatchQueue
                if generation == 0 || (lane == "preferences" || lane == "playback") { queue = effectQueues[lane] ?? DispatchQueue(label: "edusdk.effects.\(lane)") }
                else {
                    if terminalEffectQueues[lane] == nil { terminalEffectQueues[lane] = DispatchQueue(label: "edusdk.effects.\(lane).\(generation)") }
                    queue = terminalEffectQueues[lane]!
                }
                queue.async { [weak self] in _ = self?.runLaneChain(bucket, generation: generation) }
            }
            effectDispatchLock.unlock()
            // No Core/dispatch lock spans I/O. Include work already taken by the background drain.
            if waitForRequired {
                for completion in required {
                    let error = completion.wait()
                    if firstError == nil { firstError = error }
                }
            }
            if effects.isEmpty && (!waitForRequired || required.isEmpty) { break }
        }
        let observedFailure = waiter.flatMap { requiredEffects.endWait($0) }
        if let failure = firstError ?? observedFailure { throw failure }
    }

    /// A receipt arriving while the drain is finishing must queue another pass.
    private func scheduleEffectPump() { effectPump.request() }

    private func drainScheduledEffects() {
        guard initialized else { return }
        defer { drainTelemetryEffects() }
        do {
            try drainHostEffects(waitForRequired: false)
        } catch {
            let sdkError = SdkError(code: .providerError, message: error.localizedDescription)
            DispatchQueue.main.async { [weak self] in
                self?.errorListeners.forEach { $0(sdkError) }
            }
        }
    }

    /// 进入后台时抢先上报。
    ///
    /// iOS 随时可能在后台终止进程，缓冲里等待攒批的事件会跟着一起消失，
    /// 而「进不去课就切走应用」恰恰是最常见的动作，丢的正是最该看到的那批。
    private func observeBackground() {
        #if canImport(UIKit)
        guard backgroundObserver == nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            self?.reportAppVisibility(SessionLifecycle.background)
        }
        if foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                self?.reportAppVisibility(SessionLifecycle.foreground)
                self?.notifyWhiteboardAppResumed()
                if let generation = self?.imConnectionGeneration {
                    self?.dispatchImLifecycleEvent(["type": "im.connection", "generation": generation, "status": "app_resumed"])
                }
            }
        }
        #endif
    }

    /// DrawsKit Room API 401 时由 UI 调用，立刻换发白板凭证。
    public func notifyWhiteboardCredentialsExpired() {
        dispatchWhiteboardProviderEvent(["type": "credentials_expired"])
    }

    public func notifyWhiteboardReady(boardId: String) {
        let normalized = boardId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, currentWhiteboardCredentials?.roomId == normalized else { return }
        dispatchWhiteboardProviderEvent(
            ["type": "opened", "board_id": normalized],
            flushTelemetry: true
        )
    }

    public func notifyWhiteboardFailed(boardId: String, message: String) {
        let normalizedBoardId = boardId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBoardId.isEmpty,
              currentWhiteboardCredentials?.roomId == normalizedBoardId else { return }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        dispatchWhiteboardProviderEvent(
            ["type": "failed", "message": normalized.isEmpty ? "whiteboard initialization failed" : normalized],
            flushTelemetry: true
        )
    }

    private enum SessionLifecycle {
        static let domain = "im"
        static let visibility = "app.visibility"
        static let background = "background"
        static let foreground = "foreground"
        static let boundary = #"{"type":"session.boundary"}"#
        static func heartbeatDue(_ generation: UInt64) -> String {
            "{\"type\":\"session.heartbeat_due\",\"generation\":\(generation)}"
        }
    }

    private func reportAppVisibility(_ state: String) {
        guard initialized else { return }
        effectPumpQueue.async { [weak self] in
            guard let self, self.initialized else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: ["type": SessionLifecycle.visibility, "state": state])
                try self.withCore {
                    try self.core.applyProviderEvent(domain: SessionLifecycle.domain, payloadJson: String(decoding: data, as: UTF8.self))
                }
                if state == SessionLifecycle.background { self.flushTelemetry() }
                try self.drainHostEffects()
                self.pumpEvents()
            } catch {
                // 前后台只服务遥测，失败不能变成用户可见错误。
            }
        }
    }

    func dispatchImLifecycleEvent(_ payload: [String: Any]) {
        guard initialized else { return }
        effectPumpQueue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: payload)
                try self.withCore { try self.core.applyProviderEvent(domain: "im", payloadJson: String(decoding: data, as: UTF8.self)) }
                try self.drainHostEffects()
                self.pumpEvents()
            } catch {
                let error = SdkError(code: .imProviderError, message: error.localizedDescription)
                DispatchQueue.main.async { [weak self] in self?.errorListeners.forEach { $0(error) } }
            }
        }
    }

    private func notifyWhiteboardAppResumed() {
        dispatchWhiteboardProviderEvent(["type": "app_resumed"])
    }

    private func dispatchWhiteboardProviderEvent(
        _ payload: [String: Any],
        flushTelemetry: Bool = false
    ) {
        guard initialized, classroomId?.isEmpty == false else { return }
        effectPumpQueue.async { [weak self] in
            guard let self else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: payload)
                try self.withCore {
                    try self.core.applyProviderEvent(
                        domain: "whiteboard",
                        payloadJson: String(decoding: data, as: UTF8.self)
                    )
                }
                if flushTelemetry { self.flushTelemetry() }
                try self.drainHostEffects()
                self.pumpEvents()
            } catch {
                let sdkError = SdkError(
                    code: .whiteboardProviderError,
                    message: error.localizedDescription
                )
                DispatchQueue.main.async { [weak self] in
                    self?.errorListeners.forEach { $0(sdkError) }
                }
            }
        }
    }

    /// 排空遥测队列。异步且吞掉全部异常：调用方绝不能因为遥测而变慢或失败。
    private func drainTelemetryEffects() {
        if initialized { telemetryPump.request() }
    }

    private func runTelemetryEffects() {
        while true {
            let effects: [String]
            do {
                effects = try withCore {
                    try ingestRuntimeUpdate()
                    defer { runtimeOutput.telemetry.removeAll() }
                    return runtimeOutput.telemetry
                }
            } catch { return }
            if effects.isEmpty { return }
            for raw in effects {
                guard let effect = try? Self.parseHostEffect(raw) else { continue }
                do {
                    let payload = try telemetryHost.execute(effect.action)
                    completeTelemetryEffect(id: effect.id, outcome: [
                        "status": "success",
                        "payload": payload,
                    ])
                } catch {
                    // 失败回执让 Core 按退避重试；不上报、不打断循环。
                    completeTelemetryEffect(id: effect.id, outcome: [
                        "status": "failure",
                        "code": Self.telemetryFailureCode(for: error),
                        "message": error.localizedDescription,
                    ])
                }
            }
        }
    }

    private func completeTelemetryEffect(id: UInt64, outcome: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: [
            "effect_id": id,
            "outcome": outcome,
        ]) else { return }
        withCore { core.completeTelemetryEffect(resultJson: String(decoding: data, as: UTF8.self)) }
    }

    /// 进后台等时机：立即攒批并异步发出。
    private func flushTelemetry() {
        guard initialized else { return }
        withCore { core.flushTelemetry() }
        drainTelemetryEffects()
    }

    /// 单条通道内保持 FIFO：同通道副作用之间存在顺序依赖（如登录先于发信令）。
    private func runLaneChain(_ effects: [HostEffectEnvelope], generation: UInt64) -> Error? {
        var firstError: Error?
        for effect in effects {
            let runtimeOwned = effect.lane == "preferences" || effect.lane == "playback"
            if (generation != currentHostEffectGeneration() && !runtimeOwned) || !withCore({ initialized }) { continue }
            defer {
                // Follow-ups enter the registry before this receipt can release a public caller.
                withCore {
                    if initialized {
                        do { try ingestRuntimeUpdate() } catch { if firstError == nil { firstError = error } }
                    }
                    requiredEffects.complete(effect.id, failure: firstError)
                }
            }
            do {
                let payload = try executeHostEffect(effect.action)
                if (generation != currentHostEffectGeneration() && !runtimeOwned) || !withCore({ initialized }) { continue }
                do {
                    try withCore {
                        try completeHostEffect(id: effect.id, outcome: [
                            "status": "success",
                            "payload": payload,
                        ])
                    }
                } catch {
                    if firstError == nil { firstError = error }
                }
            } catch {
                if (generation != currentHostEffectGeneration() && !runtimeOwned) || !withCore({ initialized }) { continue }
                do {
                    try withCore {
                        let outcome: [String: Any]
                        if let http = error as? HostHttpFailure {
                            // HTTP 失败只回原始响应体；分类与文案格式化都在 Core。
                            outcome = ["status": "http_failure", "status_code": http.statusCode, "body": http.localizedDescription]
                        } else {
                            outcome = ["status": "failure", "code": Self.hostEffectFailureCode(effect.lane), "message": error.localizedDescription]
                        }
                        try completeHostEffect(id: effect.id, outcome: outcome)
                    }
                    // IM completion belongs to Core readiness/error events, including retries.
                    if effect.action["type"] as? String != "im_connect", firstError == nil { firstError = error }
                } catch {
                    if firstError == nil { firstError = error }
                }
            }
        }
        return firstError
    }

    private static func parseHostEffect(_ raw: String) throws -> HostEffectEnvelope {
        guard let data = raw.data(using: .utf8),
              let effect = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = effect["id"] as? NSNumber,
              let action = effect["action"] as? [String: Any],
              let lane = effect["lane"] as? String,
              let delivery = effect["delivery"] as? String else {
            throw SdkError(code: .internal, message: "invalid host effect")
        }
        return HostEffectEnvelope(
            id: id.uint64Value,
            lane: lane,
            delivery: delivery,
            action: action
        )
    }

    /// 按通道上报失败码，Core 才能把失败归到正确的域并决定回滚还是降级。
    private static func hostEffectFailureCode(_ lane: String) -> String {
        switch lane {
        case HostEffectLanes.im, HostEffectLanes.liveStroke: return "IM_PROVIDER_ERROR"
        case HostEffectLanes.rtc: return "RTC_PROVIDER_ERROR"
        case HostEffectLanes.whiteboard: return "WHITEBOARD_PROVIDER_ERROR"
        default: return "NETWORK_ERROR"
        }
    }

    private func completeHostEffect(id: UInt64, outcome: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: [
            "effect_id": id,
            "outcome": outcome,
        ])
        try core.completeHostEffect(resultJson: String(decoding: data, as: UTF8.self))
        // Receipts can enqueue more effects and events without another vendor callback.
        pumpEvents()
        scheduleEffectPump()
    }

    private func stopNativeWhiteboard() throws {
        guard let credentials = currentWhiteboardCredentials else { return }
        guard let handler = whiteboardSuspendHandler else {
            throw SdkError(code:.whiteboardProviderError,message:"Whiteboard suspension port is required")
        }
        do {
            try WhiteboardNativeStopReceipt.wait { done in handler(credentials.mediaSessionId,done) }
        } catch {
            throw SdkError(code:.whiteboardProviderError,message:error.localizedDescription)
        }
    }

    private func executeHostEffect(_ action: [String: Any]) throws -> Any {
        let type = action["type"] as? String ?? ""
        switch type {
        case "classroom_continuation_playback":
            guard let allowed = action["allowed"] as? Bool, let outputs = action["outputs"] as? [String] else {
                throw SdkError(code: .internal, message: "Invalid classroom playback effect")
            }
            var failures: [String] = []
            for output in outputs {
                if output == "notifications" { toolSound.setClassroomPlaybackAllowed(allowed) }
                else if output == "rtc" {
                    do { try rtcPlaybackOutput.setAllowed(allowed) }
                    catch { failures.append(error.localizedDescription) }
                }
                else if output == "whiteboard" {
                    do {
                        guard let generation = action["generation"] as? String,
                              let sequence = action["sequence"] as? UInt32 else {
                            throw SdkError(code: .internal, message: "Invalid whiteboard playback identity")
                        }
                        try whiteboardPlaybackOutput.set(.init(requestId: "\(generation):\(sequence)", allowed: allowed))
                    } catch { failures.append(error.localizedDescription) }
                }
                else if output == "live" {
                    do {
                        let adapter = ensureLiveAdapter()
                        try awaitHostMainCall(onDispatchThread: Thread.isMainThread, enqueue: {
                            DispatchQueue.main.async(execute: $0); return true
                        }) { try adapter.setClassroomPlaybackAllowed(allowed) }
                    } catch { failures.append(error.localizedDescription) }
                } else { failures.append("\(output) classroom playback port is unavailable") }
            }
            if !failures.isEmpty { throw SdkError(code: .internal, message: failures.joined(separator: "; ")) }
            return NSNull()
        case "classroom_continuation_window":
            guard let port = activeContinuationWindow else {
                throw SdkError(code: .internal, message: "Classroom continuation window port is unavailable")
            }
            guard let request = action["request"] as? [String: Any] else {
                throw SdkError(code: .internal, message: "Missing continuation window request")
            }
            let requestJson = String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
            try port.dispatch(requestJson: requestJson) { [weak self] eventJson in
                guard let self else { return }
                self.eventPumpQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        // Core owns exact window identities and stale-enter cleanup.
                        // Lane retirement must not discard receipts; shutdown still drains them.
                        try self.withCore {
                            guard self.initialized else { return }
                            let event = try JSONSerialization.jsonObject(with: Data(eventJson.utf8))
                            let data = try JSONSerialization.data(withJSONObject: ["type": "event", "event": event])
                            try self.core.requestClassroomContinuation(requestJson: String(decoding: data, as: UTF8.self))
                        }
                        self.pumpEvents()
                    } catch {
                        _ = self.sdkError(.internal, error.localizedDescription)
                    }
                }
            }
            return NSNull()
        case "continuation_load_settings", "continuation_save_settings":
            return try continuationStorage.execute(action)
        case "http":
            let payload = try JoinHttpClient.executeEffect(
                method: action["method"] as? String ?? "GET",
                url: action["url"] as? String ?? "",
                headers: action["headers"] as? [[String]] ?? [],
                body: action["body"] as? String
            )
            if let url = action["url"] as? String,
               url.range(of: "/v1/classrooms/join(?:\\?.*)?$", options: .regularExpression) != nil {
                let join = try JoinHttpClient.parseJoinEffect(payload)
                withCore {
                    classroomCourseware = join.coursewares
                    lastClassroomTitle = join.classroom.name
                    classroomId = join.classroom.classroomId
                    // onJoinSuccess 与 onClassInfoChanged 都要等 Core 落地 join 并产出权威 ClassInfo。
                    pendingJoinPayload = join
                }
                if let ingest = join.telemetryIngestUrl, !ingest.isEmpty {
                    telemetryHost.ingestEndpoint = ingest
                }
                emitClassSnapshotOnMain(join)
            }
            return payload
        case "im_connect":
            guard let generation = (action["generation"] as? NSNumber)?.uint64Value, generation > 0 else {
                throw SdkError(code: .imProviderError, message: "Core IM connection generation is required")
            }
            try connectImEffect(
                generation: generation,
                apiAddr: action["api_addr"] as? String ?? "",
                wsAddr: action["ws_addr"] as? String ?? "",
                platformId: action["platform_id"] as? Int ?? 0,
                userId: action["user_id"] as? String ?? "",
                token: action["token"] as? String ?? "",
                classroomId: action["classroom_id"] as? String ?? ""
            )
        case "im_schedule_recovery":
            guard let generation = (action["generation"] as? NSNumber)?.uint64Value, generation > 0,
                  let delay = (action["delay_ms"] as? NSNumber)?.intValue, delay > 0 else {
                throw SdkError(code: .imProviderError, message: "IM recovery requires generation and delay")
            }
            imRecoveryWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.dispatchImLifecycleEvent(["type": "im.recovery_due", "generation": generation])
            }
            imRecoveryWorkItem = work
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(delay), execute: work)
        case "session_schedule_heartbeat":
            guard let generation = (action["generation"] as? NSNumber)?.uint64Value, generation > 0,
                  let delay = (action["delay_ms"] as? NSNumber)?.intValue, delay > 0 else {
                throw SdkError(code: .imProviderError, message: "session heartbeat requires generation and delay")
            }
            sessionHeartbeatWorkItem?.cancel()
            let heartbeat = DispatchWorkItem { [weak self] in
                self?.effectPumpQueue.async { [weak self] in
                    guard let self, self.initialized else { return }
                    do {
                        try self.withCore {
                            try self.core.applyProviderEvent(
                                domain: SessionLifecycle.domain,
                                payloadJson: SessionLifecycle.heartbeatDue(generation)
                            )
                        }
                        try self.drainHostEffects()
                        self.pumpEvents()
                    } catch {
                        // 保活失败保持静默。
                    }
                }
            }
            sessionHeartbeatWorkItem = heartbeat
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(delay), execute: heartbeat)
        case "media_schedule_clock":
            guard let generation = (action["generation"] as? NSNumber)?.uint64Value, generation > 0,
                  let delay = (action["delay_ms"] as? NSNumber)?.intValue, delay > 0 else {
                throw SdkError(code: .whiteboardProviderError, message: "media clock requires generation and delay")
            }
            mediaClockWorkItem?.cancel()
            let clock = DispatchWorkItem { [weak self] in
                self?.effectPumpQueue.async { [weak self] in
                    guard let self, self.initialized else { return }
                    let payload = #"{"type":"media_clock_due","generation":\#(generation)}"#
                    try? self.withCore {
                        try self.core.applyProviderEvent(domain: "whiteboard", payloadJson: payload)
                    }
                    try? self.drainHostEffects()
                    self.pumpEvents()
                }
            }
            mediaClockWorkItem = clock
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(delay), execute: clock)
        case "rtc_send_sei":
            if let raw = action["payload"] as? [NSNumber] {
                let bytes = Data(raw.map { UInt8(truncating: $0) })
                (rtcAdapter as? TencentTrtcIosAdapter)?.sendSei(bytes)
            }
        case "im_disconnect": teardownIm()
        case "im_send_signal":
            let data = try JSONSerialization.data(withJSONObject: action["envelope"] ?? [:])
            try executeWhiteboardEnvelope(String(decoding: data, as: UTF8.self))
        case "im_load_history":
            #if canImport(OpenIMCore)
            let adapter = imAdapter as? OpenImIosAdapter
            guard let adapter else { throw SdkError(code: .imProviderError, message: "IM adapter is not ready") }
            return try adapter.loadHistory(cursor: action["cursor"] as? String, limit: action["limit"] as? Int ?? 0)
            #else
            throw SdkError(code: .imProviderError, message: "OpenIMCore is not linked")
            #endif
        case "im_send_text": return try sendTextMessage(action["content"] as? String ?? "")
        case "rtc_enter":
            try connectRtcEffect(
                sdkAppId: action["sdk_app_id"] as? String ?? "",
                userId: action["user_id"] as? String ?? "",
                userSig: action["user_sig"] as? String ?? "",
                classId: action["classroom_id"] as? String ?? ""
            )
        case "rtc_leave":
            #if os(iOS)
            (rtcAdapter as? TencentTrtcIosAdapter)?.exitRoom()
            #endif
            teardownRtc()
        case "whiteboard_open":
            guard let mediaSessionId = action["media_session_id"] as? String, !mediaSessionId.isEmpty else {
                throw SdkError(code: .providerError, message: "Core whiteboard media_session_id is required")
            }
            let credentials = WhiteboardCredentials(
                mediaSessionId: mediaSessionId,
                appId: action["app_id"] as? String ?? "",
                roomId: action["room_id"] as? String ?? "",
                userId: action["user_id"] as? String ?? "",
                token: action["token"] as? String ?? "",
                serverHost: action["server_host"] as? String ?? "",
                role: (action["role"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                expiresAt: (action["expires_at"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
            mediaRequestPorts.activate(mediaSessionId)
            currentWhiteboardCredentials = credentials
            emitWhiteboardCredentials(credentials)
        case "whiteboard_update_credentials":
            guard let current = currentWhiteboardCredentials else {
                throw SdkError(code: .providerError, message: "whiteboard credentials are not initialized")
            }
            let updated = WhiteboardCredentials(
                mediaSessionId: current.mediaSessionId,
                appId: current.appId,
                roomId: current.roomId,
                userId: current.userId,
                token: action["token"] as? String ?? "",
                serverHost: current.serverHost,
                role: current.role,
                expiresAt: (action["expires_at"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
            currentWhiteboardCredentials = updated
            emitWhiteboardCredentials(updated)
        case "whiteboard_schedule_credential_refresh":
            whiteboardCredentialRefreshWorkItem?.cancel()
            let generation = (action["generation"] as? NSNumber)?.uint64Value ?? 0
            let retry = (action["retry"] as? NSNumber)?.uint8Value ?? 0
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.initialized else { return }
                self.effectPumpQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        let payload = try JSONSerialization.data(withJSONObject: [
                            "type": "credentials_refresh_due",
                            "generation": generation,
                            "retry": retry,
                        ])
                        try self.withCore {
                            try self.core.applyProviderEvent(
                                domain: "whiteboard",
                                payloadJson: String(decoding: payload, as: UTF8.self)
                            )
                        }
                        try self.drainHostEffects()
                        self.pumpEvents()
                    } catch {
                        let sdkError = SdkError(
                            code: .whiteboardProviderError,
                            message: error.localizedDescription
                        )
                        DispatchQueue.main.async { [weak self] in
                            self?.errorListeners.forEach { $0(sdkError) }
                        }
                    }
                }
            }
            whiteboardCredentialRefreshWorkItem = work
            let delayMs = max(1, (action["delay_ms"] as? NSNumber)?.intValue ?? 1)
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + .milliseconds(delayMs),
                execute: work
            )
        case "classroom_stop_tasks":
            imRecoveryWorkItem?.cancel(); imRecoveryWorkItem = nil
            sessionHeartbeatWorkItem?.cancel(); sessionHeartbeatWorkItem = nil
            mediaClockWorkItem?.cancel(); mediaClockWorkItem = nil
            liveCredentialRefreshWorkItem?.cancel(); liveCredentialRefreshWorkItem = nil
            whiteboardCredentialRefreshWorkItem?.cancel(); whiteboardCredentialRefreshWorkItem = nil
            return NSNull()
        case "whiteboard_suspend":
            mediaRequestPorts.retire()
            try stopNativeWhiteboard()
            return NSNull()
        case "whiteboard_close":
            mediaRequestPorts.retire()
            try stopNativeWhiteboard()
            whiteboardCredentialRefreshWorkItem?.cancel()
            whiteboardCredentialRefreshWorkItem = nil
            currentWhiteboardCredentials = nil
            emitWhiteboardCredentials(nil)
        case "rtc_mute_local_audio":
            #if os(iOS)
            applyRtcMuteLocalAudio(muted: action["muted"] as? Bool ?? false)
            #endif
        case "rtc_mute_local_video":
            #if os(iOS)
            applyRtcMuteLocalVideo(muted: action["muted"] as? Bool ?? false)
            #endif
        // 采集是否真的起来由 Adapter 的 local_screen_share_available 事件回报。
        case "rtc_start_screen_share":
            #if os(iOS)
            try (rtcAdapter as? TencentTrtcIosAdapter)?.startScreenShare()
            #endif
        case "rtc_stop_screen_share":
            #if os(iOS)
            try (rtcAdapter as? TencentTrtcIosAdapter)?.stopScreenShare()
            #endif
        case "live_start_play":
            #if os(iOS)
            guard let playbackId = action["playback_id"] as? NSNumber,
                  let playbackEpoch = action["epoch"] as? NSNumber else {
                throw sdkError(.liveProviderError, "Live start requires a player instance and epoch")
            }
            ensureLiveAdapter().startPlay(LivePlayRequest(
                streamName: action["stream_name"] as? String ?? "",
                url: action["url"] as? String ?? "",
                streamType: action["stream_type"] as? String ?? "",
                publisherUserId: action["publisher_user_id"] as? String ?? "",
                muted: action["muted"] as? Bool ?? false,
                epoch: playbackEpoch.int64Value,
                playbackId: playbackId.int64Value
            ))
            #endif
        case "live_update_play_credential":
            liveAdapter?.updateCredential(
                streamName: action["stream_name"] as? String ?? "",
                url: action["url"] as? String ?? ""
            )
        case "live_set_playback_muted":
            guard let playbackId = action["playback_id"] as? NSNumber, playbackId.int64Value > 0 else {
                throw sdkError(.liveProviderError, "Live mute requires a player instance")
            }
            guard let adapter = liveAdapter as? TencentLiveIosAdapter else {
                throw sdkError(.liveProviderError, "Live adapter is not configured")
            }
            let name = action["stream_name"] as? String ?? ""
            let muted = action["muted"] as? Bool ?? false
            let id = playbackId.int64Value
            let applied = try awaitHostMainCall(onDispatchThread: Thread.isMainThread, enqueue: {
                DispatchQueue.main.async(execute: $0)
                return true
            }) { try adapter.setPlaybackMuted(streamName: name, muted: muted, playbackId: id) }
            return ["type": "live_playback_mute_result", "stream_name": name,
                    "playback_id": id, "muted": muted, "applied": applied]
        case "live_stop_play":
            liveAdapter?.stopPlay(streamName: action["stream_name"] as? String ?? "")
        case "live_stop_all_play":
            if let adapter = liveAdapter as? TencentLiveIosAdapter {
                try awaitHostMainCall(onDispatchThread: Thread.isMainThread, enqueue: {
                    DispatchQueue.main.async(execute: $0); return true
                }) { try adapter.stopAllPlayConfirmed() }
            }
        case "live_schedule_credential_refresh":
            liveCredentialRefreshWorkItem?.cancel()
            let generation = (action["generation"] as? NSNumber)?.uint64Value ?? 0
            let retry = (action["retry"] as? NSNumber)?.uint8Value ?? 0
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.initialized else { return }
                self.effectPumpQueue.async { [weak self] in
                    guard let self else { return }
                    do {
                        let payload = try JSONSerialization.data(withJSONObject: [
                            "type": "credentials_refresh_due",
                            "generation": generation,
                            "retry": retry,
                        ])
                        try self.withCore {
                            try self.core.applyProviderEvent(
                                domain: "live",
                                payloadJson: String(decoding: payload, as: UTF8.self)
                            )
                        }
                        try self.drainHostEffects()
                        self.pumpEvents()
                    } catch {
                        DispatchQueue.main.async { [weak self] in
                            self?.errorListeners.forEach {
                                $0(SdkError(code: .providerError, message: error.localizedDescription))
                            }
                        }
                    }
                }
            }
            liveCredentialRefreshWorkItem = work
            let delayMs = max(1, (action["delay_ms"] as? NSNumber)?.intValue ?? 1)
            DispatchQueue.global(qos: .utility).asyncAfter(
                deadline: .now() + .milliseconds(delayMs),
                execute: work
            )
        default:
            throw SdkError(code: .providerError, message: "unsupported host effect: \(type)")
        }
        return NSNull()
    }

    #if os(iOS)
    public func bindLiveStream(streamName: String, view: UIView) {
        liveViews[streamName] = WeakRtcVideoView(view)
        liveAdapter?.refreshRenderView(streamName: streamName)
    }

    public func unbindLiveStream(streamName: String, view: UIView) {
        guard liveViews[streamName]?.value === view else { return }
        liveViews.removeValue(forKey: streamName)
        liveAdapter?.refreshRenderView(streamName: streamName)
    }

    private let liveAdapterCreationLock = NSLock()
    private func ensureLiveAdapter() -> TencentLiveIosAdapter {
        liveAdapterCreationLock.lock(); defer { liveAdapterCreationLock.unlock() }
        if let existing = liveAdapter {
            return existing
        }
        let adapter = TencentLiveIosAdapter(
            onEvent: { [weak self] event in self?.handleLiveEvent(event) },
            resolveView: { [weak self] streamName in self?.liveViews[streamName]?.value }
        )
        liveAdapter = adapter
        return adapter
    }

    private func applyLiveProviderPayload(_ payload: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            try withCore { try core.applyProviderEvent(domain: "live", payloadJson: String(decoding: data, as: UTF8.self)) }
            pumpEvents()
        } catch { _ = sdkError(.liveProviderError, error.localizedDescription) }
    }

    private func reportLiveLicence(_ state: LicenceState) {
        effectPumpQueue.async { [weak self] in
            guard let self, self.initialized, self.canRetainVideoBinds() else { return }
            let value = state.report
            self.applyLiveProviderPayload(["type": "licence_loaded", "loaded": value.loaded,
                "state": value.state, "code": value.code, "message": value.message])
        }
    }

    private func handleLiveEvent(_ event: LiveAdapterEvent) {
        // 代际 fence：厂商回调是异步的，上一次会话的首帧/错误可能在离课之后才到，
        // 放给 Core 会把已经结束的那一路记成在播，下一次进课就不再下发起播。
        let epoch = currentLiveEventEpoch()
        effectPumpQueue.async { [weak self] in
            guard let self, self.initialized, self.canRetainVideoBinds(), epoch == self.currentLiveEventEpoch() else { return }
            let payload: [String: Any]
            switch event {
            case .playPrepared(let streamName):
                payload = ["type": "play_prepared", "stream_name": streamName]
            case .observation(let streamName, let playbackId, let kind, let code, let message):
                payload = ["type": "playback_observation", "stream_name": streamName, "playback_id": playbackId, "kind": kind, "vendor_code": code as Any? ?? NSNull(), "message": message as Any? ?? NSNull()]
            case .playStopped(let streamName, let recoverable, let reason):
                payload = [
                    "type": "play_stopped",
                    "stream_name": streamName,
                    "recoverable": recoverable,
                    "reason": reason,
                ]
            case .playFailed(let streamName, let message):
                payload = ["type": "play_failed", "stream_name": streamName, "message": message]
            case .sei(let streamName, let serverMs):
                payload = ["type": "sei", "stream_name": streamName, "server_ms": serverMs]
            case .statistics(let streamName, let playbackId, let metrics):
                payload = ["type": "statistics", "stream_name": streamName, "playback_id": playbackId, "metrics": metrics]
            }
            self.applyLiveProviderPayload(payload)
        }
    }
    #endif

    private func ensureInitialized() throws {
        guard !sdkLifetime.isCancelled else { throw SdkError(code: .invalidState, message: "SDK is destroyed") }
        if !initialized || !continuationConfigured.isCancelled { throw sdkError(.notInitialized, "call initialize() first and wait for configuration") }
    }

    private func notImplemented(_ method: String) throws -> Never {
        throw sdkError(.notImplemented, "\(method) is not implemented in core yet")
    }

    private func sdkError(_ code: SdkErrorCode, _ message: String) -> SdkError {
        let err = SdkError(code: code, message: message)
        DispatchQueue.main.async { [weak self] in
            self?.errorListeners.forEach { $0(err) }
        }
        return err
    }

    func withCore<T>(_ body: () throws -> T) rethrows -> T {
        precondition(
            !Thread.isMainThread,
            "EduSDK Core calls are forbidden on UIKit's main/render thread; use a background Task/queue"
        )
        if DispatchQueue.getSpecific(key: Self.coreQueueKey) != nil {
            return try body()
        }
        return try coreQueue.sync(execute: body)
    }

    private func startEventLoop() { pumpEvents() }

    private func stopEventLoop() {
        eventLoopQueue.async { [weak self] in
            self?.pollTimer?.cancel()
            self?.pollTimer = nil
        }
    }

    /// Called on coreQueue. Only this entry consumes the atomic Core output queues.
    private func ingestRuntimeUpdate(scheduleEvents: Bool = true) throws {
        let update = try core.pollRuntimeUpdate(forceSnapshot: false)
        let effects = try update.hostEffects.map(Self.parseHostEffect)
        let replacesPending = effects.contains { $0.action["type"] as? String == "classroom_stop_tasks" }
        if replacesPending { runtimeOutput.effects.removeAll() }
        requiredEffects.register(effects.filter(\.blocksCaller).map(\.id), replacingPending: replacesPending)
        runtimeOutput.accept(update)
        publishMediaCleanupSources()
        let deadline = update.nextWakeDelayMs.map { DispatchTime.now() + .milliseconds(Int(clamping: $0)) }
        eventLoopQueue.async { [weak self] in
            guard let self else { return }
            self.pollTimer?.cancel()
            self.pollTimer = nil
            self.destroyStateLock.lock()
            let active = !self.shutdownFinished
            self.destroyStateLock.unlock()
            guard active, let deadline else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.eventLoopQueue)
            timer.schedule(deadline: deadline,
                           leeway: .milliseconds(Tokens.pollLeewayMilliseconds))
            timer.setEventHandler { [weak self] in self?.pumpEvents() }
            self.pollTimer = timer
            timer.resume()
        }
        if scheduleEvents && runtimeOutput.hasEventsOrSnapshot { pumpEvents() }
        if !runtimeOutput.effects.isEmpty { scheduleEffectPump() }
        if !runtimeOutput.telemetry.isEmpty { drainTelemetryEffects() }
        if update.shutdownComplete {
            destroyStateLock.lock()
            let firstCompletion = !shutdownFinished
            shutdownFinished = true
            destroyStateLock.unlock()
            if firstCompletion { shutdownCompletion.signal() }
        } else if update.hasMoreWork { pumpEvents() }
    }

    /// 排空 Core 事件队列。始终异步：调用方（含 Vendor 回调线程与主线程）不为事件解析付费。
    func pumpEvents() {
        eventPump.request()
    }

    private func drainCoreEvents() {
        do {
            destroyStateLock.lock()
            let closing = destroyStarted
            destroyStateLock.unlock()
            if closing {
                try withCore {
                    guard initialized else { return }
                    try ingestRuntimeUpdate(scheduleEvents: false)
                    runtimeOutput.events.removeAll()
                    _ = try runtimeOutput.takeSnapshot()
                }
                return
            }
            // coreQueue 只在真正调用 Core 时持有。此前整个事件循环都包在 withCore 里，
            // 书写期间的高频事件解析会把它长期占满，其它调用方只能排队。
            destroyStateLock.lock()
            let diagnosticDelivery = livePlaybackDelivery
            destroyStateLock.unlock()
            let soundPoll = toolSound.capture()
            let (events, snapshots): ([Event], CoreUiSnapshots?) = try withCore {
                guard initialized else { return ([], nil) }
                try ingestRuntimeUpdate(scheduleEvents: false)
                let events = runtimeOutput.events
                runtimeOutput.events.removeAll()
                return (events, try runtimeOutput.takeSnapshot())
            }
            var callbacks: [() -> Void] = []
            func afterSnapshot(_ callback: @escaping () -> Void) { callbacks.append(callback) }
            var receivedMessages: [ImMessage] = []
            for event in events {
                switch event.kind {
                case .roomLeft:
                    break
                case .error:
                    if let e = event.error {
                        afterSnapshot { [weak self] in
                            self?.errorListeners.forEach {
                                $0(SdkError(code: Self.mapCoreErrorCode(String(describing: e.code)), message: e.message))
                            }
                        }
                    }
                case .roomJoined:
                    // 回调推迟到本轮 Core 快照产出 ClassInfo 之后，见 joinSuccessDue。
                    joinSuccessDue = true
                case .joinProgressChanged:
                    if let json = event.payloadJson, let progress = parseJoinProgress(json) {
                        whiteboardClassroomEvents.joinProgress.emit(progress, channel: .event,
                            validUntil: diagnosticDelivery, destination: .main)
                    }
                case .livePlaybackStatsUpdated:
                    if let json = event.payloadJson {
                        let stats = try JSONDecoder().decode([LivePlaybackStats].self, from: Data(json.utf8))
                        afterSnapshot { [weak self] in
                            guard let self, !diagnosticDelivery.isCancelled else { return }
                            self.cachedLivePlaybackStats = stats
                            Array(self.livePlaybackStatsListeners.values).forEach { $0(stats) }
                        }
                    }
                case .livePlaybackEvent:
                    if let json = event.payloadJson {
                        let value = try JSONDecoder().decode(LivePlaybackEvent.self, from: Data(json.utf8))
                        afterSnapshot { [weak self] in
                            guard let self, !diagnosticDelivery.isCancelled else { return }
                            Array(self.livePlaybackEventListeners.values).forEach { $0(value) }
                        }
                    }
                case .whiteboardMediaProgramResult:
                    if let json = event.payloadJson {
                        whiteboardMediaEvents.emit(json, channel: .programResult,
                                                   validUntil: diagnosticDelivery, destination: nil)
                    }
                case .teachingToolsUpdated:
                    if let json = event.payloadJson {
                        toolSound.deliver(json, poll: soundPoll) { [weak self] cueId, room in
                            guard let self else { return false }
                            do {
                                return try self.withCore {
                                    guard self.initialized, self.classroomId == room else { return false }
                                    let data = try JSONSerialization.data(withJSONObject: ["operation": "claim_audio_cue", "cueId": cueId])
                                    try self.core.requestTeachingTools(requestJson: String(decoding: data, as: UTF8.self))
                                    return true
                                }
                            } catch { return false }
                        }
                        afterSnapshot { [weak self] in self?.teachingToolsListeners.forEach { $0(json) } }
                    }
                case .whiteboardSyncReceived:
                    if let json = event.payloadJson {
                        let opId = json.data(using: .utf8)
                            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                            .flatMap { $0["op_id"] as? String }
                            .flatMap { $0.isEmpty ? nil : $0 }
                            ?? "<missing>"
                        NSLog("[edusdk] whiteboard sync Core → UI opId=%@", opId)
                        whiteboardClassroomEvents.sync.emit(json, channel: .event,
                            validUntil: diagnosticDelivery, destination: .main)
                    }
                // 过程笔迹 20–60Hz：在事件线程直接投递，宿主自行解析并只回切一次主线程。
                // 这里先跳主线程只会让每个包在主线程队列里多排一轮。
                case .whiteboardLiveStrokeReceived:
                    if let json = event.payloadJson {
                        emitLiveStroke(json, validUntil: diagnosticDelivery)
                    }
                case .whiteboardMediaClock:
                    if let json = event.payloadJson {
                        whiteboardMediaEvents.emit(json, channel: .clock,
                                                   validUntil: diagnosticDelivery, destination: .main)
                    }
                case .whiteboardMediaReceived:
                    if let json = event.payloadJson { emitMedia(json, validUntil: diagnosticDelivery) }
                case .whiteboardSyncReloadRequested:
                    if let json = event.payloadJson,
                       let data = json.data(using: .utf8),
                       let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let coursewareId = value["coursewareId"] as? String,
                       let serverSeq = (value["serverSeq"] as? NSNumber)?.int64Value {
                        let request = WhiteboardSyncReloadRequest(
                            coursewareId: coursewareId,
                            serverSeq: serverSeq
                        )
                        whiteboardClassroomEvents.syncReload.emit(request, channel: .event,
                            validUntil: diagnosticDelivery, destination: .main)
                    }
                case .whiteboardRecoveryRequested:
                    if let json = event.payloadJson,
                       let data = json.data(using: .utf8),
                       let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let roomId = value["roomId"] as? String,
                       let generation = (value["generation"] as? NSNumber)?.int64Value {
                        let request = WhiteboardRecoveryRequest(
                            roomId: roomId,
                            generation: generation
                        )
                        whiteboardClassroomEvents.recovery.emit(request, channel: .event,
                            validUntil: diagnosticDelivery, destination: .main)
                    }
                case .imMessageReceived:
                    if let json = event.payloadJson,
                       let data = json.data(using: .utf8),
                       let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let message = ImMessage(
                            id: value["id"] as? String ?? "",
                            senderId: value["sender_id"] as? String ?? "",
                            content: value["content"] as? String ?? "",
                            sentAt: value["sent_at"] as? Int64
                        )
                        receivedMessages.append(message)
                    }
                case .onStageUsersChanged:
                    if let json = event.payloadJson {
                        let users = parseStageUsers(json)
                        afterSnapshot { [weak self] in
                            self?.onStageUsersListeners.forEach { $0(users) }
                        }
                    }
                case .membersChanged:
                    if let json = event.payloadJson {
                        let members = parseMembers(json)
                        afterSnapshot { [weak self] in
                            self?.membersListeners.forEach { $0(members) }
                        }
                    }
                case .userPermissionsChanged:
                    if let json = event.payloadJson {
                        let permissions = parseUserPermissions(json)
                        afterSnapshot { [weak self] in
                            self?.userPermissionsListeners.forEach { $0(permissions) }
                        }
                    }
                case .myStageStatusChanged:
                    if let json = event.payloadJson,
                       let data = json.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let status = MyStageStatus(
                            onStage: object["onStage"] as? Bool ?? false,
                            handRaised: object["handRaised"] as? Bool
                        )
                        afterSnapshot { [weak self] in
                            self?.myStageStatusListeners.forEach { $0(status) }
                        }
                    }
                case .localScreenShareChanged:
                    if let json = event.payloadJson,
                       let data = json.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let sharing = object["sharing"] as? Bool ?? false
                        afterSnapshot { [weak self] in
                            self?.localScreenShareListeners.forEach { $0(sharing) }
                        }
                    }
                case .screenShareUsersChanged:
                    if let json = event.payloadJson,
                       let data = json.data(using: .utf8),
                       let userIds = try? JSONDecoder().decode([String].self, from: data) {
                        afterSnapshot { [weak self] in
                            self?.screenShareUsersListeners.forEach { $0(userIds) }
                        }
                    }
                case .mediaOpenHintChanged:
                    if let json = event.payloadJson,
                       let data = json.data(using: .utf8),
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        let audienceRaw = object["audience"] as? String ?? "student"
                        let hint = MediaOpenHint(
                            visible: object["visible"] as? Bool ?? false,
                            audience: audienceRaw == "teacher" ? .teacher : .student
                        )
                        cachedMediaOpenHint = hint
                        afterSnapshot { [weak self] in
                            self?.mediaOpenHintListeners.forEach { $0(hint) }
                        }
                    }
                case .streamInfoChanged:
                    if let json = event.payloadJson {
                        let streams = Self.parseStreamInfos(json)
                        cachedStreamInfos = streams
                        afterSnapshot { [weak self] in
                            self?.streamInfoListeners.forEach { $0(streams) }
                        }
                    }
                case .teacherMutedMyMicrophone:
                    afterSnapshot { [weak self] in
                        self?.teacherMutedMicListeners.forEach { $0() }
                    }
                case .teacherMutedMyCamera:
                    afterSnapshot { [weak self] in
                        self?.teacherMutedCameraListeners.forEach { $0() }
                    }
                case .localAudioMuted, .localVideoMuted, .raisedHandListChanged:
                    break
                default:
                    break
                }
            }
            // No projection change means no JSON mapping and no UI publication.
            if classroomId == nil, let snapshots, snapshots.changedFields.contains(.continuation) {
                var prepared = readUiSnapshot()
                prepared.continuation = try snapshots.continuationJson.map {
                    try JSONDecoder().decode(ContinuationView.self, from: Data($0.utf8))
                }
                prepared.generation = snapshots.revision
                publishUiSnapshot(prepared, validUntil: diagnosticDelivery)
                afterSnapshot { [weak self] in
                    guard !diagnosticDelivery.isCancelled, let self else { return }
                    let continuation = self.readUiSnapshot().continuation
                    Array(self.continuationListeners.values).forEach { $0(continuation) }
                }
            }
            if let id = classroomId, let snapshots {
                let previous = readUiSnapshot()
                func changed(_ field: RuntimeProjectionField) -> Bool {
                    previous.classInfo?.classroomId != id || snapshots.changedFields.contains(field)
                }
                let snap = snapshots.backend
                let room = snapshots.room
                let timer = snapshots.timer
                let policyJson = snapshots.interactionPolicyJson
                let messages = snapshots.imMessages
                let historyJson = snapshots.imHistoryJson
                let classroomViewJson = snapshots.classroomViewJson
                let title = lastClassroomTitle ?? snap.classroomTitle
                let classInfo = ClassInfo(
                    classroomId: id,
                    phase: mapMobilePhase(snap.classPhase),
                    lifecycleStatus: mapMobileLifecycleStatus(snap.lifecycleStatus),
                    title: title,
                    timerMode: {
                        switch timer.mode {
                        case .hidden: return .hidden
                        case .countdown: return .countdown
                        case .elapsed: return .elapsed
                        }
                    }(),
                    timerSeconds: timer.seconds.map { Int64(clamping: $0) }
                )
                let onStageUsers = changed(.backend) ? snap.onStageUserIds.map {
                    StageUser(userId: $0, displayName: nil, onStage: true)
                } : previous.onStageUsers
                let members = changed(.backend) ? snap.members.map { item in
                    ClassroomMember(
                        userId: item.userId,
                        role: item.role,
                        stageStatus: item.stageStatus,
                        canUseMicrophone: nil,
                        canUseCamera: nil,
                        joinedAt: item.joinedAt,
                        displayName: item.displayName,
                        avatarUrl: item.avatarUrl
                    )
                } : previous.members
                let interactionPolicy = changed(.policy) ? try JSONDecoder().decode(
                    [ActionAvailability].self,
                    from: Data(policyJson.utf8)
                ) : previous.interactionPolicy
                let imMessages = changed(.messages) ? messages.map { message in
                    ImMessage(
                        id: message.id,
                        senderId: message.senderId,
                        content: message.content,
                        sentAt: Int64(message.sentAt)
                    )
                } : previous.imMessages
                guard !diagnosticDelivery.isCancelled, classroomId == id else { return }
                publishUiSnapshot(
                    SdkSnapshot(
                        continuation: changed(.continuation) ? try snapshots.continuationJson.map { try JSONDecoder().decode(ContinuationView.self, from: Data($0.utf8)) } : previous.continuation,
                        classroomView: changed(.view) ? try JSONDecoder().decode(ClassroomView.self, from: Data(classroomViewJson.utf8)) : previous.classroomView,
                        generation: snapshots.revision,
                        classInfo: classInfo,
                        onStageUsers: onStageUsers,
                        members: members,
                        memberCount: snap.memberCount,
                        membersNextCursor: snap.membersNextCursor,
                        interactionPolicy: interactionPolicy,
                        imMessages: imMessages,
                        imHistoryState: changed(.history) ? try JSONDecoder().decode(ImHistoryState.self, from: Data(historyJson.utf8)) : previous.imHistoryState,
                        bindableRemoteVideoUserIds: changed(.room) ? Set(room.bindableRemoteVideoUserIds) : previous.bindableRemoteVideoUserIds,
                        localVideoBindable: room.localVideoBindable,
                        localScreenSharing: room.localScreenSharing,
                        bindableRemoteScreenUserIds: changed(.room) ? Set(room.bindableRemoteScreenUserIds) : previous.bindableRemoteScreenUserIds,
                        needLive: snap.needLive,
                        liveStreams: changed(.backend) ? snap.liveStreams.map {
                            LiveStream(
                                streamName: $0.streamName,
                                publisherUserId: $0.publisherUserId,
                                streamType: $0.streamType,
                                url: $0.url,
                                muted: $0.muted,
                                expiresAt: $0.expiresAt,
                                playing: $0.playing
                            )
                        } : previous.liveStreams,
                        liveRelayVersion: snap.liveRelayVersion
                    ), validUntil: diagnosticDelivery
                )
                if changed(.continuation) {
                    afterSnapshot { [weak self] in
                        guard !diagnosticDelivery.isCancelled, let self else { return }
                        let continuation = self.readUiSnapshot().continuation
                        Array(self.continuationListeners.values).forEach { $0(continuation) }
                    }
                }
                emitClassInfo(id, mapMobilePhase(snap.classPhase), title: title, lifecycleStatus: mapMobileLifecycleStatus(snap.lifecycleStatus))
                if joinSuccessDue {
                    joinSuccessDue = false
                    emitJoinSuccess(classInfo: classInfo, validUntil: diagnosticDelivery)
                }
                // 快照是可绑判定的唯一来源，发布后立刻协调；Core 主动退房
                // （下台 → leave_rtc → reset）不产生任何厂商事件，只有这里能收敛。
                if changed(.room) { reconcileVideoBinds() }
            }
            // One-shot events survive a batch with no presentation change.
            for message in receivedMessages {
                afterSnapshot { [weak self] in
                    guard !diagnosticDelivery.isCancelled else { return }
                    self?.imMessageListeners.forEach { $0(message) }
                }
            }
            if !callbacks.isEmpty {
                let delivery = callbacks
                snapshotPublication.deliverAfterPublication(validUntil: diagnosticDelivery) {
                    delivery.forEach { $0() }
                }
            }
        } catch {
            // An invalid native batch cannot leave the dedicated shutdown waiter parked forever.
            destroyStateLock.lock()
            let releaseShutdown = destroyStarted && !shutdownFinished
            if releaseShutdown { shutdownFinished = true }
            destroyStateLock.unlock()
            if releaseShutdown { shutdownCompletion.signal() }
            DispatchQueue.main.async { [weak self] in
                self?.errorListeners.forEach {
                    $0(SdkError(code: .internal, message: error.localizedDescription))
                }
            }
        }
    }

    func readUiSnapshot() -> SdkSnapshot { snapshotPublication.read() }

    private func publishUiSnapshot(_ snapshot: SdkSnapshot, validUntil poll: DispatchWorkItem) {
        snapshotPublication.publish(snapshot, validUntil: poll)
    }

    private func runQuery<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queryQueue.async {
                continuation.resume(with: Result(catching: operation))
            }
        }
    }

    /// 原始过程笔迹交由回调worker投递；不持锁执行宿主代码、不先跳主线程。
    private func emitLiveStroke(_ payloadJson: String, validUntil poll: DispatchWorkItem) {
        whiteboardClassroomEvents.liveStroke.emit(payloadJson, channel: .event,
            validUntil: poll, destination: nil)
    }

    private func emitMedia(_ payloadJson: String, validUntil poll: DispatchWorkItem) {
        whiteboardMediaEvents.emit(payloadJson, channel: .media, validUntil: poll, destination: nil)
    }

    private static func mapCoreErrorCode(_ name: String) -> SdkErrorCode {
        switch name.lowercased().replacingOccurrences(of: "_", with: "") {
        case "notinitialized": return .notInitialized
        case "alreadyinitialized": return .alreadyInitialized
        case "invalidargument": return .invalidArgument
        case "invalidstate": return .invalidState
        case "roomnotfound": return .classroomNotFound
        case "permissiondenied": return .permissionDenied
        case "networkerror": return .networkError
        case "contractmismatch": return .contractMismatch
        case "joinaborted": return .joinAborted
        case "classroomnotstarted": return .classroomNotStarted
        case "classroomended": return .classroomEnded
        case "classroomexpired": return .classroomExpired
        case "improvidererror": return .imProviderError
        case "whiteboardprovidererror": return .whiteboardProviderError
        case "rtcprovidererror": return .rtcProviderError
        case "liveprovidererror": return .liveProviderError
        case "uiresourceerror": return .uiResourceError
        case "providernotregistered": return .providerNotRegistered
        case "providererror": return .providerError
        case "notimplemented": return .notImplemented
        default: return .internal
        }
    }

    private static func parseStreamInfos(_ json: String) -> [StreamInfo] {
        guard let data = json.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            let userId = (item["user_id"] as? String) ?? (item["userId"] as? String) ?? ""
            guard !userId.isEmpty else { return nil }
            let audioMuted = (item["audio_muted"] as? Bool) ?? (item["audioMuted"] as? Bool) ?? true
            let videoMuted = (item["video_muted"] as? Bool) ?? (item["videoMuted"] as? Bool) ?? true
            return StreamInfo(userId: userId, audioMuted: audioMuted, videoMuted: videoMuted)
        }
    }

    private func parseMembers(_ json: String) -> [ClassroomMember] {
        guard let data = json.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let userId = item["user_id"] as? String, !userId.isEmpty else { return nil }
            return ClassroomMember(
                userId: userId,
                role: item["role"] as? String,
                stageStatus: item["stage_status"] as? String,
                canUseMicrophone: nil,
                canUseCamera: nil,
                joinedAt: item["joined_at"] as? String,
                displayName: item["display_name"] as? String,
                avatarUrl: item["avatar_url"] as? String
            )
        }
    }

    private func parseStageUsers(_ json: String) -> [StageUser] {
        guard let data = json.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let userId = item["user_id"] as? String, !userId.isEmpty else { return nil }
            return StageUser(
                userId: userId,
                displayName: item["display_name"] as? String,
                onStage: item["on_stage"] as? Bool ?? true
            )
        }
    }

    private func parseUserPermissions(_ json: String) -> [UserPermission] {
        guard let data = json.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }
        return items.compactMap { item in
            guard let userId = item["user_id"] as? String, !userId.isEmpty else { return nil }
            return UserPermission(
                userId: userId,
                canUseMicrophone: item["can_use_microphone"] as? Bool,
                canUseCamera: item["can_use_camera"] as? Bool,
                canSendMessage: item["can_send_message"] as? Bool,
                canUseWhiteboard: item["can_use_whiteboard"] as? Bool,
                canScreenShare: item["can_screen_share"] as? Bool
            )
        }
    }

    private func emitClassInfo(_ classroomId: String, _ phase: ClassPhase, title: String?, lifecycleStatus: ClassroomLifecycleStatus) {
        let key = "\(classroomId)|\(phase.rawValue)|\(lifecycleStatus.rawValue)|\(title ?? "")"
        if key == lastEmittedClassKey { return }
        lastEmittedClassKey = key
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lastClassroomTitle = title
        }
        let info = ClassInfo(
            classroomId: classroomId,
            phase: phase,
            lifecycleStatus: lifecycleStatus,
            title: title ?? lastClassroomTitle
        )
        DispatchQueue.main.async { [weak self] in
            self?.classInfoListeners.forEach { $0(info) }
        }
    }

    private func emitOnMain(_ block: @escaping () -> Void) {
        DispatchQueue.main.async(execute: block)
    }

    /// join 响应刚落地时先把上台列表与本人资料交给 UI，让骨架屏能显示真实内容。
    /// 课堂相位要等 Core 落地 join，所以这里不发 onClassInfoChanged。
    private func emitClassSnapshotOnMain(_ join: JoinHttpClient.JoinPayload) {
        let stageUsers = join.joinStageUsers()
        emitOnMain { [weak self] in
            guard let self else { return }
            self.onStageUsersListeners.forEach { $0(stageUsers) }
            self.userProfileListeners.forEach {
                $0(UserProfile(
                    userId: join.session.eduUserId ?? "unknown",
                    displayName: join.session.nickname,
                    avatarUrl: join.session.avatar,
                    role: nil
                ))
            }
        }
    }

    /// 必要域就绪时只回调一次；可选域的后续推进走 `onJoinProgress`。
    /// 相位与生命周期状态取本轮 Core 快照，宿主不再映射 join 响应。
    private func emitJoinSuccess(classInfo: ClassInfo, validUntil poll: DispatchWorkItem) {
        guard let join = pendingJoinPayload else { return }
        pendingJoinPayload = nil
        let success = join.toJoinSuccessInfo(classInfo: classInfo)
        whiteboardClassroomEvents.joinSuccess.emit(success, channel: .event,
            validUntil: poll, destination: .main)
    }

    private func emitWhiteboardCredentials(_ credentials: WhiteboardCredentials?) {
        destroyStateLock.lock()
        let poll = livePlaybackDelivery
        destroyStateLock.unlock()
        whiteboardClassroomEvents.credentials.emit(credentials, channel: .event,
            validUntil: poll, destination: .main)
    }

    private func parseJoinProgress(_ json: String) -> JoinProgress? {
        guard let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return JoinProgress(
            phase: JoinPhase(wire: value["phase"] as? String ?? ""),
            im: DomainState(wire: value["im"] as? String ?? ""),
            whiteboard: DomainState(wire: value["whiteboard"] as? String ?? ""),
            rtc: DomainState(wire: value["rtc"] as? String ?? "")
        )
    }

    private enum Tokens {
        static let destroyQueueLabel = "edusdk.destroy"
        static let coreQueueLabel = "edusdk.core"
        static let backendEffectQueueLabel = "edusdk.effects.backend"
        static let backendQueryEffectQueueLabel = "edusdk.effects.backend-query"
        static let backendCommandEffectQueueLabel = "edusdk.effects.backend-command"
        static let imEffectQueueLabel = "edusdk.effects.im"
        static let rtcEffectQueueLabel = "edusdk.effects.rtc"
        static let whiteboardEffectQueueLabel = "edusdk.effects.whiteboard"
        static let liveEffectQueueLabel = "edusdk.effects.live"
        static let liveStrokeEffectQueueLabel = "edusdk.effects.live-stroke"
        static let effectPumpQueueLabel = "edusdk.effects.pump"
        static let eventLoopQueueLabel = "edusdk.events.poll"
        static let eventPumpQueueLabel = "edusdk.events.pump"
        static let whiteboardSendQueueLabel = "edusdk.whiteboard.send"
        static let liveStrokeSendQueueLabel = "edusdk.whiteboard.live-stroke-send"
        static let telemetryQueueLabel = "edusdk.telemetry"
        static let pollLeewayMilliseconds = 20
    }

    /// 遥测回执用的 Core 错误码名；仅驱动退避重试，不会到达业务。
    private static let telemetryNetworkFailureCode = "NETWORK_ERROR"

    /// 401/403：凭证对不上，Core 删除该批次。
    private static let telemetryUnauthorizedCode = "PERMISSION_DENIED"

    /// 400/413：ingest 整批拒绝，Core 删除该批次。
    private static let telemetryRejectedCode = "INVALID_ARGUMENT"

    /// 401/403/400 删除 outbox；其余按网络失败退避。
    private static func telemetryFailureCode(for error: Error) -> String {
        switch (error as? SdkError)?.kind {
        case .permissionDenied: return telemetryUnauthorizedCode
        case .invalidArgument: return telemetryRejectedCode
        default: return telemetryNetworkFailureCode
        }
    }

    func enqueueRtc(_ block: @escaping () -> Void) {
        effectQueues[HostEffectLanes.rtc]?.async(execute: block)
    }

    /// 与 Rust `HostEffectLane` 的 serde 表示逐值对应。
    private enum HostEffectLanes {
        static let backend = "backend"
        static let backendQuery = "backend_query"
        static let backendCommand = "backend_command"
        static let im = "im"
        static let rtc = "rtc"
        static let whiteboard = "whiteboard"
        static let live = "live"
        static let liveStroke = "live_stroke"
    }

    /// 与 Rust `HostEffectDelivery` 的 serde 表示逐值对应。
    private enum HostEffectDeliveries {
        static let required = "required"
    }

    struct HostEffectEnvelope {
        let id: UInt64
        let lane: String
        let delivery: String
        let action: [String: Any]

        var blocksCaller: Bool { delivery == HostEffectDeliveries.required }
    }

    private func mapMobilePhase(_ phase: MobileClassPhase) -> ClassPhase {
        switch phase {
        case .entered: return .entered
        case .inClass: return .inClass
        case .ended: return .ended
        case .idle: return .idle
        }
    }


    private func mapMobileLifecycleStatus(_ status: MobileClassroomLifecycleStatus) -> ClassroomLifecycleStatus {
        switch status {
        case .notStarted: return .notStarted
        case .inProgress: return .inProgress
        case .ended: return .ended
        case .expired: return .expired
        }
    }
}
