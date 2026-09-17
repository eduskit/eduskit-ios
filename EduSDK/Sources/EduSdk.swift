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
    private var initialized = false
    var classroomId: String?
    private var pollTimer: DispatchSourceTimer?
    private var whiteboardCredentialRefreshWorkItem: DispatchWorkItem?
    private var currentWhiteboardCredentials: WhiteboardCredentials?
    private let eventLoopQueue = DispatchQueue(label: Tokens.eventLoopQueueLabel, qos: .userInitiated)
    /// 事件解析与派发的串行队列。
    ///
    /// 去重状态（`lastEmittedClassKey`、`pendingJoinSuccess`）只在这条队列上读写，
    /// 因此 `coreQueue` 不必为了串行化而覆盖整个事件循环。
    private let eventPumpQueue = DispatchQueue(label: Tokens.eventPumpQueueLabel, qos: .userInitiated)
    private static let coreQueueKey = DispatchSpecificKey<UInt8>()
    private let coreQueue = DispatchQueue(label: Tokens.coreQueueLabel)
    /// 通道由 Core 随副作用下发（`HostEffect.lane`），平台不再按 action 类型前缀推断。
    ///
    /// `liveStroke` 必须独立于 `im`：IM 登录、聊天和最终白板 op 都要等回执，
    /// 共用一条队列会让书写时的高频笔迹排在一次 IM 往返之后，反之亦然。
    let effectQueues: [String: DispatchQueue] = [
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
    private let effectPumpStateLock = NSLock()
    private var effectPumpScheduled = false
    /// DrawsKit 高频发送只入队；Core 与 IM 回执等待不得占用主线程。
    private let whiteboardSendQueue = DispatchQueue(label: Tokens.whiteboardSendQueueLabel)
    /// 过程笔迹出站入口队列。与 `whiteboardSendQueue` 分开：最终 op 的发送会同步等
    /// IM 回执，共用队列时每次抬笔都会把后续笔迹堵住一次往返。
    private let liveStrokeSendQueue = DispatchQueue(label: Tokens.liveStrokeSendQueueLabel)
    /// 遥测独占一条队列：复用业务域队列会让上报排在进课副作用之后，
    /// 甚至被 IM 登录的长超时拖住；遥测是尽力而为的旁路，必须完全让路。
    private let telemetryQueue = DispatchQueue(label: Tokens.telemetryQueueLabel)
    private let queryQueue = DispatchQueue(label: "com.edukits.edusdk.query", qos: .userInitiated)
    private let telemetryHost = TelemetryHost()
    private let telemetryDraining = NSLock()
    private var telemetryDrainScheduled = false
    private let destroyStateLock = NSLock()
    private var destroyStarted = false
    private var backgroundObserver: NSObjectProtocol?
    private var foregroundObserver: NSObjectProtocol?
    /// 持有 OpenImIosAdapter（AnyObject 避免 SPM 无 Adapter 时编译失败）
    var imAdapter: AnyObject?
    var imConnectionGeneration: UInt64?
    var imRecoveryWorkItem: DispatchWorkItem?
    /// 持有 TencentTrtcIosAdapter（由 SwiftPM 解析 Vendor binary target）
    var rtcAdapter: AnyObject?
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
    var pendingJoinSuccess: JoinSuccessInfo?

    var classInfoListeners: [(ClassInfo) -> Void] = []
    var joinSuccessListeners: [(JoinSuccessInfo) -> Void] = []
    var joinProgressListeners: [(JoinProgress) -> Void] = []
    var whiteboardCredentialsListeners: [(WhiteboardCredentials?) -> Void] = []
    var onStageUsersListeners: [([StageUser]) -> Void] = []
    var membersListeners: [([ClassroomMember]) -> Void] = []
    var userPermissionsListeners: [([UserPermission]) -> Void] = []
    var myStageStatusListeners: [(MyStageStatus) -> Void] = []
    var userProfileListeners: [(UserProfile) -> Void] = []
    var imMessageListeners: [(ImMessage) -> Void] = []
    var whiteboardSyncListeners: [(String) -> Void] = []
    /// 过程笔迹回调在事件线程执行，与主线程的订阅/退订并发，因此该数组必须加锁访问。
    private var whiteboardLiveStrokeListeners: [(String) -> Void] = []
    private let liveStrokeListenerLock = NSLock()
    var whiteboardSyncReloadListeners: [(WhiteboardSyncReloadRequest) -> Void] = []
    var whiteboardRecoveryListeners: [(WhiteboardRecoveryRequest) -> Void] = []
    var errorListeners: [(SdkError) -> Void] = []
    var mediaOpenHintListeners: [(MediaOpenHint) -> Void] = []
    var streamInfoListeners: [([StreamInfo]) -> Void] = []
    var teacherMutedMicListeners: [() -> Void] = []
    var teacherMutedCameraListeners: [() -> Void] = []
    private var cachedStreamInfos: [StreamInfo] = []
    private var cachedMediaOpenHint = MediaOpenHint(visible: false, audience: .student)
    var lastClassroomTitle: String?
    private var lastEmittedClassKey: String?
    private var classroomCourseware: [Courseware] = []
    /// Render-facing getters read only this precomputed value. Core/JSON work stays on eventPumpQueue.
    private let uiSnapshotLock = NSLock()
    private var uiSnapshot = SdkSnapshot()
    private var sdkSnapshotListeners: [UUID: (SdkSnapshot) -> Void] = [:]

    private init(createOptions: EduSdkCreateOptions) {
        self.createOptions = createOptions
        coreQueue.setSpecific(key: Self.coreQueueKey, value: 1)
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
        joinSuccessListeners.append(listener)
        return { [weak self] in
            self?.joinSuccessListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onJoinProgress(_ listener: @escaping (JoinProgress) -> Void) -> () -> Void {
        joinProgressListeners.append(listener)
        return { [weak self] in
            self?.joinProgressListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    /// Core 判定需要白板时下发凭证；关闭或不需要白板时回调 `nil`。
    @discardableResult
    public func onWhiteboardCredentials(
        _ listener: @escaping (WhiteboardCredentials?) -> Void
    ) -> () -> Void {
        whiteboardCredentialsListeners.append(listener)
        return { [weak self] in
            self?.whiteboardCredentialsListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
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
        let id = UUID()
        uiSnapshotLock.lock()
        sdkSnapshotListeners[id] = listener
        let initial = uiSnapshot
        uiSnapshotLock.unlock()
        DispatchQueue.main.async { listener(initial) }
        return { [weak self] in
            guard let self else { return }
            self.uiSnapshotLock.lock()
            self.sdkSnapshotListeners.removeValue(forKey: id)
            self.uiSnapshotLock.unlock()
        }
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
        whiteboardSyncListeners.append(listener)
        return { [weak self] in
            self?.whiteboardSyncListeners.removeAll { $0 as AnyObject === listener as AnyObject }
        }
    }

    @discardableResult
    public func onWhiteboardLiveStrokeReceived(_ listener: @escaping (String) -> Void) -> () -> Void {
        liveStrokeListenerLock.lock()
        whiteboardLiveStrokeListeners.append(listener)
        liveStrokeListenerLock.unlock()
        return { [weak self] in
            guard let self else { return }
            self.liveStrokeListenerLock.lock()
            self.whiteboardLiveStrokeListeners.removeAll {
                $0 as AnyObject === listener as AnyObject
            }
            self.liveStrokeListenerLock.unlock()
        }
    }

    @discardableResult
    public func onWhiteboardSyncReloadRequested(
        _ listener: @escaping (WhiteboardSyncReloadRequest) -> Void
    ) -> () -> Void {
        whiteboardSyncReloadListeners.append(listener)
        return { [weak self] in
            self?.whiteboardSyncReloadListeners.removeAll {
                $0 as AnyObject === listener as AnyObject
            }
        }
    }

    @discardableResult
    public func onWhiteboardRecoveryRequested(
        _ listener: @escaping (WhiteboardRecoveryRequest) -> Void
    ) -> () -> Void {
        whiteboardRecoveryListeners.append(listener)
        return { [weak self] in
            self?.whiteboardRecoveryListeners.removeAll {
                $0 as AnyObject === listener as AnyObject
            }
        }
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

    public func initialize(config: InitializeConfig = InitializeConfig()) throws {
        try withCore {
            let appId = config.appId ?? createOptions.appId
            let backendUrl = config.backendUrl ?? createOptions.backendUrl
            try core.`init`(config: InitConfig(
                appId: appId,
                backendBaseUrl: backendUrl,
                rtcProvider: "mock",
                imProvider: "openim",
                liveProvider: "mock",
                whiteboardProvider: "mock",
                userToken: createOptions.userToken,
                deviceId: telemetryHost.deviceId,
                platform: telemetryHost.platform,
                sdkVersion: telemetryHost.sdkVersion,
                appVersion: createOptions.appVersion
            ))
            initialized = true
        }
        startEventLoop()
        observeBackground()
        // Core 在 init 时会请求读取上次遗留的落盘批次，这里把它执行掉。
        drainTelemetryEffects()
        pumpEvents()
    }

    public func destroy() {
        destroyStateLock.lock()
        if destroyStarted {
            destroyStateLock.unlock()
            return
        }
        destroyStarted = true
        destroyStateLock.unlock()
        let clearListeners: () -> Void = { [weak self] in self?.clearPublicListeners() }
        if Thread.isMainThread {
            clearListeners()
        } else {
            DispatchQueue.main.async(execute: clearListeners)
        }
        if Thread.isMainThread {
            effectPumpQueue.async { [self] in destroyBlocking() }
        } else {
            destroyBlocking()
        }
    }

    private func destroyBlocking() {
        whiteboardCredentialRefreshWorkItem?.cancel()
        whiteboardCredentialRefreshWorkItem = nil
        currentWhiteboardCredentials = nil
        stopEventLoop()
        // 先解绑：通知晚于 shutdown 触发就会碰到已销毁的 Core。
        if let backgroundObserver {
            NotificationCenter.default.removeObserver(backgroundObserver)
            self.backgroundObserver = nil
        }
        if let foregroundObserver {
            NotificationCenter.default.removeObserver(foregroundObserver)
            self.foregroundObserver = nil
        }
        // 必须在 shutdown 之前同步发出：Core 一销毁，缓冲里的事件就再也取不出来了。
        if withCore({ initialized }) { flushTelemetryBlocking() }
        invalidateVideoBinds()
        teardownIm()
        teardownRtc()
        pendingJoinSuccess = nil
        withCore {
            if initialized {
                try? core.shutdown()
                initialized = false
            }
        }
        classroomId = nil
        lastClassroomTitle = nil
        lastEmittedClassKey = nil
        classroomCourseware = []
    }

    /// Listener 属于 UI-facing 状态，只在主线程增删，避免后台销毁与回调遍历并发修改数组。
    private func clearPublicListeners() {
        classInfoListeners.removeAll()
        joinSuccessListeners.removeAll()
        joinProgressListeners.removeAll()
        whiteboardCredentialsListeners.removeAll()
        onStageUsersListeners.removeAll()
        membersListeners.removeAll()
        myStageStatusListeners.removeAll()
        userProfileListeners.removeAll()
        imMessageListeners.removeAll()
        whiteboardSyncListeners.removeAll()
        liveStrokeListenerLock.lock()
        whiteboardLiveStrokeListeners.removeAll()
        liveStrokeListenerLock.unlock()
        whiteboardSyncReloadListeners.removeAll()
        whiteboardRecoveryListeners.removeAll()
        errorListeners.removeAll()
        mediaOpenHintListeners.removeAll()
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

    public func loadMembers(_ cursor: String? = nil) throws {
        try ensureInitialized()
        try withCore { try core.loadMembers(cursor: cursor ?? "") }
        try drainHostEffects()
        pumpEvents()
    }

    public func leaveClassroom() throws {
        cachedMediaOpenHint = MediaOpenHint(visible: false, audience: .student)
        try ensureInitialized()
        invalidateVideoBinds()
        try withCore { try core.leaveRoom() }
        try drainHostEffects()
        pumpEvents()
        classroomId = nil
        classroomCourseware = []
    }

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
        try ensureInitialized()
        try withCore { try core.endClass() }
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

    public func getImMessageList(options: ImMessageListOptions? = nil) throws -> [ImMessage] {
        try ensureInitialized()
        let messages = readUiSnapshot().imMessages
        guard let limit = options?.limit, limit >= 0 else { return messages }
        return Array(messages.suffix(Int(limit)))
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
        #if os(iOS)
        ensureRtcAdapter()?.setLocalAudioLevelListener(listener)
        #endif
    }

    public func playTestTone() {
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

    public func mediaOpenHint() -> MediaOpenHint {
        cachedMediaOpenHint
    }

    /// 可绑判定唯一实现在 Core；这里只读已发布的快照，不再另建缓存。
    ///
    /// 刻意不在绑定路径上直连 Core：最终的 Vendor 调用发生在主线程，
    /// 而 uiSnapshot 是后台 pump 预计算好的不可变值，读它不会等锁也不会陈旧。
    func remoteVideoBindable(userId: String) -> Bool {
        readUiSnapshot().bindableRemoteVideoUserIds.contains(userId)
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
    private func drainHostEffects() throws {
        if Thread.isMainThread {
            scheduleEffectPump()
            return
        }
        var firstError: Error?
        while true {
            let effects = try withCore { try core.pollHostEffects() }
            if effects.isEmpty {
                if let firstError { throw firstError }
                return
            }
            var order: [String] = []
            var byLane: [String: [HostEffectEnvelope]] = [:]
            for raw in effects {
                let effect = try Self.parseHostEffect(raw)
                if byLane[effect.lane] == nil { order.append(effect.lane) }
                byLane[effect.lane, default: []].append(effect)
            }
            let group = DispatchGroup()
            let lock = NSLock()
            var batchError: Error?
            for lane in order {
                guard let bucket = byLane[lane] else { continue }
                let queue = effectQueues[lane] ?? DispatchQueue(label: "edusdk.effects.\(lane)")
                if bucket.contains(where: \.blocksCaller) {
                    queue.async(group: group) { [weak self] in
                        guard let self, let error = self.runLaneChain(bucket) else { return }
                        lock.lock()
                        if batchError == nil { batchError = error }
                        lock.unlock()
                    }
                } else {
                    // 可选与易失副作用继续推进，但不占住公开 API 和 UI 操作队列。
                    queue.async { [weak self] in
                        _ = self?.runLaneChain(bucket)
                    }
                }
            }
            group.wait()
            if firstError == nil { firstError = batchError }
        }
    }

    /// 去重周期性 drain，避免 IM 慢回执期间每 100ms 往串行队列堆积一个任务。
    private func scheduleEffectPump() {
        destroyStateLock.lock()
        let isDestroying = destroyStarted
        destroyStateLock.unlock()
        guard !isDestroying else { return }
        effectPumpStateLock.lock()
        guard !effectPumpScheduled else {
            effectPumpStateLock.unlock()
            return
        }
        effectPumpScheduled = true
        effectPumpStateLock.unlock()
        effectPumpQueue.async { [weak self] in
            guard let self else { return }
            defer {
                self.effectPumpStateLock.lock()
                self.effectPumpScheduled = false
                self.effectPumpStateLock.unlock()
                self.drainTelemetryEffects()
            }
            do {
                try self.drainHostEffects()
                self.pumpEvents()
            } catch {
                let sdkError = SdkError(code: .providerError, message: error.localizedDescription)
                DispatchQueue.main.async { [weak self] in
                    self?.errorListeners.forEach { $0(sdkError) }
                }
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
            self?.flushTelemetry()
        }
        if foregroundObserver == nil {
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
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
        guard initialized else { return }
        telemetryDraining.lock()
        if telemetryDrainScheduled {
            telemetryDraining.unlock()
            return
        }
        telemetryDrainScheduled = true
        telemetryDraining.unlock()

        telemetryQueue.async { [weak self] in
            guard let self else { return }
            self.runTelemetryEffects()
            self.telemetryDraining.lock()
            self.telemetryDrainScheduled = false
            self.telemetryDraining.unlock()
        }
    }

    private func runTelemetryEffects() {
        while true {
            let effects = withCore { core.pollTelemetryEffects() }
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

    /// destroy 路径：必须在当前线程发完再返回，否则紧随其后的 shutdown 会让这批永远消失。
    private func flushTelemetryBlocking() {
        withCore { core.flushTelemetry() }
        runTelemetryEffects()
    }

    /// 单条通道内保持 FIFO：同通道副作用之间存在顺序依赖（如登录先于发信令）。
    private func runLaneChain(_ effects: [HostEffectEnvelope]) -> Error? {
        var firstError: Error?
        for effect in effects {
            do {
                let payload = try executeHostEffect(effect.action)
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
                try? withCore {
                    let outcome: [String: Any]
                    if let http = error as? HostHttpFailure {
                        outcome = ["status": "http_failure", "status_code": http.statusCode, "message": http.localizedDescription]
                    } else {
                        outcome = ["status": "failure", "code": Self.hostEffectFailureCode(effect.lane), "message": error.localizedDescription]
                    }
                    try completeHostEffect(id: effect.id, outcome: outcome)
                }
                if firstError == nil { firstError = error }
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
    }

    private func executeHostEffect(_ action: [String: Any]) throws -> Any {
        let type = action["type"] as? String ?? ""
        switch type {
        case "http":
            let payload = try JoinHttpClient.executeEffect(
                method: action["method"] as? String ?? "GET",
                url: action["url"] as? String ?? "",
                headers: action["headers"] as? [[String]] ?? [],
                body: action["body"] as? String
            )
            if let url = action["url"] as? String,
               url.range(of: "/v1/classrooms/[^/]+/join(?:\\?.*)?$", options: .regularExpression) != nil {
                let join = try JoinHttpClient.parseJoinEffect(payload)
                let success = join.toJoinSuccessInfo()
                withCore {
                    classroomCourseware = join.coursewares
                    lastClassroomTitle = success.classroom.name
                    classroomId = success.classroom.classroomId
                    // onJoinSuccess 推迟到 Core 判定必要域就绪（RoomJoined）时再发。
                    pendingJoinSuccess = success
                }
                if let ingest = join.telemetryIngestUrl, !ingest.isEmpty {
                    telemetryHost.ingestEndpoint = ingest
                }
                emitClassSnapshotOnMain(success)
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
        case "im_disconnect": teardownIm()
        case "im_send_signal":
            let data = try JSONSerialization.data(withJSONObject: action["envelope"] ?? [:])
            try executeWhiteboardEnvelope(String(decoding: data, as: UTF8.self))
        case "im_send_text": try sendTextMessage(action["content"] as? String ?? "")
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
            let credentials = WhiteboardCredentials(
                appId: action["app_id"] as? String ?? "",
                roomId: action["room_id"] as? String ?? "",
                userId: action["user_id"] as? String ?? "",
                token: action["token"] as? String ?? "",
                role: (action["role"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                expiresAt: (action["expires_at"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
            currentWhiteboardCredentials = credentials
            emitWhiteboardCredentials(credentials)
        case "whiteboard_update_credentials":
            guard let current = currentWhiteboardCredentials else {
                throw SdkError(code: .providerError, message: "whiteboard credentials are not initialized")
            }
            let updated = WhiteboardCredentials(
                appId: current.appId,
                roomId: current.roomId,
                userId: current.userId,
                token: action["token"] as? String ?? "",
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
        case "whiteboard_close":
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
        default:
            throw SdkError(code: .providerError, message: "unsupported host effect: \(type)")
        }
        return NSNull()
    }

    private func ensureInitialized() throws {
        if !initialized { throw sdkError(.notInitialized, "call initialize() first") }
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

    private func startEventLoop() {
        eventLoopQueue.async { [weak self] in
            guard let self, self.initialized, self.pollTimer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.eventLoopQueue)
            timer.schedule(
                deadline: .now(),
                repeating: Tokens.pollInterval,
                leeway: .milliseconds(Tokens.pollLeewayMilliseconds)
            )
            timer.setEventHandler { [weak self] in
                guard let self else { return }
                self.pumpEvents()
                // IM 信令也会让 Core 补下发副作用（如刷新成员以更新 needRtc），
                // 没有后台冲刷它们会一直等到下一次公开 API 调用。
                self.scheduleEffectPump()
            }
            self.pollTimer = timer
            timer.resume()
        }
    }

    private func stopEventLoop() {
        eventLoopQueue.async { [weak self] in
            guard let self, let timer = self.pollTimer else { return }
            timer.setEventHandler {}
            timer.cancel()
            self.pollTimer = nil
        }
    }

    /// 排空 Core 事件队列。始终异步：调用方（含 Vendor 回调线程与主线程）不为事件解析付费。
    func pumpEvents() {
        eventPumpQueue.async { [weak self] in self?.drainCoreEvents() }
    }

    private func drainCoreEvents() {
        do {
            // coreQueue 只在真正调用 Core 时持有。此前整个事件循环都包在 withCore 里，
            // 书写期间的高频事件解析会把它长期占满，其它调用方只能排队。
            let events: [Event] = try withCore {
                guard initialized else { return [] }
                return try core.pollEvents()
            }
            for event in events {
                switch event.kind {
                case .roomLeft:
                    break
                case .error:
                    if let e = event.error {
                        DispatchQueue.main.async { [weak self] in
                            self?.errorListeners.forEach {
                                $0(SdkError(code: Self.mapCoreErrorCode(String(describing: e.code)), message: e.message))
                            }
                        }
                    }
                case .roomJoined:
                    emitJoinSuccess()
                case .joinProgressChanged:
                    if let json = event.payloadJson, let progress = parseJoinProgress(json) {
                        DispatchQueue.main.async { [weak self] in
                            self?.joinProgressListeners.forEach { $0(progress) }
                        }
                    }
                case .whiteboardSyncReceived:
                    if let json = event.payloadJson {
                        let opId = json.data(using: .utf8)
                            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                            .flatMap { $0["op_id"] as? String }
                            .flatMap { $0.isEmpty ? nil : $0 }
                            ?? "<missing>"
                        NSLog("[edusdk] whiteboard sync Core → UI opId=%@", opId)
                        DispatchQueue.main.async { [weak self] in
                            self?.whiteboardSyncListeners.forEach { $0(json) }
                        }
                    }
                // 过程笔迹 20–60Hz：在事件线程直接投递，宿主自行解析并只回切一次主线程。
                // 这里先跳主线程只会让每个包在主线程队列里多排一轮。
                case .whiteboardLiveStrokeReceived:
                    if let json = event.payloadJson {
                        emitLiveStroke(json)
                    }
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
                        DispatchQueue.main.async { [weak self] in
                            self?.whiteboardSyncReloadListeners.forEach { $0(request) }
                        }
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
                        DispatchQueue.main.async { [weak self] in
                            self?.whiteboardRecoveryListeners.forEach { $0(request) }
                        }
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
                        DispatchQueue.main.async { [weak self] in
                            self?.imMessageListeners.forEach { $0(message) }
                        }
                    }
                case .onStageUsersChanged:
                    if let json = event.payloadJson {
                        let users = parseStageUsers(json)
                        DispatchQueue.main.async { [weak self] in
                            self?.onStageUsersListeners.forEach { $0(users) }
                        }
                    }
                case .membersChanged:
                    if let json = event.payloadJson {
                        let members = parseMembers(json)
                        DispatchQueue.main.async { [weak self] in
                            self?.membersListeners.forEach { $0(members) }
                        }
                    }
                case .userPermissionsChanged:
                    if let json = event.payloadJson {
                        let permissions = parseUserPermissions(json)
                        DispatchQueue.main.async { [weak self] in
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
                        DispatchQueue.main.async { [weak self] in
                            self?.myStageStatusListeners.forEach { $0(status) }
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
                        DispatchQueue.main.async { [weak self] in
                            self?.mediaOpenHintListeners.forEach { $0(hint) }
                        }
                    }
                case .streamInfoChanged:
                    if let json = event.payloadJson {
                        let streams = Self.parseStreamInfos(json)
                        cachedStreamInfos = streams
                        DispatchQueue.main.async { [weak self] in
                            self?.streamInfoListeners.forEach { $0(streams) }
                        }
                    }
                case .teacherMutedMyMicrophone:
                    DispatchQueue.main.async { [weak self] in
                        self?.teacherMutedMicListeners.forEach { $0() }
                    }
                case .teacherMutedMyCamera:
                    DispatchQueue.main.async { [weak self] in
                        self?.teacherMutedCameraListeners.forEach { $0() }
                    }
                case .localAudioMuted, .localVideoMuted, .raisedHandListChanged:
                    break
                default:
                    break
                }
            }
            // 课堂相位只跟 Backend，禁止用 RTC RoomPhase 覆盖
            if let id = classroomId {
                let (snap, room, timer, policyJson, messages) = try withCore {
                    (
                        try core.backendSnapshot(),
                        try core.roomState(),
                        try core.classroomTimer(),
                        try core.interactionPolicyJson(),
                        try core.imMessages()
                    )
                }
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
                let onStageUsers = snap.onStageUserIds.map {
                    StageUser(userId: $0, displayName: nil, onStage: true)
                }
                let members = snap.members.map { item in
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
                }
                let interactionPolicy = try JSONDecoder().decode(
                    [ActionAvailability].self,
                    from: Data(policyJson.utf8)
                )
                let imMessages = messages.map { message in
                    ImMessage(
                        id: message.id,
                        senderId: message.senderId,
                        content: message.content,
                        sentAt: Int64(message.sentAt)
                    )
                }
                publishUiSnapshot(
                    SdkSnapshot(
                        generation: readUiSnapshot().generation + 1,
                        classInfo: classInfo,
                        onStageUsers: onStageUsers,
                        members: members,
                        memberCount: snap.memberCount,
                        membersNextCursor: snap.membersNextCursor,
                        interactionPolicy: interactionPolicy,
                        imMessages: imMessages,
                        bindableRemoteVideoUserIds: Set(room.bindableRemoteVideoUserIds),
                        localVideoBindable: room.localVideoBindable,
                        needLive: snap.needLive
                    )
                )
                emitClassInfo(id, mapMobilePhase(snap.classPhase), title: title, lifecycleStatus: mapMobileLifecycleStatus(snap.lifecycleStatus))
                // 快照是可绑判定的唯一来源，发布后立刻协调；Core 主动退房
                // （下台 → leave_rtc → reset）不产生任何厂商事件，只有这里能收敛。
                reconcileVideoBinds()
            }
        } catch {
            DispatchQueue.main.async { [weak self] in
                self?.errorListeners.forEach {
                    $0(SdkError(code: .internal, message: error.localizedDescription))
                }
            }
        }
    }

    func readUiSnapshot() -> SdkSnapshot {
        uiSnapshotLock.lock()
        defer { uiSnapshotLock.unlock() }
        return uiSnapshot
    }

    private func publishUiSnapshot(_ snapshot: SdkSnapshot) {
        uiSnapshotLock.lock()
        uiSnapshot = snapshot
        let listeners = Array(sdkSnapshotListeners.values)
        uiSnapshotLock.unlock()
        guard !listeners.isEmpty else { return }
        DispatchQueue.main.async {
            listeners.forEach { $0(snapshot) }
        }
    }

    private func runQuery<T>(_ operation: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queryQueue.async {
                continuation.resume(with: Result(catching: operation))
            }
        }
    }

    /// 在事件线程投递过程笔迹。取快照后再调用，避免持锁执行宿主代码。
    private func emitLiveStroke(_ payloadJson: String) {
        liveStrokeListenerLock.lock()
        let listeners = whiteboardLiveStrokeListeners
        liveStrokeListenerLock.unlock()
        for listener in listeners {
            listener(payloadJson)
        }
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

    /// join 响应刚落地时先把课堂信息交给 UI，让骨架屏能显示真实内容。
    private func emitClassSnapshotOnMain(_ success: JoinSuccessInfo) {
        emitOnMain { [weak self] in
            guard let self else { return }
            self.classInfoListeners.forEach { $0(success.classInfo) }
            self.onStageUsersListeners.forEach { $0(success.onStageUsers) }
            self.userProfileListeners.forEach {
                $0(UserProfile(
                    userId: success.selfInfo.userId,
                    displayName: success.selfInfo.displayName,
                    avatarUrl: success.selfInfo.avatarUrl,
                    role: nil
                ))
            }
        }
    }

    /// 必要域就绪时只回调一次；可选域的后续推进走 `onJoinProgress`。
    private func emitJoinSuccess() {
        guard let success = pendingJoinSuccess else { return }
        pendingJoinSuccess = nil
        emitOnMain { [weak self] in
            self?.joinSuccessListeners.forEach { $0(success) }
        }
    }

    private func emitWhiteboardCredentials(_ credentials: WhiteboardCredentials?) {
        emitOnMain { [weak self] in
            self?.whiteboardCredentialsListeners.forEach { $0(credentials) }
        }
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
        static let pollInterval: TimeInterval = 0.1
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
