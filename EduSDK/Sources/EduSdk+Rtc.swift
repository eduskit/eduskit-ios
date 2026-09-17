import Foundation

#if os(iOS)
import UIKit
import TXLiteAVSDK_TRTC

extension EduSdk {
    @discardableResult
    func ensureRtcAdapter() -> TencentTrtcIosAdapter? {
        if let existing = rtcAdapter as? TencentTrtcIosAdapter {
            return existing
        }
        let adapter = createTencentTrtcIosAdapter(
            options: TencentTrtcIosAdapterOptions(
                onEvent: { [weak self] event in
                    guard let classId = self?.classroomId else { return }
                    self?.handleRtcEvent(event, classId: classId)
                },
                onCustomMessage: { [weak self] message in
                    guard let classId = self?.classroomId else { return }
                    self?.handleRtcCustomMessage(message, classId: classId)
                },
                onError: { [weak self] error in
                    self?.emitRtcError(code: error.code, message: error.message)
                }
            )
        )
        rtcAdapter = adapter
        return adapter
    }

    /// TRTC Host 桥：sdkAppId/UserSig 来自 join.rtc，classId 映射到 strRoomId。
    func connectRtcEffect(
        sdkAppId: String,
        userId: String,
        userSig: String,
        classId: String,
    ) throws {
        guard !userId.isEmpty, !userSig.isEmpty, !sdkAppId.isEmpty else {
            throw SdkError(code: .rtcProviderError, message: "RTC effect is missing credentials")
        }

        guard let adapter = ensureRtcAdapter() else {
            throw SdkError(code: .rtcProviderError, message: "RTC adapter is not ready")
        }
        rtcLocalUserId = userId
        do {
            try adapter.enterRoom(
                params: TrtcEnterParams(
                    sdkAppId: sdkAppId,
                    userId: userId,
                    userSig: userSig,
                    classId: classId
                )
            )
        } catch {
            emitRtcError(code: 0, message: error.localizedDescription)
            teardownRtc()
            throw error
        }
    }

    func teardownRtc() {
        rtcLocalUserId = nil
        localVideoPlaceholder = nil
        videoBindLock.lock()
        boundVideoViews.removeAll()
        videoBindLock.unlock()
        guard let adapter = rtcAdapter as? TencentTrtcIosAdapter else {
            rtcAdapter = nil
            return
        }
        rtcAdapter = nil
        adapter.destroy()
    }

    public func bindUserVideo(userId: String, view: UIView) {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let canRetain = canRetainVideoBinds()
        guard canRetain else { return }
        videoBindLock.lock()
        let epoch = videoBindEpoch
        let active = isVideoBindActive()
        var hosts = videoViews[id, default: []]
        hosts.removeAll { $0.value == nil || $0.value === view }
        hosts.append(WeakRtcVideoView(view))
        videoViews[id] = hosts
        videoBindLock.unlock()
        guard active else { return }
        scheduleVideoBind(userId: id, view: view, epoch: epoch)
    }

    public func unbindUserVideo(userId: String, view: UIView) {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        videoBindLock.lock()
        let epoch = videoBindEpoch
        var hosts = videoViews[id, default: []].filter { $0.value != nil }
        let wasCurrent = hosts.last?.value === view
        hosts.removeAll { $0.value === view }
        if boundVideoViews[id]?.value === view { boundVideoViews.removeValue(forKey: id) }
        let fallback = hosts.last?.value
        if hosts.isEmpty {
            videoViews.removeValue(forKey: id)
        } else {
            videoViews[id] = hosts
        }
        let localId = rtcLocalUserId
        videoBindLock.unlock()
        guard wasCurrent else { return }
        if let fallback {
            scheduleVideoBind(userId: id, view: fallback, epoch: epoch)
            return
        }
        enqueueRtc { [weak self] in
            guard let self else { return }
            self.videoBindLock.lock()
            let current = self.videoBindEpoch
            let replacement = self.currentVideoViewLocked(userId: id)
            self.videoBindLock.unlock()
            guard current == epoch, replacement == nil,
                  let adapter = self.rtcAdapter as? TencentTrtcIosAdapter else { return }
            DispatchQueue.main.async {
                self.videoBindLock.lock()
                let shouldStop = self.videoBindEpoch == epoch
                    && self.currentVideoViewLocked(userId: id) == nil
                self.videoBindLock.unlock()
                guard shouldStop else { return }
                if id == localId {
                    // 解绑 view ≠ 关设备：已开的采集继续推流，只切到占位 view。
                    if !self.localVideoCaptureMuted() {
                        let view = self.localVideoPlaceholder ?? UIView(frame: .zero)
                        self.localVideoPlaceholder = view
                        adapter.startLocalVideo(view: view)
                    }
                } else {
                    try? adapter.stopRemoteVideo(userId: id)
                }
            }
        }
    }

    private func scheduleVideoBind(userId: String, view: UIView, epoch: UInt64) {
        enqueueRtc { [weak self] in
            guard let self else { return }
            self.videoBindLock.lock()
            let current = self.videoBindEpoch
            let localId = self.rtcLocalUserId
            let registeredView = self.currentVideoViewLocked(userId: userId)
            let alreadyBound = self.boundVideoViews[userId]?.value === view
            self.videoBindLock.unlock()
            guard current == epoch, registeredView === view, !alreadyBound,
                  let adapter = self.rtcAdapter as? TencentTrtcIosAdapter else { return }
            DispatchQueue.main.async {
                // UIView.window / bounds 只能在主线程读；reconcile 在 coreQueue 触发。
                guard view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return }
                self.videoBindLock.lock()
                let stillCurrent = self.videoBindEpoch == epoch
                    && self.currentVideoViewLocked(userId: userId) === view
                    && self.boundVideoViews[userId]?.value !== view
                self.videoBindLock.unlock()
                guard stillCurrent else { return }
                if userId == localId {
                    // 绑 view 只负责预览容器，不得代替 HostEffect 开摄像头。
                    if self.localVideoCaptureMuted() { return }
                    adapter.startLocalVideo(view: view)
                } else {
                    // 可绑判定由 Core 拥有；不可绑时不调 Vendor，等 Core 更新后重绑。
                    guard self.remoteVideoBindable(userId: userId) else { return }
                    do {
                        try adapter.startRemoteVideo(userId: userId, view: view)
                    } catch {
                        return
                    }
                }
                self.videoBindLock.lock()
                if self.videoBindEpoch == epoch,
                   self.currentVideoViewLocked(userId: userId) === view {
                    self.boundVideoViews[userId] = WeakRtcVideoView(view)
                }
                self.videoBindLock.unlock()
            }
        }
    }

    /**
     按 Core 快照协调视频绑定：该绑的绑上，已失效的停掉。

     只在快照发布点调用。phase 退回 Idle 时可绑集合变空，会天然产生全部解绑，
     因此不需要「退房就清空已绑标记」这类补丁。
     */
    func reconcileVideoBinds() {
        let snapshot = readUiSnapshot()
        videoBindLock.lock()
        let epoch = videoBindEpoch
        let localId = rtcLocalUserId
        let targets = Array(videoViews.keys).compactMap { userId -> (String, UIView)? in
            guard let view = currentVideoViewLocked(userId: userId) else { return nil }
            return (userId, view)
        }
        let bound = Set(targets.compactMap { userId, view in
            boundVideoViews[userId]?.value === view ? userId : nil
        })
        videoBindLock.unlock()

        for (userId, view) in targets {
            let isLocal = userId == localId
            let bindable = isLocal
                ? snapshot.localVideoBindable
                : snapshot.bindableRemoteVideoUserIds.contains(userId)
            if bindable == bound.contains(userId) { continue }
            if bindable {
                scheduleVideoBind(userId: userId, view: view, epoch: epoch)
                continue
            }
            videoBindLock.lock()
            boundVideoViews.removeValue(forKey: userId)
            videoBindLock.unlock()
            // 本地采集由 HostEffect 关闭，这里只撤销记账；远端必须显式停订阅，
            // 否则 Vendor 会继续把已失效的流推到这个 view 上。
            if !isLocal { stopRemoteVideoBind(userId: userId, epoch: epoch) }
        }
    }

    private func stopRemoteVideoBind(userId: String, epoch: UInt64) {
        enqueueRtc { [weak self] in
            guard let self else { return }
            self.videoBindLock.lock()
            let current = self.videoBindEpoch
            self.videoBindLock.unlock()
            guard current == epoch,
                  let adapter = self.rtcAdapter as? TencentTrtcIosAdapter else { return }
            DispatchQueue.main.async {
                self.videoBindLock.lock()
                let stillCurrent = self.videoBindEpoch == epoch
                self.videoBindLock.unlock()
                guard stillCurrent else { return }
                try? adapter.stopRemoteVideo(userId: userId)
            }
        }
    }

    /// Must be called while `videoBindLock` is held.
    private func currentVideoViewLocked(userId: String) -> UIView? {
        var hosts = videoViews[userId, default: []]
        hosts.removeAll { $0.value == nil }
        if hosts.isEmpty {
            videoViews.removeValue(forKey: userId)
            return nil
        }
        videoViews[userId] = hosts
        return hosts.last?.value
    }

    private func handleRtcEvent(_ event: TrtcAdapterEvent, classId: String) {
        guard classroomId == classId else { return }
        var payload: [String: Any] = ["classId": classId]
        switch event {
        case let .entered(_, userId, elapsedMs):
            payload.merge(["type": "entered", "userId": userId, "elapsedMs": elapsedMs]) { _, new in new }
        case let .exited(_, reason):
            payload.merge(["type": "exited", "reason": reason]) { _, new in new }
        case let .remoteUserEntered(userId):
            payload.merge(["type": "remote_user_entered", "userId": userId]) { _, new in new }
        case let .remoteUserLeft(userId, reason):
            payload.merge(["type": "remote_user_left", "userId": userId, "reason": reason]) { _, new in new }
        case let .remoteAudioAvailable(userId, available):
            payload.merge(["type": "remote_audio_available", "userId": userId, "available": available]) { _, new in new }
        case let .remoteVideoAvailable(userId, available, streamType):
            payload.merge([
                "type": "remote_video_available",
                "userId": userId,
                "available": available,
                "streamType": streamType,
            ]) { _, new in new }
        case let .connectionLost(recoverable):
            payload.merge(["type": "connection_lost", "recoverable": recoverable]) { _, new in new }
        }
        applyRtcPayload(payload)
    }

    private func handleRtcCustomMessage(_ message: TrtcCustomMessage, classId: String) {
        guard classroomId == classId else { return }
        applyRtcPayload([
            "type": "custom_message",
            "classId": classId,
            "userId": message.userId,
            "cmdId": message.commandId,
            "seq": message.sequence,
            "dataBase64": message.data.base64EncodedString(),
        ])
    }

    func applyRtcMuteLocalAudio(muted: Bool) {
        guard let adapter = rtcAdapter as? TencentTrtcIosAdapter else { return }
        if muted {
            adapter.stopLocalAudio()
        } else {
            adapter.startLocalAudio()
        }
        applyRtcPayload([
            "type": "local_audio_available",
            "available": !muted,
        ])
    }

    func applyRtcMuteLocalVideo(muted: Bool) {
        guard let adapter = rtcAdapter as? TencentTrtcIosAdapter else { return }
        if muted {
            adapter.stopLocalVideo()
        } else {
            videoBindLock.lock()
            let bound = rtcLocalUserId.flatMap { currentVideoViewLocked(userId: $0) }
            videoBindLock.unlock()
            let view = bound ?? localVideoPlaceholder ?? UIView(frame: .zero)
            if bound == nil {
                localVideoPlaceholder = view
            }
            adapter.startLocalVideo(view: view)
        }
        applyRtcPayload([
            "type": "local_video_available",
            "available": !muted,
        ])
    }

    private func applyRtcPayload(_ payload: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload)
            guard let json = String(data: data, encoding: .utf8) else { return }
            // pumpEvents 会发布带最新可绑集合的快照并在发布点协调绑定。
            // 端侧刻意不枚举「哪些厂商事件影响可绑集合」：集合本身就是判定结果。
            try withCore { try core.applyProviderEvent(domain: "rtc", payloadJson: json) }
            pumpEvents()
        } catch {
            emitRtcError(code: 0, message: error.localizedDescription)
        }
    }

    private func emitRtcError(code: Int, message: String) {
        let error = SdkError(code: .rtcProviderError, message: "TRTC(\(code)): \(message)")
        DispatchQueue.main.async { [weak self] in
            self?.errorListeners.forEach { $0(error) }
        }
    }
}
#else
extension EduSdk {
    func connectRtcEffect(
        sdkAppId: String,
        userId: String,
        userSig: String,
        classId: String,
    ) throws {
        throw SdkError(code: .rtcProviderError, message: "TRTC is unavailable on this platform")
    }

    func teardownRtc() { rtcAdapter = nil }
}
#endif
