import Foundation
import Combine
import EduSDK
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class ClassroomController: ObservableObject {
    public let options: EduClassroomOptions
    @Published public private(set) var snapshot: UiSnapshot

    private var sdk: EduSdk
    private var unsubs: [() -> Void] = []
    private var joinSucceeded = false
    private var feedbackQueue: [UiFeedback] = []
    private var feedbackActionHandlers: [UInt64: (String) -> Void] = [:]
    private var lastErrorSignature = ""
    private var lastErrorAt: TimeInterval = 0
    private var classroomStatusFeedbackId: UInt64?
    private var lastClassroomFeedbackKey: String?
    private var mediaOpenHintFeedbackId: UInt64?
    private var hintActionInProgress = false
    private var interactionPolicy: [ActionAvailability] = []
    private let initEpoch = ClassroomInitEpoch()
    private let writeGate = WhiteboardWriteGate()
    private let initQueue = DispatchQueue(label: Tokens.initQueueLabel, qos: .userInitiated)
    private let queryQueue = DispatchQueue(label: Tokens.queryQueueLabel, qos: .userInitiated)
    private var timerQueryInFlight = false
    private var policyQueryGeneration: UInt64 = 0
    private var classroomTimer: Timer?
    /// IM 消息去重与批量投递（MainActor 隔离）。
    private var seenMessageIds: Set<String> = []
    private var pendingMessages: [ImMessage] = []
    private var messageFlushScheduled = false
    private var joinLocalUserId: String?

    static func unbindWhiteboardSyncIfEnded(
        phase: ClassPhase,
        unbind: () -> Void = { WhiteboardHost.shared.bindSyncSender(nil) }
    ) {
        guard phase == .ended else { return }
        unbind()
    }

    public init(options: EduClassroomOptions) {
        self.options = options
        self.sdk = Self.makeSdk(options: options)
        self.snapshot = UiSnapshot(
            initStatus: .loading,
            classroomId: options.classroomId,
            userId: options.userId,
            displayName: options.displayName,
            badgeText: EduI18n.text("statusConnecting")
        )
    }

    public func initialize() {
        stopClassroomTimer()
        clearClassroomStatusFeedback()
        lastClassroomFeedbackKey = nil
        let epoch = initEpoch.bump()
        snapshot.initStatus = .loading
        snapshot.busy = true
        snapshot.badgeText = EduI18n.text("statusConnecting")
        snapshot.errorMessage = nil
        snapshot.classroomTitle = ""
        snapshot.lifecycleStatus = .notStarted
        snapshot.canEndClass = false
        snapshot.onStage = []
        snapshot.members = []
        snapshot.memberCount = 0
        snapshot.membersNextCursor = nil
        snapshot.membersLoading = false
        snapshot.messages = []
        snapshot.joinProgress = .idle
        snapshot.teacherUserId = nil
        snapshot.teacherDisplayName = nil
        snapshot.teacherAvatarUrl = nil
        snapshot.audioMuted = true
        snapshot.videoMuted = true
        snapshot.streamInfos = []
        snapshot.deviceCheckOpen = false
        mediaOpenHintFeedbackId = nil
        hintActionInProgress = false
        joinLocalUserId = nil
        joinSucceeded = false
        interactionPolicy = []
        resetMessageBuffer()
        writeGate.update(allowed: false, feedbackReason: nil)
        WhiteboardHost.shared.setLocalEditEnabled(false)
        WhiteboardHost.shared.updateJoinProgress(.idle)
        clearListeners()
        bindSdkListeners(epoch: epoch)
        WhiteboardHost.shared.bindSyncSender({ [weak sdk] payloadJson in
            guard let sdk else { return }
            try sdk.sendWhiteboardSync(payloadJson: payloadJson)
        }, liveStrokeSender: { [weak sdk] payloadJson in
            guard let sdk else { return }
            try sdk.sendWhiteboardLiveStroke(payloadJson: payloadJson)
        }, onFailure: { [weak self] error in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.enqueueError(
                        error as? SdkError ?? SdkError(
                            code: .whiteboardProviderError,
                            message: error.localizedDescription.isEmpty
                                ? EduI18n.text("whiteboardInitFailed")
                                : error.localizedDescription
                        )
                    )
                }
            }
        })
        // DrawsKit 在自己的线程同步调用该闭环，因此只读 `writeGate` 缓存；
        // 需要提示时才回主线程入队 Feedback。
        let boundWriteGate = writeGate
        WhiteboardHost.shared.bindAuthExpired { [weak sdk] in
            sdk?.notifyWhiteboardCredentialsExpired()
        }
        WhiteboardHost.shared.bindReadinessReporter(
            onReady: { [weak sdk] boardId in sdk?.notifyWhiteboardReady(boardId: boardId) },
            onFailed: { [weak sdk] boardId, message in
                sdk?.notifyWhiteboardFailed(boardId: boardId, message: message)
            }
        )
        WhiteboardHost.shared.bindWriteAuthorizer { [weak self] in
            switch boundWriteGate.authorize() {
            case .allowed:
                return true
            case .denied(let feedbackReason):
                guard let feedbackReason else { return false }
                Task { @MainActor in
                    guard let self, self.initEpoch.isCurrent(epoch) else { return }
                    self.presentFeedback(interactionRestrictionFeedback(
                        action: Tokens.actionEditWhiteboard,
                        reason: feedbackReason,
                        localeTag: self.options.localeTag
                    ))
                }
                return false
            }
        }

        let sdkRef = sdk
        let params = EnterClassroomParams(
            classroomId: options.classroomId,
            userId: options.userId,
            displayName: options.displayName,
            userToken: options.userToken.isEmpty ? nil : options.userToken
        )
        let gate = initEpoch
        initQueue.async { [weak self] in
            guard gate.isCurrent(epoch) else { return }
            do {
                try sdkRef.initialize()
                guard gate.isCurrent(epoch) else { return }
                try sdkRef.enterClassroom(params: params)
                guard gate.isCurrent(epoch) else { return }
                Task { @MainActor in
                    guard let self, self.initEpoch.isCurrent(epoch) else { return }
                    self.snapshot.busy = false
                    self.refreshMembers()
                }
            } catch {
                Task { @MainActor in
                    guard let self, self.initEpoch.isCurrent(epoch) else { return }
                    let message = error.localizedDescription.isEmpty
                        ? EduI18n.text("statusInitializingFailed")
                        : error.localizedDescription
                    self.enqueueError(error as? SdkError ?? SdkError(code: .internal, message: message))
                    if !self.joinSucceeded {
                        self.snapshot.initStatus = .error
                        self.snapshot.busy = false
                        self.snapshot.errorMessage = message
                        self.snapshot.badgeText = EduI18n.text("statusFailed")
                    } else {
                        self.snapshot.busy = false
                    }
                }
            }
        }
    }

    /// 消息高峰时逐条 `append` 会按消息数触发同样多次 `@Published` 发布，
    /// `contains(where:)` 又是 O(n)；这里用 Set 去重，同一轮调度合并为一次发布。
    private func appendImMessage(_ message: ImMessage) {
        guard seenMessageIds.insert(message.id).inserted else { return }
        pendingMessages.append(message)
        guard !messageFlushScheduled else { return }
        messageFlushScheduled = true
        Task { @MainActor [weak self] in
            self?.flushPendingMessages()
        }
    }

    private func flushPendingMessages() {
        messageFlushScheduled = false
        guard !pendingMessages.isEmpty else { return }
        snapshot.messages.append(contentsOf: pendingMessages)
        pendingMessages.removeAll(keepingCapacity: true)
    }

    private func resetMessageBuffer() {
        messageFlushScheduled = false
        pendingMessages.removeAll()
        seenMessageIds.removeAll()
    }

    public func retry() {
        dismissFeedback()
        retryWithoutFeedbackDismiss()
    }

    public func dismissFeedback(id: UInt64? = nil) {
        guard let current = feedbackQueue.first, id == nil || current.id == id else { return }
        if current.id == classroomStatusFeedbackId { classroomStatusFeedbackId = nil }
        let dismissingHint = current.id == mediaOpenHintFeedbackId
        if dismissingHint { mediaOpenHintFeedbackId = nil }
        feedbackActionHandlers.removeValue(forKey: current.id)
        feedbackQueue.removeFirst()
        snapshot.feedback = feedbackQueue.first
        if dismissingHint && !hintActionInProgress {
            let sdkRef = sdk
            queryQueue.async { try? sdkRef.dismissMediaOpenHint() }
        }
    }

    public func presentFeedback(_ feedback: UiFeedback, onAction: ((String) -> Void)? = nil) {
        if let onAction { feedbackActionHandlers[feedback.id] = onAction }
        if feedback.mode == .toast {
            feedbackQueue.filter { $0.mode == .toast }
                .forEach { feedbackActionHandlers.removeValue(forKey: $0.id) }
            feedbackQueue.removeAll { $0.mode == .toast }
            feedbackQueue.insert(feedback, at: 0)
        } else {
            feedbackQueue.append(feedback)
        }
        snapshot.feedback = feedbackQueue.first
    }

    public func handleFeedbackAction(feedbackId: UInt64, actionId: String) {
        guard let current = feedbackQueue.first, current.id == feedbackId else { return }
        let handler = feedbackActionHandlers[feedbackId]
        if current.id == mediaOpenHintFeedbackId && isMediaOpenHintAction(actionId) {
            hintActionInProgress = true
        }
        if current.actions.first(where: { $0.id == actionId })?.dismissOnClick == true {
            dismissFeedback(id: feedbackId)
        }
        handler?(actionId)
        hintActionInProgress = false
        if actionId == "retry" {
            retryWithoutFeedbackDismiss()
        }
        if actionId == mediaOpenHintActionCheckDevices && handler == nil {
            openDeviceCheck()
        }
    }

    private func retryWithoutFeedbackDismiss() {
        initEpoch.bump()
        clearListeners()
        WhiteboardHost.shared.bindSyncSender(nil)
        WhiteboardHost.shared.bindWriteAuthorizer(nil)
        WhiteboardHost.shared.bindAuthExpired(nil)
        let oldSdk = sdk
        sdk = Self.makeSdk(options: options)
        initQueue.async {
            oldSdk.destroy()
        }
        initialize()
    }

    private func enqueueError(_ error: SdkError) {
        let now = Date.timeIntervalSinceReferenceDate
        let signature = "\(error.code):\(error.message)"
        if signature == lastErrorSignature && now - lastErrorAt < Tokens.errorDedupWindow { return }
        lastErrorSignature = signature
        lastErrorAt = now
        feedbackQueue.append(
            feedback(from: error, duringInitialization: !joinSucceeded, localeTag: options.localeTag)
        )
        snapshot.feedback = feedbackQueue.first
    }

    public func sendImMessage(_ content: String) {
        guard requestInteraction(Tokens.actionSendMessage) else { return }
        let sdkRef = sdk
        initQueue.async { [weak self] in
            do {
                try sdkRef.sendImMessage(content: content)
            } catch {
                Task { @MainActor in
                    guard let self else { return }
                    self.enqueueError(
                        error as? SdkError ?? SdkError(
                            code: .internal,
                            message: error.localizedDescription.isEmpty
                                ? EduI18n.text("feedbackOperationTitle")
                                : error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    public func startClass() {
        guard requestInteraction(Tokens.actionStartClass) else { return }
        let sdkRef = sdk
        initQueue.async { [weak self] in
            do {
                try sdkRef.startClass()
            } catch {
                Task { @MainActor in
                    guard let self else { return }
                    self.enqueueError(
                        error as? SdkError ?? SdkError(
                            code: .internal,
                            message: error.localizedDescription.isEmpty
                                ? EduI18n.text("feedbackOperationTitle")
                                : error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    /// 操作栏：`end_class` 可用则先确认再下课并留下，明确不可用则离开。
    /// 策略尚未落地时走下课确认，避免误判成离开。返回是否已离开。
    @discardableResult
    public func endOrLeaveClassroom() -> Bool {
        let availability = interactionPolicy.first { $0.action == Tokens.actionEndClass }
        if availability?.available != false {
            requestEndClassConfirm()
            return false
        }
        leaveClassroom()
        return true
    }

    private func requestEndClassConfirm() {
        if feedbackQueue.contains(where: { item in
            item.actions.contains { $0.id == endClassConfirmAction }
        }) {
            return
        }
        presentFeedback(feedbackFromEndClassConfirm(localeTag: options.localeTag)) { [weak self] actionId in
            if actionId == endClassConfirmAction {
                self?.endClass()
            }
        }
    }

    public func endClass() {
        guard requestInteraction(Tokens.actionEndClass) else { return }
        let sdkRef = sdk
        initQueue.async { [weak self] in
            do {
                try sdkRef.endClass()
            } catch {
                Task { @MainActor in
                    guard let self else { return }
                    self.enqueueError(
                        error as? SdkError ?? SdkError(
                            code: .internal,
                            message: error.localizedDescription.isEmpty
                                ? EduI18n.text("feedbackOperationTitle")
                                : error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    /// 读取 Core 已落地的成员快照，不发 HTTP。
    public func refreshMembers() {
        snapshot.members = (try? sdk.getMemberList()) ?? []
        snapshot.memberCount = (try? sdk.getMemberCount()) ?? snapshot.memberCount
        snapshot.membersNextCursor = try? sdk.getMembersNextCursor()
    }

    public func loadMoreMembers() {
        guard let cursor = snapshot.membersNextCursor, !cursor.isEmpty else { return }
        guard !snapshot.membersLoading else { return }
        snapshot.membersLoading = true
        let sdkRef = sdk
        initQueue.async { [weak self] in
            do {
                try sdkRef.loadMembers(cursor)
                Task { @MainActor in
                    guard let self else { return }
                    self.refreshMembers()
                    self.snapshot.membersLoading = false
                }
            } catch {
                Task { @MainActor in
                    guard let self else { return }
                    self.snapshot.membersLoading = false
                    self.enqueueError(
                        error as? SdkError ?? SdkError(
                            code: .internal,
                            message: error.localizedDescription.isEmpty
                                ? EduI18n.text("feedbackOperationTitle")
                                : error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    public func leaveClassroom() {
        initEpoch.bump()
        clearClassroomStatusFeedback()
        clearListeners()
        resetMessageBuffer()
        interactionPolicy = []
        writeGate.update(allowed: false, feedbackReason: nil)
        WhiteboardHost.shared.bindSyncSender(nil)
        WhiteboardHost.shared.bindWriteAuthorizer(nil)
        WhiteboardHost.shared.bindAuthExpired(nil)
        WhiteboardHost.shared.setLocalEditEnabled(false)
        let sdkRef = sdk
        initQueue.async {
            try? sdkRef.leaveClassroom()
        }
    }

    #if os(iOS)
    public func bindUserVideo(userId: String, view: UIView) {
        sdk.bindUserVideo(userId: userId, view: view)
    }

    public func unbindUserVideo(userId: String, view: UIView) {
        sdk.unbindUserVideo(userId: userId, view: view)
    }

    public func startLocalPreview(view: UIView, cameraId: String? = nil) {
        sdk.startLocalPreview(view: view, cameraId: cameraId)
    }
    #endif

    public func openDeviceCheck() {
        snapshot.deviceCheckOpen = true
    }

    public func closeDeviceCheck() {
        snapshot.deviceCheckOpen = false
        sdk.stopLocalPreview()
        sdk.stopLocalAudioPreview()
    }

    public func deferDeviceCheck() {
        closeDeviceCheck()
    }

    public func loadMediaDevices(_ completion: @escaping (MediaDeviceList) -> Void) {
        let sdkRef = sdk
        let epoch = initEpoch.current()
        queryQueue.async { [weak self] in
            let devices = sdkRef.listMediaDevices()
            Task { @MainActor in
                guard let self, self.initEpoch.isCurrent(epoch) else { return }
                completion(devices)
            }
        }
    }

    public func stopLocalPreview() {
        sdk.stopLocalPreview()
    }

    public func startLocalAudioPreview(microphoneId: String? = nil) {
        sdk.startLocalAudioPreview(microphoneId: microphoneId)
    }

    public func stopLocalAudioPreview() {
        sdk.stopLocalAudioPreview()
    }

    public func setLocalAudioLevelListener(_ listener: ((Int) -> Void)?) {
        sdk.setLocalAudioLevelListener(listener)
    }

    public func playTestTone() {
        sdk.playTestTone()
    }

    public func confirmDeviceCheck(selection: DeviceCheckSelection = DeviceCheckSelection()) {
        let sdkRef = sdk
        let epoch = initEpoch.current()
        queryQueue.async { [weak self] in
            do {
                sdkRef.stopLocalPreview()
                sdkRef.stopLocalAudioPreview()
                try sdkRef.confirmDeviceCheck(selection: selection)
                Task { @MainActor in
                    guard let self, self.initEpoch.isCurrent(epoch) else { return }
                    self.snapshot.deviceCheckOpen = false
                }
            } catch {
                Task { @MainActor in
                    guard let self, self.initEpoch.isCurrent(epoch) else { return }
                    self.enqueueError(error as? SdkError ?? SdkError(
                        code: .internal,
                        message: error.localizedDescription
                    ))
                }
            }
        }
    }

    public func setMicrophoneEnabled(_ enabled: Bool) {
        if enabled && !requestInteraction(Tokens.actionUseMicrophone) { return }
        let sdkRef = sdk
        let epoch = initEpoch.current()
        queryQueue.async { [weak self] in
            do {
                try sdkRef.setLocalAudioMuted(muted: !enabled)
            } catch {
                guard enabled else { return }
                Task { @MainActor in
                    guard let self, self.initEpoch.isCurrent(epoch) else { return }
                    self.presentCaptureFailure()
                }
            }
        }
    }

    public func setCameraEnabled(_ enabled: Bool) {
        if enabled && !requestInteraction(Tokens.actionUseCamera) { return }
        let sdkRef = sdk
        let epoch = initEpoch.current()
        queryQueue.async { [weak self] in
            do {
                try sdkRef.setLocalVideoMuted(muted: !enabled)
            } catch {
                guard enabled else { return }
                Task { @MainActor in
                    guard let self, self.initEpoch.isCurrent(epoch) else { return }
                    self.presentCaptureFailure()
                }
            }
        }
    }

    public func loadClassroomCourseware(_ completion: @escaping ([Courseware]) -> Void) {
        let sdkRef = sdk
        let epoch = initEpoch.current()
        queryQueue.async { [weak self] in
            let courseware = (try? sdkRef.getClassroomCourseware()) ?? []
            Task { @MainActor in
                guard let self, self.initEpoch.isCurrent(epoch) else { return }
                completion(courseware)
            }
        }
    }

    /// 拉 manifest 并加载到白板。
    ///
    /// manifest 是同步阻塞的后台 HTTP（最长 30 秒），必须在 `queryQueue` 执行；
    /// 权限判定读主线程缓存策略，manifest 解析在后台完成，只有 DrawsKit 载入和
    /// `completion` 回主线程。
    public func useCourseware(
        coursewareId: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        guard requestInteraction(Tokens.actionEditWhiteboard) else {
            let reason = interactionPolicy.first { $0.action == Tokens.actionEditWhiteboard }?.reason
                ?? Tokens.reasonCapabilityNotReady
            completion(.failure(NSError(
                domain: Tokens.errorDomain,
                code: Tokens.errorCodeInteractionDenied,
                userInfo: [NSLocalizedDescriptionKey: interactionRestrictionMessage(
                    action: Tokens.actionEditWhiteboard,
                    reason: reason,
                    localeTag: options.localeTag
                )]
            )))
            return
        }
        let sdkRef = sdk
        let epoch = initEpoch.current()
        Task { [weak self] in
            let manifest: Result<Any, Error>
            do {
                let json = try await sdkRef.getCoursewareManifest(coursewareId: coursewareId)
                let value: Any = {
                    guard let data = json.data(using: .utf8),
                          let object = try? JSONSerialization.jsonObject(with: data) else { return json }
                    return object
                }()
                manifest = .success(value)
            } catch {
                manifest = .failure(error)
            }
            guard let self, self.initEpoch.isCurrent(epoch) else { return }
            switch manifest {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let value):
                    guard let fileId = WhiteboardHost.shared.addTranscodeFile(value) else {
                        completion(.failure(NSError(
                            domain: Tokens.errorDomain,
                            code: Tokens.errorCodeCoursewareLoadFailed,
                            userInfo: [
                                NSLocalizedDescriptionKey: EduI18n.text("whiteboardCoursewareFailed"),
                            ]
                        )))
                        return
                    }
                    completion(.success(fileId))
                }
        }
    }

    public func destroy() {
        initEpoch.bump()
        clearClassroomStatusFeedback()
        clearListeners()
        resetMessageBuffer()
        interactionPolicy = []
        writeGate.update(allowed: false, feedbackReason: nil)
        feedbackActionHandlers.removeAll()
        WhiteboardHost.shared.bindSyncSender(nil)
        WhiteboardHost.shared.bindWriteAuthorizer(nil)
        WhiteboardHost.shared.bindAuthExpired(nil)
        WhiteboardHost.shared.setLocalEditEnabled(false)
        WhiteboardHost.shared.endSession()
        let sdkRef = sdk
        initQueue.async {
            sdkRef.destroy()
        }
    }

    private func bindSdkListeners(epoch: UInt64) {
        unsubs.append(sdk.onJoinSuccess { [weak self] info in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.applyJoinSuccess(info)
                }
            }
        })
        // 白板凭证由 Core 按后台 needWhiteboard 下发，与 IM、RTC 并发；
        // 不再等 onJoinSuccess，否则白板会被 IM 登录耗时拖住。
        unsubs.append(sdk.onWhiteboardCredentials { [weak self] credentials in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.applyWhiteboardCredentials(credentials)
                }
            }
        })
        unsubs.append(sdk.onJoinProgress { [weak self] progress in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    WhiteboardHost.shared.updateJoinProgress(progress)
                    self?.snapshot.joinProgress = progress
                }
            }
        })
        unsubs.append(sdk.onClassInfoChanged { [weak self] info in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    guard let self else { return }
                    Self.unbindWhiteboardSyncIfEnded(phase: info.phase)
                    let lifecycleStatus = info.lifecycleStatus
                    self.snapshot.phase = info.phase.rawValue
                    self.snapshot.lifecycleStatus = lifecycleStatus
                    self.snapshot.classroomId = info.classroomId
                    if let title = info.title, !title.isEmpty {
                        self.snapshot.classroomTitle = title
                    }
                    if self.joinSucceeded {
                        self.snapshot.badgeText = Self.badge(lifecycleStatus)
                    }
                    self.refreshInteractionPolicy()
                    self.syncClassroomStatusFeedback()
                }
            }
        })
        unsubs.append(sdk.onSdkSnapshot { [weak self] snap in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.snapshot.needLive = snap.needLive
                }
            }
        })
        unsubs.append(sdk.onOnStageUsersChanged { [weak self] users in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    guard let self else { return }
                    self.snapshot.onStage = users
                    self.refreshInteractionPolicy()
                }
            }
        })
        unsubs.append(sdk.onMembersChanged { [weak self] members in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    guard let self else { return }
                    self.snapshot.members = members
                    self.snapshot.memberCount = (try? self.sdk.getMemberCount()) ?? self.snapshot.memberCount
                    self.snapshot.membersNextCursor = try? self.sdk.getMembersNextCursor()
                }
            }
        })
        unsubs.append(sdk.onUserPermissionsChanged { [weak self] _ in
            guard let self else { return }
            self.refreshInteractionPolicy(notifyPermissionChanges: self.joinSucceeded)
        })
        unsubs.append(sdk.onImMessageReceived { [weak self] message in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.appendImMessage(message)
                }
            }
        })
        unsubs.append(sdk.onWhiteboardSyncReceived { [weak self] payloadJson in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    WhiteboardHost.shared.receiveWhiteboardSync(payloadJson)
                }
            }
        })
        // 过程笔迹不走 MainActor Task：Bridge 在自己的 worker 解析，再合并成一次主线程投递。
        // 先跳一次主线程只会让每个包在主线程队列里多排一轮。
        let liveStrokeGate = initEpoch
        unsubs.append(sdk.onWhiteboardLiveStrokeReceived { payloadJson in
            guard liveStrokeGate.isCurrent(epoch) else { return }
            WhiteboardHost.shared.receiveWhiteboardLiveStroke(payloadJson)
        })
        unsubs.append(sdk.onWhiteboardRecoveryRequested { [weak self] request in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    WhiteboardHost.shared.requestRecovery(roomId: request.roomId, generation: request.generation)
                }
            }
        })
        unsubs.append(sdk.onWhiteboardSyncReloadRequested { [weak self] request in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    WhiteboardHost.shared.requestSyncReload(
                        coursewareId: request.coursewareId,
                        serverSeq: request.serverSeq
                    )
                }
            }
        })
        unsubs.append(sdk.onStreamInfoChanged { [weak self] streams in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.applyStreamInfos(streams)
                }
            }
        })
        unsubs.append(sdk.onMediaOpenHintChanged { [weak self] hint in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.applyMediaOpenHint(hint)
                }
            }
        })
        unsubs.append(sdk.onError { [weak self] err in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    guard let self else { return }
                    self.enqueueError(err)
                    if !self.joinSucceeded {
                        self.snapshot.initStatus = .error
                        self.snapshot.errorMessage = err.message
                        self.snapshot.badgeText = EduI18n.text("statusFailed")
                        self.snapshot.busy = false
                    }
                }
            }
        })
    }

    private func runIfCurrent(_ epoch: UInt64, _ body: () throws -> Void) {
        initEpoch.run(epoch, body) { [weak self] error in
            let message = error.localizedDescription.isEmpty
                ? EduI18n.text("statusInitializingFailed")
                : error.localizedDescription
            self?.enqueueError(error as? SdkError ?? SdkError(code: .internal, message: message))
        }
    }

    private func applyWhiteboardCredentials(_ credentials: WhiteboardCredentials?) {
        guard let credentials else {
            WhiteboardHost.shared.applyJoinCredentials(nil)
            return
        }
        WhiteboardHost.shared.applyJoinCredentials(WhiteboardConfig(
            roomId: credentials.roomId,
            appId: credentials.appId,
            userId: credentials.userId,
            token: credentials.token,
            serverEnvironment: options.whiteboardServerEnvironment,
            serverHost: options.whiteboardServerHost
        ))
    }

    private func applyJoinSuccess(_ info: JoinSuccessInfo) {
        joinSucceeded = true
        joinLocalUserId = info.selfInfo.userId
        snapshot.phase = info.classInfo.phase.rawValue
        snapshot.lifecycleStatus = info.classInfo.lifecycleStatus
        snapshot.classroomId = info.classInfo.classroomId
        snapshot.classroomTitle = info.classroom.name ?? info.classInfo.title ?? ""
        snapshot.displayName = info.selfInfo.displayName ?? options.displayName
        snapshot.localRole = info.selfInfo.role ?? ""
        snapshot.onStage = info.onStageUsers
        snapshot.teacherUserId = info.classroom.teacher?.userId
        snapshot.teacherDisplayName = info.classroom.teacher?.displayName
        snapshot.teacherAvatarUrl = info.classroom.teacher?.avatarUrl
        snapshot.initStatus = .ready
        snapshot.busy = false
        snapshot.badgeText = Self.badge(snapshot.lifecycleStatus)
        snapshot.errorMessage = nil
        refreshInteractionPolicy()
        syncClassroomStatusFeedback()
        applyMediaOpenHint(sdk.mediaOpenHint())
        refreshMembers()
        startClassroomTimer()
    }

    private func applyMediaOpenHint(_ hint: MediaOpenHint) {
        if !hint.visible {
            hintActionInProgress = false
            clearMediaOpenHintFeedback()
            return
        }
        if hintActionInProgress || mediaOpenHintFeedbackId != nil { return }
        let item = feedbackFromMediaOpenHint(audience: hint.audience)
        mediaOpenHintFeedbackId = item.id
        presentFeedback(item) { [weak self] actionId in
            self?.handleMediaOpenHintAction(actionId)
        }
    }

    private func clearMediaOpenHintFeedback() {
        guard let id = mediaOpenHintFeedbackId else { return }
        mediaOpenHintFeedbackId = nil
        feedbackActionHandlers.removeValue(forKey: id)
        feedbackQueue.removeAll { $0.id == id }
        snapshot.feedback = feedbackQueue.first
    }

    private func handleMediaOpenHintAction(_ actionId: String) {
        switch actionId {
        case mediaOpenHintActionOpenMic:
            setMicrophoneEnabled(true)
        case mediaOpenHintActionOpenCamera:
            setCameraEnabled(true)
        case mediaOpenHintActionCheckDevices:
            let sdkRef = sdk
            queryQueue.async { try? sdkRef.dismissMediaOpenHint() }
            openDeviceCheck()
        case mediaOpenHintActionGotIt:
            let sdkRef = sdk
            queryQueue.async { try? sdkRef.dismissMediaOpenHint() }
        default:
            break
        }
    }

    private func presentCaptureFailure() {
        presentFeedback(feedbackFromMediaCaptureFailure()) { [weak self] actionId in
            if actionId == mediaOpenHintActionCheckDevices {
                self?.openDeviceCheck()
            }
        }
    }

    private func startClassroomTimer() {
        stopClassroomTimer()
        refreshClassroomTimer()
        classroomTimer = Timer.scheduledTimer(withTimeInterval: Tokens.classroomTimerInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshClassroomTimer() }
        }
    }

    private func stopClassroomTimer() {
        classroomTimer?.invalidate()
        classroomTimer = nil
    }

    private func refreshClassroomTimer() {
        guard joinSucceeded, !timerQueryInFlight else { return }
        timerQueryInFlight = true
        let sdkRef = sdk
        let epoch = initEpoch.current()
        queryQueue.async { [weak self] in
            let result = Result { try sdkRef.getClassInfo() }
            Task { @MainActor in
                guard let self else { return }
                self.timerQueryInFlight = false
                guard self.joinSucceeded, self.initEpoch.isCurrent(epoch) else { return }
                switch result {
                case .success(let info):
                    let lifecycleStatus = info.lifecycleStatus
                    let lifecycleChanged = lifecycleStatus != self.snapshot.lifecycleStatus
                    let phaseChanged = info.phase.rawValue != self.snapshot.phase
                    self.snapshot.phase = info.phase.rawValue
                    self.snapshot.lifecycleStatus = lifecycleStatus
                    self.snapshot.badgeText = Self.badge(lifecycleStatus)
                    self.snapshot.timerMode = info.timerMode ?? .hidden
                    self.snapshot.timerSeconds = info.timerSeconds
                    if lifecycleChanged || phaseChanged {
                        self.refreshInteractionPolicy()
                        self.syncClassroomStatusFeedback()
                    }
                case .failure:
                    self.snapshot.timerMode = .hidden
                    self.snapshot.timerSeconds = nil
                }
            }
        }
    }

    private func clearClassroomStatusFeedback() {
        guard let id = classroomStatusFeedbackId else { return }
        feedbackActionHandlers.removeValue(forKey: id)
        feedbackQueue.removeAll { $0.id == id }
        classroomStatusFeedbackId = nil
        snapshot.feedback = feedbackQueue.first
    }

    private func syncClassroomStatusFeedback() {
        guard joinSucceeded else { return }
        let status = snapshot.lifecycleStatus
        let canStart = interactionPolicy.contains { $0.action == Tokens.actionStartClass && $0.available }
        let feedbackKey = "\(status.rawValue):\(canStart)"
        guard feedbackKey != lastClassroomFeedbackKey else { return }
        lastClassroomFeedbackKey = feedbackKey
        clearClassroomStatusFeedback()
        guard let item = feedback(from: status, canStart: canStart, localeTag: options.localeTag) else { return }
        classroomStatusFeedbackId = item.id
        feedbackActionHandlers[item.id] = { [weak self] actionId in
            if actionId == classroomStatusStartAction { self?.startClass() }
        }
        feedbackQueue.append(item)
        snapshot.feedback = feedbackQueue.first
    }

    private func clearListeners() {
        stopClassroomTimer()
        unsubs.forEach { $0() }
        unsubs.removeAll()
    }

    /// 交互裁决只读缓存策略。策略刷新由 Core 事件驱动（进课、上台、权限、生命周期变化），
    /// 这里不再每次触发 `getClassroomInteractionPolicy()`：该查询是异步的，本次调用永远
    /// 用不上它的结果，却会让每次操作都排一个 Core 查询。
    @discardableResult
    public func requestInteraction(_ action: String) -> Bool {
        let availability = interactionPolicy.first { $0.action == action }
        guard availability?.available == true else {
            if availability?.reason == Tokens.permissionDeniedReason { return false }
            presentFeedback(interactionRestrictionFeedback(
                action: action,
                reason: availability?.reason ?? Tokens.reasonCapabilityNotReady,
                localeTag: options.localeTag
            ))
            return false
        }
        return true
    }

    public func loadMemberActions(
        userId: String,
        completion: @escaping ([MemberActionAvailability]) -> Void
    ) {
        let sdkRef = sdk
        queryQueue.async { [weak self] in
            let result: [MemberActionAvailability]
            if let raw = try? sdkRef.getMemberActionPolicy(userId: userId),
               let data = raw.data(using: .utf8),
               let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                result = values.compactMap { item in
                    guard let action = item["action"] as? String,
                          let available = item["available"] as? Bool else { return nil }
                    return MemberActionAvailability(action: action, available: available, reason: item["reason"] as? String)
                }
            } else {
                result = []
            }
            Task { @MainActor in
                _ = self
                completion(result)
            }
        }
    }

    public func performMemberAction(action: String, userId: String, completion: @escaping () -> Void = {}) {
        let sdkRef = sdk
        queryQueue.async { [weak self] in
            do {
                let raw = try sdkRef.getMemberActionPolicy(userId: userId)
                guard let data = raw.data(using: .utf8),
                      let values = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                      let availability = values.first(where: { ($0["action"] as? String) == action }) else {
                    throw SdkError(code: .invalidState, message: EduI18n.text("feedbackOperationTitle"))
                }
                guard (availability["available"] as? Bool) == true else {
                    let reason = availability["reason"] as? String ?? Tokens.reasonCapabilityNotReady
                    throw SdkError(code: .permissionDenied, message: reason)
                }
                try Self.executeMemberAction(sdkRef, action: action, userId: userId)
                Task { @MainActor in _ = self; completion() }
            } catch {
                Task { @MainActor in
                    guard let self else { completion(); return }
                    self.enqueueError(error as? SdkError ?? SdkError(
                        code: .internal,
                        message: error.localizedDescription.isEmpty
                            ? EduI18n.text("feedbackOperationTitle")
                            : error.localizedDescription
                    ))
                    completion()
                }
                return
            }
        }
    }

    private nonisolated static func executeMemberAction(_ sdk: EduSdk, action: String, userId: String) throws {
        switch action {
        case "invite_on_stage": try sdk.inviteUserOnStage(userId: userId)
        case "remove_from_stage": try sdk.removeUserFromStage(userId: userId)
        case "approve_raise_hand": try sdk.approveUserOnStage(userId: userId)
        case "reject_raise_hand": try sdk.rejectUserOnStage(userId: userId)
        case "mute_microphone": try sdk.muteUserMicrophone(userId: userId)
        case "mute_camera": try sdk.muteUserCamera(userId: userId)
        case "prompt_open_microphone": try sdk.promptUserOpenMicrophone(userId: userId)
        case "prompt_open_camera": try sdk.promptUserOpenCamera(userId: userId)
        case "grant_microphone": try sdk.grantMicrophonePermission(userId: userId)
        case "revoke_microphone": try sdk.revokeMicrophonePermission(userId: userId)
        case "grant_camera": try sdk.grantCameraPermission(userId: userId)
        case "revoke_camera": try sdk.revokeCameraPermission(userId: userId)
        case "mute_chat": try sdk.revokeUserMessagePermission(userId: userId)
        case "unmute_chat": try sdk.grantUserMessagePermission(userId: userId)
        case "grant_whiteboard": try sdk.grantWhiteboardPermission(userId: userId)
        case "revoke_whiteboard": try sdk.revokeWhiteboardPermission(userId: userId)
        case "grant_screen_share": try sdk.grantScreenSharePermission(userId: userId)
        case "revoke_screen_share": try sdk.revokeScreenSharePermission(userId: userId)
        default: break
        }
    }

    private func refreshInteractionPolicy(notifyPermissionChanges: Bool = false) {
        policyQueryGeneration &+= 1
        let generation = policyQueryGeneration
        let epoch = initEpoch.current()
        let sdkRef = sdk
        queryQueue.async { [weak self] in
            let policy = (try? sdkRef.getClassroomInteractionPolicy()) ?? []
            Task { @MainActor in
                guard let self,
                      self.initEpoch.isCurrent(epoch),
                      self.policyQueryGeneration == generation else { return }
                let previousDenied = self.snapshot.permissionDeniedActions
                self.interactionPolicy = policy
                let permissionDeniedActions = Set(policy.compactMap { item in
                    !item.available && item.reason == Tokens.permissionDeniedReason ? item.action : nil
                })
                let editAvailability = policy.first { $0.action == Tokens.actionEditWhiteboard }
                let canEditWhiteboard = self.snapshot.lifecycleStatus == .inProgress &&
                    editAvailability?.available == true
                self.snapshot.canEditWhiteboard = canEditWhiteboard
                self.snapshot.canEndClass = policy.contains {
                    $0.action == Tokens.actionEndClass && $0.available
                }
                self.snapshot.permissionDeniedActions = permissionDeniedActions
                let restrictionReason = editAvailability?.reason ?? Tokens.reasonCapabilityNotReady
                self.writeGate.update(
                    allowed: editAvailability?.available == true,
                    feedbackReason: restrictionReason == Tokens.permissionDeniedReason
                        ? nil
                        : restrictionReason
                )
                WhiteboardHost.shared.setLocalEditEnabled(
                    canEditWhiteboard,
                    restrictionReason: restrictionReason
                )
                if notifyPermissionChanges {
                    let revoked = permissionDeniedActions.subtracting(previousDenied)
                    let granted = previousDenied.subtracting(permissionDeniedActions)
                    let changed = revoked.isEmpty ? granted : revoked
                    if !changed.isEmpty {
                        self.presentFeedback(permissionChangedFeedback(
                            actions: changed.map(self.permissionActionLabel),
                            allowed: revoked.isEmpty,
                            localeTag: self.options.localeTag
                        ))
                    }
                }
            }
        }
    }

    private func applyStreamInfos(_ streams: [StreamInfo]) {
        snapshot.streamInfos = streams
        let inProgress = snapshot.lifecycleStatus == .inProgress
        guard inProgress, let selfStream = streams.first(where: { isLocalUserId($0.userId) }) else {
            if !inProgress {
                snapshot.audioMuted = true
                snapshot.videoMuted = true
            }
            return
        }
        snapshot.audioMuted = selfStream.audioMuted ?? true
        snapshot.videoMuted = selfStream.videoMuted ?? true
    }

    private func isLocalUserId(_ userId: String) -> Bool {
        if userId.isEmpty { return false }
        return userId == options.userId || userId == joinLocalUserId
    }

    private func permissionActionLabel(_ action: String) -> String {
        let key: String
        switch action {
        case Tokens.actionSendMessage: key = "classroomActionChat"
        case Tokens.actionUseMicrophone: key = "classroomActionMicrophone"
        case Tokens.actionUseCamera: key = "classroomActionCamera"
        case Tokens.actionEditWhiteboard: key = "classroomActionWhiteboard"
        case Tokens.actionShareScreen: key = "classroomActionScreenShare"
        default: key = "feedbackOperationTitle"
        }
        return EduI18n.text(key, localeTag: options.localeTag)
    }

    private static func makeSdk(options: EduClassroomOptions) -> EduSdk {
        EduSdk.create(options: EduSdkCreateOptions(
            appId: options.appId,
            backendUrl: options.backendUrl,
            userToken: options.userToken.isEmpty ? nil : options.userToken
        ))
    }

    private static func badge(_ lifecycleStatus: ClassroomLifecycleStatus) -> String {
        switch lifecycleStatus {
        case .notStarted: return EduI18n.text("statusNotStarted")
        case .inProgress: return EduI18n.text("statusInProgress")
        case .ended: return EduI18n.text("statusEnded")
        case .expired: return EduI18n.text("statusExpired")
        }
    }

    private enum Tokens {
        static let initQueueLabel = "edusdk.classroom.init"
        static let queryQueueLabel = "edusdk.classroom.query"
        static let errorDedupWindow: TimeInterval = 0.3
        static let classroomTimerInterval: TimeInterval = 1
        static let actionStartClass = "start_class"
        static let actionEndClass = "end_class"
        static let actionSendMessage = "send_message"
        static let actionEditWhiteboard = "edit_whiteboard"
        static let actionUseMicrophone = "use_microphone"
        static let actionUseCamera = "use_camera"
        static let actionShareScreen = "share_screen"
        static let permissionDeniedReason = "permission_denied"
        static let reasonCapabilityNotReady = "capability_not_ready"
        static let errorDomain = "EduSDKUI"
        static let errorCodeCoursewareLoadFailed = 1
        static let errorCodeInteractionDenied = 2
    }
}
