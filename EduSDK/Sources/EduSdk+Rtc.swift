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
        let generation = currentHostEffectGeneration()
        let adapter = createTencentTrtcIosAdapter(
            options: TencentTrtcIosAdapterOptions(
                onEvent: { [weak self] event in
                    guard self?.currentHostEffectGeneration() == generation else { return }
                    guard let classId = self?.classroomId else { return }
                    self?.handleRtcEvent(event, classId: classId)
                },
                onCustomMessage: { [weak self] message in
                    guard self?.currentHostEffectGeneration() == generation else { return }
                    guard let classId = self?.classroomId else { return }
                    self?.handleRtcCustomMessage(message, classId: classId)
                },
                onError: { [weak self] error in
                    guard self?.currentHostEffectGeneration() == generation else { return }
                    self?.emitRtcError(code: error.code, message: error.message)
                }
            )
        )
        rtcAdapter = adapter
        rtcPlaybackOutput.attach(adapter, output: adapter.setClassroomPlaybackAllowed) { [weak self] error in
            self?.emitRtcError(code: 0, message: error.localizedDescription, report: false)
        }
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
            try rtcPlaybackOutput.perform(adapter) { try adapter.enterRoom(
                params: TrtcEnterParams(
                    sdkAppId: sdkAppId,
                    userId: userId,
                    userSig: userSig,
                    classId: classId
                )
            ) }
        } catch {
            emitRtcError(code: 0, message: error.localizedDescription, report: false)
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
        do {
            try rtcPlaybackOutput.retire(adapter) { adapter.destroy() }
            rtcAdapter = nil
        } catch {
            emitRtcError(code: 0, message: error.localizedDescription, report: false)
        }
    }

    public func bindUserVideo(
        userId: String,
        view: UIView,
        streamType: EduStreamType = .camera
    ) {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let canRetain = canRetainVideoBinds()
        guard canRetain else { return }
        let slot = VideoSlot(userId: id, streamType: streamType)
        videoBindLock.lock()
        let epoch = videoBindEpoch
        let active = isVideoBindActive()
        var hosts = videoViews[slot.key, default: []]
        hosts.removeAll { $0.value == nil || $0.value === view }
        hosts.append(WeakRtcVideoView(view))
        videoViews[slot.key] = hosts
        videoBindLock.unlock()
        guard active else { return }
        scheduleVideoBind(slot: slot, view: view, epoch: epoch)
    }

    public func unbindUserVideo(
        userId: String,
        view: UIView,
        streamType: EduStreamType = .camera
    ) {
        let id = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        let slot = VideoSlot(userId: id, streamType: streamType)
        videoBindLock.lock()
        let epoch = videoBindEpoch
        var hosts = videoViews[slot.key, default: []].filter { $0.value != nil }
        let wasCurrent = hosts.last?.value === view
        hosts.removeAll { $0.value === view }
        if boundVideoViews[slot.key]?.value === view {
            boundVideoViews.removeValue(forKey: slot.key)
        }
        let fallback = hosts.last?.value
        if hosts.isEmpty {
            videoViews.removeValue(forKey: slot.key)
        } else {
            videoViews[slot.key] = hosts
        }
        videoBindLock.unlock()
        guard wasCurrent else { return }
        if let fallback {
            scheduleVideoBind(slot: slot, view: fallback, epoch: epoch)
            return
        }
        enqueueRtc { [weak self] in
            guard let self else { return }
            self.videoBindLock.lock()
            let current = self.videoBindEpoch
            let replacement = self.currentVideoViewLocked(slotKey: slot.key)
            self.videoBindLock.unlock()
            guard current == epoch, replacement == nil,
                  let adapter = self.rtcAdapter as? TencentTrtcIosAdapter else { return }
            DispatchQueue.main.async {
                self.videoBindLock.lock()
                let shouldStop = self.videoBindEpoch == epoch
                    && self.currentVideoViewLocked(slotKey: slot.key) == nil
                self.videoBindLock.unlock()
                guard shouldStop else { return }
                if self.isLocalCameraSlot(slot) {
                    // 解绑 view ≠ 关设备：已开的采集继续推流，只切到占位 view。
                    if !self.localVideoCaptureMuted() {
                        let view = self.localVideoPlaceholder ?? UIView(frame: .zero)
                        self.localVideoPlaceholder = view
                        adapter.startLocalVideo(view: view)
                    }
                } else {
                    try? adapter.stopRemoteVideo(userId: id, streamType: slot.streamType)
                }
            }
        }
    }

    private func scheduleVideoBind(slot: VideoSlot, view: UIView, epoch: UInt64) {
        enqueueRtc { [weak self] in
            guard let self else { return }
            self.videoBindLock.lock()
            let current = self.videoBindEpoch
            let registeredView = self.currentVideoViewLocked(slotKey: slot.key)
            let alreadyBound = self.boundVideoViews[slot.key]?.value === view
            self.videoBindLock.unlock()
            guard current == epoch, registeredView === view, !alreadyBound,
                  let adapter = self.rtcAdapter as? TencentTrtcIosAdapter else { return }
            DispatchQueue.main.async {
                // UIView.window / bounds 只能在主线程读；reconcile 在 coreQueue 触发。
                guard view.window != nil, view.bounds.width > 0, view.bounds.height > 0 else { return }
                self.videoBindLock.lock()
                let stillCurrent = self.videoBindEpoch == epoch
                    && self.currentVideoViewLocked(slotKey: slot.key) === view
                    && self.boundVideoViews[slot.key]?.value !== view
                self.videoBindLock.unlock()
                guard stillCurrent else { return }
                // 可绑判定由 Core 拥有；不可绑时不调 Vendor，等 Core 更新后重绑。
                guard self.isSlotBindable(self.readUiSnapshot(), slot) else { return }
                if self.isLocalCameraSlot(slot) {
                    // 绑 view 只负责预览容器，不得代替 HostEffect 开摄像头。
                    adapter.startLocalVideo(view: view)
                } else {
                    do {
                        try adapter.startRemoteVideo(
                            userId: slot.userId,
                            view: view,
                            streamType: slot.streamType
                        )
                    } catch {
                        return
                    }
                }
                self.videoBindLock.lock()
                if self.videoBindEpoch == epoch,
                   self.currentVideoViewLocked(slotKey: slot.key) === view {
                    self.boundVideoViews[slot.key] = WeakRtcVideoView(view)
                }
                self.videoBindLock.unlock()
            }
        }
    }

    /// 本端摄像头槽位走采集预览链路；本端的屏幕共享不在本地回显。
    func isLocalCameraSlot(_ slot: VideoSlot) -> Bool {
        slot.streamType == .camera && slot.userId == rtcLocalUserId
    }

    /// 可绑判定唯一实现在 Core；这里只按轨道查对应集合。
    func isSlotBindable(_ snapshot: SdkSnapshot, _ slot: VideoSlot) -> Bool {
        if slot.streamType == .screen {
            return snapshot.bindableRemoteScreenUserIds.contains(slot.userId)
        }
        if isLocalCameraSlot(slot) { return snapshot.localVideoBindable }
        return snapshot.bindableRemoteVideoUserIds.contains(slot.userId)
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
        let targets = Array(videoViews.keys).compactMap { key -> (VideoSlot, UIView)? in
            guard let view = currentVideoViewLocked(slotKey: key),
                  let slot = VideoSlot(key: key) else { return nil }
            return (slot, view)
        }
        let bound = Set(targets.compactMap { slot, view in
            boundVideoViews[slot.key]?.value === view ? slot.key : nil
        })
        videoBindLock.unlock()

        for (slot, view) in targets {
            let isLocal = isLocalCameraSlot(slot)
            let bindable = isSlotBindable(snapshot, slot)
            if bindable == bound.contains(slot.key) { continue }
            if bindable {
                scheduleVideoBind(slot: slot, view: view, epoch: epoch)
                continue
            }
            videoBindLock.lock()
            boundVideoViews.removeValue(forKey: slot.key)
            videoBindLock.unlock()
            // 本地采集由 HostEffect 关闭，这里只撤销记账；远端必须显式停订阅，
            // 否则 Vendor 会继续把已失效的流推到这个 view 上。
            if !isLocal { stopRemoteVideoBind(slot: slot, epoch: epoch) }
        }
    }

    private func stopRemoteVideoBind(slot: VideoSlot, epoch: UInt64) {
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
                try? adapter.stopRemoteVideo(userId: slot.userId, streamType: slot.streamType)
            }
        }
    }

    /// Must be called while `videoBindLock` is held.
    private func currentVideoViewLocked(slotKey: String) -> UIView? {
        var hosts = videoViews[slotKey, default: []]
        hosts.removeAll { $0.value == nil }
        if hosts.isEmpty {
            videoViews.removeValue(forKey: slotKey)
            return nil
        }
        videoViews[slotKey] = hosts
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
                "streamType": streamType.wire,
            ]) { _, new in new }
        case let .localScreenShareAvailable(available):
            payload.merge(["type": "local_screen_share_available", "available": available]) { _, new in new }
        case let .connectionLost(recoverable):
            payload.merge(["type": "connection_lost", "recoverable": recoverable]) { _, new in new }
        case let .firstVideoFrame(userId, streamType, width, height):
            payload.merge(["type": "first_video_frame", "userId": userId, "streamType": streamType.wire, "width": width, "height": height]) { _, new in new }
        case let .localVoiceLevel(level):
            payload.merge(["type": "local_voice_level", "level": level]) { _, new in new }
        case let .sei(userId, serverMs):
            payload.merge(["type": "sei", "userId": userId, "serverMs": serverMs]) { _, new in new }
        case let .networkQuality(localQuality, uplinkNetworkQuality, downlinkNetworkQuality, remoteQualities):
            var body: [String: Any] = [
                "type": "network_quality",
                "remoteQualities": remoteQualities.map { ["userId": $0.userId, "quality": $0.quality] },
            ]
            if let localQuality { body["localQuality"] = localQuality }
            if let uplinkNetworkQuality { body["uplinkNetworkQuality"] = uplinkNetworkQuality }
            if let downlinkNetworkQuality { body["downlinkNetworkQuality"] = downlinkNetworkQuality }
            payload.merge(body) { _, new in new }
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
            let bound = rtcLocalUserId.flatMap {
                currentVideoViewLocked(slotKey: VideoSlot(userId: $0, streamType: .camera).key)
            }
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
            emitRtcError(code: 0, message: error.localizedDescription, report: false)
        }
    }

    private func emitRtcError(code: Int, message: String, report: Bool = true) {
        if report {
            applyRtcPayload([
                "type": "error",
                "vendor_code": String(code),
                "reason": message,
            ])
        }
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
