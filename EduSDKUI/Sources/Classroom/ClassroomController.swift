import Foundation
import Combine
import AVFoundation
import EduSDK
#if canImport(UIKit)
import UIKit
#endif

@MainActor
public final class ClassroomController: ObservableObject {
    public let options: EduClassroomOptions
    @Published public private(set) var snapshot: UiSnapshot

    @Published private(set) var toolsView: TeachingToolsView?

    private var sdk: EduSdk
    private let continuationBinding: ClassroomContinuationBinding?
    private var unsubs: [() -> Void] = []
    private var joinSucceeded = false
    private var feedbackQueue: [UiFeedback] = []
    private var feedbackActionHandlers: [UInt64: (String) -> Void] = [:]
    private var endConfirmId: UInt64?
    private lazy var feedbackPresenter = FeedbackPresenter(locale: options.localeTag, onFrame: { [weak self] frame in self?.applyFeedbackFrame(frame) }, onFailure: { error in NSLog("EduSDK feedback presentation failed: %@", String(describing: error)) })
    private var classroomStatusFeedbackId: UInt64?
    private var lastClassroomFeedbackKey: String?
    private var mediaOpenHintFeedbackId: UInt64?
    private var hintActionInProgress = false
    private var interactionPolicy: [ActionAvailability] = []
    private let initEpoch = ClassroomInitEpoch()
    private let writeGate = WhiteboardWriteGate()
    private let initQueue = DispatchQueue(label: Tokens.initQueueLabel, qos: .userInitiated)
    private let queryQueue = DispatchQueue(label: Tokens.queryQueueLabel, qos: .userInitiated)
    private let exportQueue=DispatchQueue(label:"edusdk.classroom.export-file",qos:.userInitiated)
    private let exportGate=TeachingToolExportGate()
    private var timerQueryInFlight = false
    private var policyQueryGeneration: UInt64 = 0
    private var classroomTimer: Timer?
    /// IM 消息去重与批量投递（MainActor 隔离）。
    private var joinLocalUserId: String?

    /// 终态判据用 `lifecycleStatus`：`ClassPhase.ended` 把 ended 与 expired 压成一个值，
    /// 无法区分两个必须分开的终态。
    static func unbindWhiteboardSyncIfTerminal(
        lifecycleStatus: ClassroomLifecycleStatus,
        unbind: () -> Void = { WhiteboardHost.shared.bindSyncSender(nil) }
    ) {
        guard lifecycleStatus == .ended || lifecycleStatus == .expired else { return }
        unbind()
    }

    public init(options: EduClassroomOptions) {
        self.options = options
        weak var owner: ClassroomController?
        let binding = options.continuation.map { _ in
            ClassroomContinuationBinding(options: options) { error in
                Task { @MainActor in
                    owner?.enqueueError(SdkError(code: .internal, message: error.localizedDescription))
                }
            }
        }
        self.continuationBinding = binding
        self.sdk = Self.makeSdk(options: options, continuation: binding)
        self.snapshot = UiSnapshot(
            initStatus: .loading,
            classroomId: options.classroomId,
            userId: options.userId,
            displayName: options.displayName,
            badgeText: EduI18n.text("statusConnecting")
        )
        owner = self
        guard options.continuation != nil else { return }
        audioInterruption = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: AVAudioSession.sharedInstance(), queue: nil
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard let raw, let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if type == .began {
                Task { @MainActor in self?.announceAudioInterruption() }
                return
            }
            let optionRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            guard AVAudioSession.InterruptionOptions(rawValue: optionRaw).contains(.shouldResume) else { return }
            Task { @MainActor in
                guard let self, let view = self.snapshot.continuation, view.playbackAllowed && view.returnEntry else { return }
                Self.activateBackgroundAudio(true)
            }
        }
    }

    func classroomPresentation(visible: Bool, scene: UIWindowScene?) {
        continuationBinding?.presentation(visible: visible, scene: scene)
    }

    private var windowPort: ContinuationWindowPort?
    private var stopWindow: (() -> Void)?
    private var audioInterruption: NSObjectProtocol?

    func bindContinuationWindow(_ port: ContinuationWindowPort?, stop: (() -> Void)? = nil) {
        windowPort = port
        stopWindow = stop
        sdk.bindContinuationWindow(port)
    }

    private var announcedLimitations: Set<String> = []

    private func announceContinuationLimitations(_ limitations: [String]) {
        let next = Set(limitations)
        let fresh = next.subtracting(announcedLimitations)
        announcedLimitations = next
        if fresh.contains("window_failed") {
            presentFeedback(FeedbackRequest.create(
                mode: .toast, tone: .warning, message: EduI18n.text("continuationWindowFailed"),
                autoDismissMs: Tokens.toastAutoDismissMs
            ))
        }
        if fresh.contains("background_audio_unavailable") {
            presentFeedback(FeedbackRequest.create(
                mode: .toast, tone: .warning, message: EduI18n.text("continuationBackgroundHoldFailed"),
                autoDismissMs: Tokens.toastAutoDismissMs
            ))
        }
    }

    private func announceAudioInterruption() {
        guard snapshot.continuation?.playbackAllowed == true else { return }
        presentFeedback(FeedbackRequest.create(
            mode: .toast, tone: .warning, message: EduI18n.text("continuationAudioInterrupted"),
            autoDismissMs: Tokens.toastAutoDismissMs
        ))
    }

    func continuationContentReady(_ content: String) -> Bool {
        switch content {
        case "whiteboard":
            return WhiteboardHost.shared.engineReady && WhiteboardHost.shared.persistentSurface != nil
        case "teacher":
            return snapshot.featuredTeacher != nil || snapshot.liveStreams.contains { $0.streamType == LiveStreamType.main.rawValue && !$0.publisherUserId.isEmpty }
        case "remote_screen":
            return !snapshot.screenShareUserIds.isEmpty || snapshot.liveStreams.contains { $0.streamType == LiveStreamType.aux.rawValue && !$0.publisherUserId.isEmpty }
        default:
            return false
        }
    }

    /// Moves the one live renderer Core selected. An empty host is a failed window, never a still image.
    func attachContinuationContent(_ content: String, to host: UIView) -> Bool {
        releaseContinuationVideo()
        switch content {
        case "whiteboard":
            guard WhiteboardHost.shared.engineReady, let surface = WhiteboardHost.shared.persistentSurface else { return false }
            surface.translatesAutoresizingMaskIntoConstraints = true
            surface.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            surface.frame = host.bounds
            host.addSubview(surface)
            WhiteboardHost.shared.bindPersistentSurface(boardContainer: host)
            return true
        case "teacher":
            if let teacher = snapshot.featuredTeacher {
                if let stream = LiveStreams.byUser(snapshot)[teacher.id] { return attachContinuationLive(stream, to: host) }
                return attachContinuationRtc(VideoSlot(userId: teacher.id, streamType: .camera), to: host)
            }
            guard let stream = snapshot.liveStreams.first(where: { $0.streamType == LiveStreamType.main.rawValue && !$0.publisherUserId.isEmpty }) else { return false }
            return attachContinuationLive(stream.streamName, to: host)
        case "remote_screen":
            if let presenter = snapshot.screenSharePresenter() {
                if let stream = LiveStreams.auxStreamName(snapshot, userId: presenter.userId) { return attachContinuationLive(stream, to: host) }
                return attachContinuationRtc(VideoSlot(userId: presenter.userId, streamType: .screen), to: host)
            }
            guard let stream = snapshot.liveStreams.first(where: { $0.streamType == LiveStreamType.aux.rawValue && !$0.publisherUserId.isEmpty }) else { return false }
            return attachContinuationLive(stream.streamName, to: host)
        default:
            return false
        }
    }

    func releaseContinuationContent() {
        releaseContinuationVideo()
    }

    private var continuationVideo: (slot: VideoSlot?, stream: String?, view: UIView)?

    private func attachContinuationRtc(_ slot: VideoSlot, to host: UIView) -> Bool {
        let view = RtcVideoHostView()
        view.frame = host.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.onReady = { [weak self] ready in self?.bindUserVideo(slot: slot, view: ready) }
        host.addSubview(view)
        continuationVideo = (slot, nil, view)
        return true
    }

    private func attachContinuationLive(_ stream: String, to host: UIView) -> Bool {
        let view = RtcVideoHostView()
        view.frame = host.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.onReady = { [weak self] ready in self?.bindLiveStream(streamName: stream, view: ready) }
        host.addSubview(view)
        continuationVideo = (nil, stream, view)
        return true
    }

    private func releaseContinuationVideo() {
        guard let bound = continuationVideo else { return }
        continuationVideo = nil
        if let slot = bound.slot { unbindUserVideo(slot: slot, view: bound.view) }
        if let stream = bound.stream { unbindLiveStream(streamName: stream, view: bound.view) }
        bound.view.removeFromSuperview()
    }

    func promptClassroomBack(onContinue: @escaping () -> Void, onLeave: @escaping () -> Void) {
        switch snapshot.continuation?.settings?.settings.classroomBack {
        case "continue": onContinue()
        case "leave": onLeave()
        default:
            var remember = false
            presentFeedback(FeedbackRequest.create(
                mode: .dialog, tone: .info, message: EduI18n.text("continuationCloseMessage"),
                autoDismissMs: nil, modal: true,
                actions: [
                    FeedbackAction(id: "remember", label: EduI18n.text("continuationRememberClose"), dismissOnClick: false),
                    FeedbackAction(id: "continue", label: EduI18n.text("continuationCloseContinue"), style: .primary),
                    FeedbackAction(id: "leave", label: EduI18n.text("continuationCloseLeave"), style: .danger),
                    FeedbackAction(id: "cancel", label: EduI18n.text("continuationCloseCancel")),
                ]
            )) { [weak self] action in
                guard let self else { return }
                switch action {
                case "remember": remember = !remember
                case "continue":
                    if remember { self.updateContinuationPreference("classroom_back", choice: "continue") }
                    onContinue()
                case "leave":
                    if remember { self.updateContinuationPreference("classroom_back", choice: "leave") }
                    onLeave()
                default: break
                }
            }
        }
    }

    func updateContinuationPreference(_ field: String, enabled: Bool? = nil, choice: String? = nil) {
        guard let view = snapshot.continuation?.settings, view.storage == "ready" || view.storage == "saving" else { return }
        let media = view.settings.media
        let record: [String: Any] = [
            "media": [
                "auto_window": field == "auto_window" ? enabled == true : media.autoWindow,
                "background_audio": field == "background_audio" ? enabled == true : media.backgroundAudio,
                "background_microphone": field == "background_microphone" ? enabled == true : media.backgroundMicrophone,
            ],
            "classroom_back": field == "classroom_back" ? choice as Any? ?? NSNull() : view.settings.classroomBack as Any? ?? NSNull(),
            "window_close": field == "window_close" ? choice as Any? ?? NSNull() : view.settings.windowClose as Any? ?? NSNull(),
        ]
        let sdkRef = sdk
        queryQueue.async {
            guard let data = try? JSONSerialization.data(withJSONObject: ["type": "preferences", "settings": record]),
                  let json = String(data: data, encoding: .utf8) else { return }
            try? sdkRef.requestClassroomContinuation(json)
        }
    }

    func loadTools(cursor: String? = nil) {
        sendToolRequest { ["operation": "list", "cursor": cursor as Any? ?? NSNull(), "limit": 20] }
    }
    func loadToolDefinition(_ card: TeachingToolCard) {
        sendToolRequest { ["operation": "definition", "sessionId": card.sessionId] }
    }
    @discardableResult
    func updateTool(_ edit: TeachingToolEdit, draft: TeachingToolDraft, trueLabel: String, falseLabel: String, onRejected: (() -> Void)? = nil) -> String {
        let requestId = UUID().uuidString
        sendToolRequest(onRejected: onRejected) { ["operation": "update", "sessionId": edit.sessionId, "expectedRevision": edit.revision, "requestId": requestId,
            "config": try draft.config(trueLabel: trueLabel, falseLabel: falseLabel)] }
        return requestId
    }
    @discardableResult
    func createTool(_ draft: TeachingToolDraft, trueLabel: String, falseLabel: String, onRejected: (() -> Void)? = nil) -> String {
        let requestId = UUID().uuidString
        sendToolRequest(onRejected: onRejected) { ["operation": "create", "requestId": requestId, "config": try draft.config(trueLabel: trueLabel, falseLabel: falseLabel)] }
        return requestId
    }
    func loadToolHistory(cursor: String? = nil) {
        sendToolRequest { ["operation": "history_list", "cursor": cursor as Any? ?? NSNull(), "limit": 20] }
    }
    func loadToolHistoryVersions(sessionId: String, cursor: String? = nil) {
        sendToolRequest { ["operation": "history_versions", "sessionId": sessionId, "cursor": cursor as Any? ?? NSNull(), "limit": 20] }
    }
    func loadToolHistoryDetail(sessionId: String, revision: String) {
        sendToolRequest { ["operation": "history_detail", "sessionId": sessionId, "revision": revision] }
    }
    func loadToolOwn(_ card: TeachingToolCard) {
        sendToolRequest { guard let roundId = card.roundId else { throw NSError(domain: "TeachingToolForm", code: 3) }; return ["operation": "own", "sessionId": card.sessionId, "roundId": roundId] }
    }
    func loadToolResults(_ card: TeachingToolCard, cursor: String? = nil) {
        sendToolRequest {
            guard let roundId = card.roundId else { throw NSError(domain: "TeachingToolForm", code: 3) }
            return ["operation": "results", "sessionId": card.sessionId, "roundId": roundId, "cursor": cursor as Any? ?? NSNull(), "limit": 20]
        }
    }
    func reviewTool(_ card: TeachingToolCard, submission: TeachingToolSubmission, score: String, feedback: String) {
        guard !toolMutationPending(card.sessionId) else { return }
        sendToolRequest {
            guard let roundId = card.roundId, let points = Int(score) else { throw NSError(domain: "TeachingToolForm", code: 4) }
            return ["operation": "review", "sessionId": card.sessionId, "roundId": roundId, "userId": submission.userId,
                "expectedSubmissionRevision": submission.revision, "requestId": UUID().uuidString, "score": points, "feedback": feedback]
        }
    }
    func manageToolGroup(_ card: TeachingToolCard, action: String, groupId: String? = nil, first: String? = nil, second: String? = nil, name: String? = nil) {
        guard !toolMutationPending(card.sessionId) else { return }
        sendToolRequest {
            var body: [String: Any] = ["action": action]
            switch action {
            case "rename_group": body["groupId"] = groupId; body["name"] = name
            case "set_group_leader": body["groupId"] = groupId; body["userId"] = first as Any? ?? NSNull()
            case "move_member": body["groupId"] = groupId; body["userId"] = first
            case "swap_members": body["firstUserId"] = first; body["secondUserId"] = second
            default: throw NSError(domain: "TeachingToolForm", code: 6)
            }
            return ["operation": "execute", "sessionId": card.sessionId, "expectedRevision": card.revision, "requestId": UUID().uuidString, "action": body]
        }
    }
    func loadToolScorePeriods(_ card: TeachingToolCard, cursor: String? = nil) {
        sendToolRequest { ["operation": "score_periods", "sessionId": card.sessionId, "cursor": cursor as Any? ?? NSNull(), "limit": 20] }
    }
    func loadToolScores(_ card: TeachingToolCard, periodId: String, view: String, kind: String? = nil, id: String? = nil, cursor: String? = nil, limit: Int = 20) {
        sendToolRequest { ["operation": "scores", "sessionId": card.sessionId, "query": ["periodId": periodId, "view": view,
            "targetKind": kind as Any? ?? NSNull(), "targetId": id as Any? ?? NSNull(), "cursor": cursor as Any? ?? NSNull(), "limit": limit]] }
    }
    func reverseToolScore(_ card: TeachingToolCard, entryId: String, reason: String) {
        guard !toolMutationPending(card.sessionId) else { return }
        sendToolRequest { ["operation": "execute", "sessionId": card.sessionId, "expectedRevision": card.revision, "requestId": UUID().uuidString,
            "action": ["action": "reverse_score", "entryId": entryId, "reason": reason]] }
    }
    func awardToolScore(_ card: TeachingToolCard, kind: String, id: String, delta: String, reason: String) {
        guard !toolMutationPending(card.sessionId) else { return }
        sendToolRequest {
            guard let points = Int(delta) else { throw NSError(domain: "TeachingToolForm", code: 5) }
            return ["operation": "execute", "sessionId": card.sessionId, "expectedRevision": card.revision, "requestId": UUID().uuidString,
                "action": ["action": "award_score", "target": ["kind": kind, "id": id], "delta": points, "reason": reason]]
        }
    }
    func loadToolStudents(cursor: String? = nil) {
        let sdkRef = sdk; let epoch = initEpoch.current(); let gate = initEpoch
        queryQueue.async { [weak self] in
            guard gate.isCurrent(epoch) else { return }
            do { try sdkRef.loadMembers(cursor) }
            catch {
                Task { @MainActor [weak self] in
                    guard let self, self.initEpoch.isCurrent(epoch) else { return }
                    self.enqueueError(error as? SdkError ?? SdkError(code: .internal, message: error.localizedDescription))
                }
            }
        }
    }
    func controlTool(_ card: TeachingToolCard, action: String, parameter: String) {
        guard !toolMutationPending(card.sessionId) else { return }
        sendToolRequest {
            var body: [String: Any] = ["action": action]
            if action == "lap" { body["label"] = parameter }
            if action == "hide_term" || action == "restore_term" { body["termKey"] = parameter }
            if action == "adjust" {
                let value = NSDecimalNumber(string: parameter, locale: Locale(identifier: "en_US_POSIX")).multiplying(by: 1000)
                guard let milliseconds = Int64(value.stringValue) else { throw NSError(domain: "TeachingToolForm", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid adjustment"]) }
                body["deltaMs"] = milliseconds
            }
            return ["operation": "execute", "sessionId": card.sessionId, "expectedRevision": card.revision, "requestId": UUID().uuidString, "action": body]
        }
    }
    func submitTool(_ card: TeachingToolCard, selection: [String], text: String) {
        guard card.canSubmit && !toolMutationPending(card.sessionId) else { return }
        sendToolRequest {
            let answer: [String: Any]
            switch card.input?.type {
            case "buzz": answer = ["kind": "buzz"]
            case "text": answer = ["kind": "text", "text": text]
            case "words": answer = ["kind": "words", "words": text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }]
            case "single_choice", "multiple_choice": answer = ["kind": "choice", "optionIds": selection]
            default: throw NSError(domain: "TeachingToolForm", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unknown input"])
            }
            guard let roundId = card.roundId else { throw NSError(domain: "TeachingToolForm", code: 3, userInfo: [NSLocalizedDescriptionKey: "Missing round"]) }
            return ["operation": "submit", "sessionId": card.sessionId, "requestId": UUID().uuidString,
                "submission": ["roundId": roundId, "expectedSubmissionRevision": card.ownRevision as Any? ?? NSNull(), "answer": answer]]
        }
    }
    func toolMutationPending(_ sessionId: String) -> Bool {
        toolsView?.operations.contains { $0.sessionId == sessionId && $0.blocksWrites } == true
    }

    func createToolExport(_ card: TeachingToolCard, currentRound: Bool) {
        guard card.canExport,!toolMutationPending(card.sessionId),!currentRound || card.roundId != nil else {return}
        sendToolRequest { ["operation":"export","sessionId":card.sessionId,"expectedRevision":card.revision,"requestId":UUID().uuidString,"roundId":currentRound ? card.roundId as Any : NSNull(),"format":"csv"] }
    }
    func refreshToolExport(_ entry:TeachingToolExport) {
        guard toolsView?.exports.contains(where:{$0.id==entry.id && $0.job.sessionId==entry.job.sessionId})==true else {return}
        sendToolRequest { ["operation":"export_get","sessionId":entry.job.sessionId,"exportId":entry.id] }
    }
    func downloadToolExport(_ entry:TeachingToolExport, completion:@escaping (URL?)->Void) {
        let lifecycle=initEpoch;let epoch=lifecycle.current();let gate=exportGate
        exportQueue.async { [weak self] in
            let ticket=gate.ticket()
            let current={lifecycle.isCurrent(epoch) && gate.permits(entry,ticket)}
            let download=TeachingToolExportFile(entry:entry,isCurrent:current) { result in
                Task { @MainActor [weak self] in
                    guard let self,lifecycle.isCurrent(epoch) else {
                        if case let .success(file)=result {DispatchQueue.global(qos:.utility).async {TeachingToolExportFile.remove(file)}}
                        return
                    }
                    guard gate.permits(entry,ticket) else {
                        if case let .success(file)=result {DispatchQueue.global(qos:.utility).async {TeachingToolExportFile.remove(file)}}
                        completion(nil);return
                    }
                    switch result {
                    case let .success(file):completion(file)
                    case .failure:self.enqueueError(SdkError(code:.internal,message:EduI18n.text("tool_exportSaveFailed")));completion(nil)
                    }
                }
            }
            download.start()
        }
    }
    func resolveTool(_ requestId: String) {
        guard toolsView?.operations.contains(where: { $0.requestId == requestId && $0.canResolve }) == true else { return }
        sendToolRequest { ["operation": "resolve", "requestId": requestId] }
    }
    func retryTool(_ requestId: String) {
        guard toolsView?.operations.contains(where: { $0.requestId == requestId && $0.canRetry }) == true else { return }
        sendToolRequest { ["operation": "retry", "requestId": requestId] }
    }
    private func sendToolRequest(onRejected: (() -> Void)? = nil, _ build: @escaping () throws -> [String: Any]) {
        let sdkRef = sdk; let epoch = initEpoch.current(); let gate = initEpoch
        queryQueue.async { [weak self] in
            guard gate.isCurrent(epoch) else { return }
            do {
                let data = try JSONSerialization.data(withJSONObject: build())
                try sdkRef.requestTeachingTools(String(decoding: data, as: UTF8.self))
            } catch {
                Task { @MainActor [weak self] in
                    guard let self, self.initEpoch.isCurrent(epoch) else { return }
                    onRejected?()
                    self.enqueueError(error as? SdkError ?? SdkError(code: .internal, message: error.localizedDescription))
                }
            }
        }
    }

    public func initialize() {
        feedbackPresenter.removeGroup("classroom-entry-error")
        exportGate.reset()
        toolsView = nil
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
        }, mediaSender: { [weak sdk] payloadJson in
            guard let sdk else { return }
            try sdk.sendWhiteboardMedia(payloadJson: payloadJson)
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
        WhiteboardHost.shared.bindRoomMediaFeedback { [weak self] error in
            self?.enqueueError((error as? WhiteboardMediaRequestFailure)?.sdkError
                ?? error as? SdkError
                ?? SdkError(code:.whiteboardProviderError,message:error.localizedDescription))
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

    private func resetMessageBuffer() {
        snapshot.historyLoading = false; snapshot.historyHasMore = true; snapshot.historyError = false
    }


    public func retry() {
        dismissFeedback()
        retryWithoutFeedbackDismiss()
    }

    public func dismissFeedback(id: UInt64? = nil, reason: String = "programmatic") {
        if let id = id ?? snapshot.feedback?.id { feedbackPresenter.dismiss(id, reason: reason) }
    }
    public func feedbackShown(id: UInt64) { feedbackPresenter.shown(id) }
    public func presentFeedback(_ request: FeedbackRequest, onAction: ((String) -> Void)? = nil) {
        if let onAction { feedbackActionHandlers[request.id] = onAction }
        feedbackPresenter.present(request)
    }
    public func handleFeedbackAction(feedbackId: UInt64, actionId: String) { feedbackPresenter.action(feedbackId, actionId) }
    private func applyFeedbackFrame(_ frame: FeedbackFrame) {
        feedbackQueue = frame.queue
        snapshot.feedback = frame.current
        for effect in frame.receipts {
            guard let id = UInt64(effect.feedbackId) else { continue }
            if effect.type == "action", let actionId = effect.actionId {
                let handler = feedbackActionHandlers[id]
                if id == mediaOpenHintFeedbackId { hintActionInProgress = true }
                handler?(actionId)
                hintActionInProgress = false
                if actionId == "retry" { retryWithoutFeedbackDismiss() }
                if actionId == mediaOpenHintActionCheckDevices && handler == nil { openDeviceCheck() }
            }
            if effect.type != "action" || !frame.queue.contains(where: { $0.id == id }) {
                feedbackActionHandlers.removeValue(forKey: id)
                if id == endConfirmId { endConfirmId = nil }
                if id == classroomStatusFeedbackId { classroomStatusFeedbackId = nil }
                if id == mediaOpenHintFeedbackId {
                    mediaOpenHintFeedbackId = nil
                    if effect.type == "dismissed" { let sdkRef = sdk; queryQueue.async { try? sdkRef.dismissMediaOpenHint() } }
                }
            }
        }
    }

    private func retryWithoutFeedbackDismiss() {
        initEpoch.bump()
        clearListeners()
        WhiteboardHost.shared.bindSyncSender(nil)
        WhiteboardHost.shared.bindWriteAuthorizer(nil)
        WhiteboardHost.shared.bindAuthExpired(nil)
        WhiteboardHost.shared.bindRoomMediaFeedback(nil)
        let oldSdk = sdk
        sdk = Self.makeSdk(options: options, continuation: continuationBinding)
        Self.destroySdk(oldSdk)
        initialize()
    }

    private func enqueueError(_ error: SdkError) {
        presentFeedback(feedback(from: error, duringInitialization: !joinSucceeded, localeTag: options.localeTag))
    }

    public func loadImMessageHistory() {
        guard sdk.classroomView().runtime.canLoadHistory else { return }
        guard joinSucceeded, snapshot.initStatus == .ready else { return }
        guard !snapshot.historyLoading, snapshot.historyHasMore || snapshot.historyError else { return }
        snapshot.historyLoading = true; snapshot.historyError = false
        let epoch = initEpoch.current()
        let sdkRef = sdk
        Task { [weak self] in
            do {
                let cursor = sdkRef.getImHistoryState().page?.nextCursor
                _ = try await sdkRef.loadImMessageHistory(options: ImHistoryOptions(cursor: cursor))
                guard let self, self.initEpoch.isCurrent(epoch) else { return }
                self.snapshot.historyHasMore = sdkRef.getImHistoryState().page?.hasMore ?? true
            } catch {
                guard let self, self.initEpoch.isCurrent(epoch) else { return }
                self.snapshot.historyError = true
                self.enqueueError(error as? SdkError ?? SdkError(code: .imProviderError, message: error.localizedDescription))
            }
            if let self, self.initEpoch.isCurrent(epoch) { self.snapshot.historyLoading = false }
        }
    }

    public func sendImMessage(_ content: String) async -> Bool {
        guard requestInteraction(Tokens.actionSendMessage) else { return false }
        let epoch = initEpoch.current()
        let gate = initEpoch
        let sdkRef = sdk
        return await withCheckedContinuation { completion in
            initQueue.async { [weak self] in
                guard gate.isCurrent(epoch) else { completion.resume(returning: false); return }
                let result = Result { try sdkRef.sendImMessage(content: content) }
                Task { @MainActor [weak self] in
                    guard let self, self.initEpoch.isCurrent(epoch) else {
                        completion.resume(returning: false); return
                    }
                    switch result {
                    case .success: completion.resume(returning: true)
                    case .failure(let error):
                        self.enqueueError(error as? SdkError ?? SdkError(code: .internal,
                            message: error.localizedDescription.isEmpty
                                ? EduI18n.text("feedbackOperationFailed") : error.localizedDescription))
                        completion.resume(returning: false)
                    }
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
                                ? EduI18n.text("feedbackOperationFailed")
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
        guard endConfirmId == nil else { return }
        let request = feedbackFromEndClassConfirm(localeTag: options.localeTag)
        endConfirmId = request.id
        presentFeedback(request) { [weak self] actionId in
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
                                ? EduI18n.text("feedbackOperationFailed")
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
        guard sdk.classroomView().runtime.mode == "active" else { return }
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
                                ? EduI18n.text("feedbackOperationFailed")
                                : error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    public func leaveClassroom() {
        joinSucceeded = false
        initEpoch.bump()
        clearClassroomStatusFeedback()
        clearListeners()
        resetMessageBuffer()
        interactionPolicy = []
        writeGate.update(allowed: false, feedbackReason: nil)
        WhiteboardHost.shared.bindSyncSender(nil)
        WhiteboardHost.shared.bindWriteAuthorizer(nil)
        WhiteboardHost.shared.bindAuthExpired(nil)
        WhiteboardHost.shared.bindRoomMediaFeedback(nil)
        WhiteboardHost.shared.setLocalEditEnabled(false)
        let sdkRef = sdk
        initQueue.async {
            try? sdkRef.leaveClassroom()
        }
    }

    #if os(iOS)
    public func bindUserVideo(slot: VideoSlot, view: UIView) {
        sdk.bindUserVideo(userId: slot.userId, view: view, streamType: slot.streamType)
    }

    public func unbindUserVideo(slot: VideoSlot, view: UIView) {
        sdk.unbindUserVideo(userId: slot.userId, view: view, streamType: slot.streamType)
    }

    public func bindLiveStream(streamName: String, view: UIView) {
        sdk.bindLiveStream(streamName: streamName, view: view)
    }

    public func unbindLiveStream(streamName: String, view: UIView) {
        sdk.unbindLiveStream(streamName: streamName, view: view)
    }

    public func startLocalPreview(view: UIView, cameraId: String? = nil) {
        sdk.startLocalPreview(view: view, cameraId: cameraId)
    }
    #endif

    public func openDeviceCheck() {
        guard sdk.classroomView().runtime.canInspectDevices else { return }
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

    public func raiseHand() {
        guard requestInteraction(Tokens.actionRaiseHand) else { return }
        let sdkRef = sdk
        queryQueue.async { try? sdkRef.userRaiseHand() }
    }

    public func leaveStage() {
        guard requestInteraction("manage_own_stage") else { return }
        let sdkRef = sdk
        queryQueue.async { try? sdkRef.userLeaveStage() }
    }

    public func cancelHand() {
        let sdkRef = sdk
        queryQueue.async { try? sdkRef.userCancelHand() }
    }

    /// 开启屏幕共享。是否真的推流以 onLocalScreenShareChanged 回执为准，
    /// 用户可能在系统录屏授权弹窗上取消。
    public func startScreenShare() {
        guard requestInteraction(Tokens.actionShareScreen) else { return }
        let sdkRef = sdk
        queryQueue.async { try? sdkRef.startScreenShare() }
    }

    /// 停止不做权限门控：权限被中途撤销时仍必须能把屏幕收回来。
    public func stopScreenShare() {
        let sdkRef = sdk
        queryQueue.async { try? sdkRef.stopScreenShare() }
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
                manifest = .success(json)
            } catch {
                manifest = .failure(error)
            }
            guard let self, self.initEpoch.isCurrent(epoch) else { return }
            switch manifest {
                case .failure(let error):
                    completion(.failure(error))
                case .success(let value):
                    do {
                        let fileId = try await WhiteboardHost.shared.addTranscodeFile(value)
                        guard self.initEpoch.isCurrent(epoch) else { return }
                        completion(.success(fileId))
                    } catch { completion(.failure(error)) }
                }
        }
    }

    public func destroy() {
        ContinuationReturnEntry.shared.hide()
        if let audioInterruption { NotificationCenter.default.removeObserver(audioInterruption) }
        self.audioInterruption = nil
        stopWindow?()
        stopWindow = nil
        releaseContinuationContent()
        continuationBinding?.close()
        feedbackPresenter.close()
        joinSucceeded = false
        exportGate.reset()
        toolsView = nil
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
        WhiteboardHost.shared.bindRoomMediaFeedback(nil)
        WhiteboardHost.shared.setLocalEditEnabled(false)
        Self.destroySdk(sdk)
    }

    private static func activateBackgroundAudio(_ allowed: Bool) {
        guard allowed else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(true)
        }
    }

    private static func destroySdk(_ retiringSdk:EduSdk) {
        // destroy retires producers immediately and queues heavy teardown itself;
        // do not put it behind an in-flight enterClassroom on initQueue.
        // Keep the scoped native host until the SDK teardown job finishes.
        retiringSdk.destroy {
            DispatchQueue.main.async { WhiteboardHost.shared.endSession(ownedBy:retiringSdk) }
        }
    }

    private func bindSdkListeners(epoch: UInt64) {
        let toolsQueue = queryQueue
        let toolsGate = initEpoch
        unsubs.append(sdk.onTeachingToolsUpdated { [weak self] json in
            toolsQueue.async {
                guard toolsGate.isCurrent(epoch) else { return }
                do {
                    let prepared = try TeachingToolsView.decode(json)
                    Task { @MainActor [weak self] in
                        guard let self, self.initEpoch.isCurrent(epoch) else { return }
                        self.exportGate.replace(prepared.exports)
                        self.toolsView = prepared
                    }
                } catch {
                    Task { @MainActor [weak self] in
                        guard let self, self.initEpoch.isCurrent(epoch) else { return }
                        self.enqueueError(SdkError(code: .internal, message: error.localizedDescription))
                    }
                }
            }
        })
        let presentationQueue = queryQueue
        unsubs.append(sdk.onSdkSnapshot { [weak self] prepared in
            presentationQueue.async {
                let participants = prepared.classroomView.participants.map(ClassroomParticipant.init)
                let teacher = prepared.classroomView.teacher.map(ClassroomParticipant.init)
                Task { @MainActor in
                    self?.runIfCurrent(epoch) {
                        self?.snapshot.classroomView = prepared.classroomView
                        self?.snapshot.continuation = prepared.continuation
                        self?.snapshot.messages = prepared.classroomView.chatMessages
                        if let continuation = prepared.continuation {
                            self?.announceContinuationLimitations(continuation.limitations)
                            Self.activateBackgroundAudio(continuation.playbackAllowed && continuation.returnEntry)
                        }
                        self?.snapshot.stageParticipants = participants
                        self?.snapshot.featuredTeacher = teacher
                    }
                }
            }
        })
        unsubs.append(sdk.onJoinSuccess { [weak self] info in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.applyJoinSuccess(info)
                }
            }
        })
        // 白板凭证由 Core 按后台 needWhiteboard 下发，与 IM、RTC 并发；
        // 不再等 onJoinSuccess，否则白板会被 IM 登录耗时拖住。
        sdk.setWhiteboardSuspendHandler { scope,done in WhiteboardHost.shared.suspendCollaboration(mediaSessionId:scope,completion:done) }
        // This is an OS cleanup capability, not a public event subscription.
        // Keep it through leave/shutdown; EduSdk retires it after Core cleanup.
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
                    Self.unbindWhiteboardSyncIfTerminal(lifecycleStatus: info.lifecycleStatus)
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
                    self?.snapshot.liveStreams = snap.liveStreams
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
        unsubs.append(sdk.onMyStageStatusChanged { [weak self] status in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    guard let self else { return }
                    self.snapshot.handRaised = status.handRaised ?? false
                    self.refreshInteractionPolicy()
                }
            }
        })
        unsubs.append(sdk.onLocalScreenShareChanged { [weak self] sharing in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.snapshot.localScreenSharing = sharing
                }
            }
        })
        unsubs.append(sdk.onScreenShareUsersChanged { [weak self] users in
            Task { @MainActor in
                self?.runIfCurrent(epoch) {
                    self?.snapshot.screenShareUserIds = users
                }
            }
        })
        unsubs.append(sdk.onUserPermissionsChanged { [weak self] _ in
            guard let self else { return }
            self.refreshInteractionPolicy(notifyPermissionChanges: self.joinSucceeded)
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
        unsubs.append(sdk.onWhiteboardMediaClock { payloadJson in
            guard liveStrokeGate.isCurrent(epoch) else { return }
            WhiteboardHost.shared.receiveMediaClock(payloadJson)
        })
        unsubs.append(sdk.onWhiteboardMediaReceived { payloadJson in
            guard liveStrokeGate.isCurrent(epoch) else { return }
            WhiteboardHost.shared.receiveWhiteboardMedia(payloadJson)
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
            WhiteboardHost.shared.bindRoomMediaSdk(nil,mediaSessionId:nil)
            WhiteboardHost.shared.applyJoinCredentials(nil)
            return
        }
        WhiteboardHost.shared.bindRoomMediaSdk(sdk,mediaSessionId:credentials.mediaSessionId)
        WhiteboardHost.shared.applyJoinCredentials(WhiteboardConfig(
            roomId: credentials.roomId,
            appId: credentials.appId,
            userId: credentials.userId,
            token: credentials.token,
            serverHost: credentials.serverHost
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
        // The first page belongs to Core onJoinSuccess, not SwiftUI appearance.
        loadImMessageHistory()
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
        feedbackPresenter.remove(id)
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
        guard sdk.classroomView().runtime.mode == "active" else { return }
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
        guard sdk.classroomView().runtime.mode == "active" else { stopClassroomTimer(); return }
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
        feedbackPresenter.remove(id)
        classroomStatusFeedbackId = nil
    }

    private func syncClassroomStatusFeedback() {
        guard joinSucceeded else { return }
        let status = snapshot.lifecycleStatus
        let canStart = interactionPolicy.contains { $0.action == Tokens.actionStartClass && $0.available }
        let feedbackKey = "\(status.rawValue):\(canStart)"
        guard feedbackKey != lastClassroomFeedbackKey else { return }
        lastClassroomFeedbackKey = feedbackKey
        clearClassroomStatusFeedback()
        let item = feedback(from: status, canStart: canStart, localeTag: options.localeTag)
        classroomStatusFeedbackId = item.id
        presentFeedback(item) { [weak self] actionId in
            if actionId == classroomStatusStartAction { self?.startClass() }
        }
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
                    throw SdkError(code: .invalidState, message: EduI18n.text("feedbackOperationFailed"))
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
                            ? EduI18n.text("feedbackOperationFailed")
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
        if !sdk.classroomView().runtime.canInspectDevices {
            snapshot.deviceCheckOpen = false
            stopClassroomTimer()
        }
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
                let previous = self.interactionPolicy
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
                self.snapshot.toolbarEntries = toolbarEntries(policy)
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
                WhiteboardHost.shared.syncCoursewareMediaPublisher()
                if notifyPermissionChanges && !previous.isEmpty {
                    let revoked = Tokens.permissionToastActions.filter { action in
                        Tokens.policyAllows(previous, action) && Tokens.policyDenies(policy, action)
                    }
                    let granted = Tokens.permissionToastActions.filter { action in
                        Tokens.policyDenies(previous, action) && Tokens.policyAllows(policy, action)
                    }
                    let changed = revoked.isEmpty ? granted : revoked
                    if !changed.isEmpty {
                        self.presentFeedback(permissionChangedFeedback(
                            actions: changed.map { classroomActionLabel($0, localeTag: self.options.localeTag) },
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

    private static func makeSdk(options: EduClassroomOptions, continuation: ClassroomContinuationBinding?) -> EduSdk {
        EduSdk.create(options: EduSdkCreateOptions(
            appId: options.appId,
            backendUrl: options.backendUrl,
            userToken: options.userToken.isEmpty ? nil : options.userToken,
            continuation: continuation.map { binding in { try binding.configure() } },
            continuationEnvironment: continuation.map { binding in { report in try binding.subscribe(report) } }
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
        static let classroomTimerInterval: TimeInterval = 1
        static let actionStartClass = "start_class"
        static let actionEndClass = "end_class"
        static let actionSendMessage = "send_message"
        static let actionEditWhiteboard = "edit_whiteboard"
        static let actionUseMicrophone = "use_microphone"
        static let actionUseCamera = "use_camera"
        static let actionShareScreen = "share_screen"
        static let actionRaiseHand = "raise_hand"
        static let permissionDeniedReason = "permission_denied"
        static let toastAutoDismissMs: UInt64 = 3000
        static let permissionToastActions = [
            actionSendMessage, actionUseMicrophone, actionUseCamera, actionEditWhiteboard, actionShareScreen,
        ]

        static func policyDenies(_ policy: [ActionAvailability], _ action: String) -> Bool {
            policy.contains { $0.action == action && !$0.available && $0.reason == permissionDeniedReason }
        }

        static func policyAllows(_ policy: [ActionAvailability], _ action: String) -> Bool {
            policy.contains { $0.action == action && $0.available }
        }
        static let reasonCapabilityNotReady = "capability_not_ready"
        static let errorDomain = "EduSDKUI"
        static let errorCodeCoursewareLoadFailed = 1
        static let errorCodeInteractionDenied = 2
    }
}
