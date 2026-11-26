import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if os(iOS)
import AVFoundation
import TXLiteAVSDK_TRTC
import AudioToolbox
#endif

public let trtcWhiteboardCommandId = 1
public let trtcControlCommandId = 2
public let trtcMaximumCustomMessageBytes = 1_000

public struct TrtcEnterParams {
    public let sdkAppId: String
    public let userId: String
    public let userSig: String
    /// 业务 classId；始终写入 TRTC strRoomId。
    public let classId: String

    public init(sdkAppId: String, userId: String, userSig: String, classId: String) {
        self.sdkAppId = sdkAppId
        self.userId = userId
        self.userSig = userSig
        self.classId = classId
    }
}

public struct TrtcCustomMessage {
    public let userId: String
    public let commandId: Int
    public let sequence: UInt32
    public let data: Data
}

/// Core 契约的轨道语义（`RtcStreamType`）。TRTC 的 big/sub 常量只在本文件翻译一次，
/// Core、Binding 与 UI 一律只认 `camera` / `screen`。
public enum EduStreamType: String {
    case camera
    case screen

    public var wire: String { rawValue }
}

public enum TrtcAdapterEvent {
    case entered(classId: String, userId: String, elapsedMs: Int)
    case exited(classId: String?, reason: Int)
    case remoteUserEntered(userId: String)
    case remoteUserLeft(userId: String, reason: Int)
    case remoteAudioAvailable(userId: String, available: Bool)
    case remoteVideoAvailable(userId: String, available: Bool, streamType: EduStreamType)
    case localScreenShareAvailable(available: Bool)
    case connectionLost(recoverable: Bool)
    case firstVideoFrame(userId: String, streamType: EduStreamType, width: Int, height: Int)
    case localVoiceLevel(level: Int)
    case sei(userId: String, serverMs: Int64)
    /// 厂商若只给一档 `localQuality`，上下行留空。不要用综合质量拆成两行。
    case networkQuality(
        localQuality: Int?,
        uplinkNetworkQuality: Int?,
        downlinkNetworkQuality: Int?,
        remoteQualities: [TrtcRemoteNetworkQuality]
    )
}

public struct TrtcRemoteNetworkQuality {
    public let userId: String
    public let quality: Int

    public init(userId: String, quality: Int) {
        self.userId = userId
        self.quality = quality
    }
}

public struct TrtcAdapterError {
    public let code: Int
    public let message: String
}

public struct TrtcMediaDevice {
    public let deviceId: String
    public let label: String
    public let kind: String
}

public struct TrtcMediaDeviceList {
    public var cameras: [TrtcMediaDevice]
    public var microphones: [TrtcMediaDevice]
    public var speakers: [TrtcMediaDevice]
}

public struct TrtcDeviceSelection {
    public var cameraId: String?
    public var microphoneId: String?
    public var speakerId: String?
}

public struct TencentTrtcIosAdapterOptions {
    public var onEvent: (TrtcAdapterEvent) -> Void
    public var onCustomMessage: (TrtcCustomMessage) -> Void
    public var onError: (TrtcAdapterError) -> Void

    public init(
        onEvent: @escaping (TrtcAdapterEvent) -> Void = { _ in },
        onCustomMessage: @escaping (TrtcCustomMessage) -> Void = { _ in },
        onError: @escaping (TrtcAdapterError) -> Void = { _ in }
    ) {
        self.onEvent = onEvent
        self.onCustomMessage = onCustomMessage
        self.onError = onError
    }
}

#if os(iOS)
public final class TencentTrtcIosAdapter: NSObject, TRTCCloudDelegate {
    private let options: TencentTrtcIosAdapterOptions
    private let trtc = TRTCCloud.sharedInstance()
    private var classroomPlaybackAllowed = true
    private var classId: String?
    private var userId: String?
    private var entered = false
    private var preferredCameraId: String?
    private var preferredMicrophoneId: String?
    private var preferredSpeakerId: String?
    private var audioPreviewActive = false
    private var audioLevelListener: ((Int) -> Void)?
    private var screenSharing = false
    private let callbackQueue = DispatchQueue(label: "edusdk.rtc.trtc.callbacks")
    private let callbackStateLock = NSLock()
    private var callbacksActive = true

    public init(options: TencentTrtcIosAdapterOptions = TencentTrtcIosAdapterOptions()) {
        self.options = options
        super.init()
        trtc.addDelegate(self)
    }

    public func enterRoom(params: TrtcEnterParams) throws {
        guard let sdkAppId = UInt32(params.sdkAppId.trimmingCharacters(in: .whitespacesAndNewlines)),
              sdkAppId > 0 else {
            throw adapterError("invalid sdkAppId: \(params.sdkAppId)")
        }
        let room = try requireText(params.classId, name: "classId")
        let uid = try requireText(params.userId, name: "userId")
        let userSig = try requireText(params.userSig, name: "userSig")
        if classId != nil { trtc.exitRoom() }
        classId = room
        userId = uid

        let vendorParams = TRTCParams()
        vendorParams.sdkAppId = sdkAppId
        vendorParams.userId = uid
        vendorParams.userSig = userSig
        vendorParams.strRoomId = room
        vendorParams.role = .anchor
        trtc.callExperimentalAPI("{\"api\":\"setSEIPayloadType\",\"params\":{\"payloadType\":5}}")
        trtc.setAudioPlayoutVolume(classroomPlaybackAllowed ? 100 : 0)
        trtc.enterRoom(vendorParams, appScene: .videoCall)
    }

    public func sendSei(_ payload: Data) {
        guard !payload.isEmpty else { return }
        trtc.sendSEIMsg(payload, repeatCount: 1)
    }

    public func exitRoom() {
        guard classId != nil else { return }
        trtc.exitRoom()
    }

    public func startLocalAudio() {
        applyPreferredMicrophone()
        trtc.startLocalAudio(.default)
    }
    /// Native master output; does not change capture or individual remote mute settings.
    /// The vendor void API confirms delivery only, not hardware silence.
    public func setClassroomPlaybackAllowed(_ allowed: Bool) {
        classroomPlaybackAllowed = allowed
        trtc.setAudioPlayoutVolume(allowed ? 100 : 0)
    }
    public func stopLocalAudio() { trtc.stopLocalAudio() }
    public func startLocalVideo(view: UIView, frontCamera: Bool = true) {
        applyPreferredCamera()
        let useFront = preferredCameraId.map(Self.isFrontCamera) ?? frontCamera
        trtc.startLocalPreview(useFront, view: view)
    }
    public func stopLocalVideo() { trtc.stopLocalPreview() }

    public func listMediaDevices() -> TrtcMediaDeviceList {
        // iOS TRTC 不导出 TXMediaDeviceType / getDevicesList（仅 macOS）。
        // 摄像头走前后摄，扬声器走 TXAudioRoute，麦克风枚举系统输入口。
        TrtcMediaDeviceList(
            cameras: Self.fallbackCameras,
            microphones: listMicrophones(),
            speakers: Self.fallbackSpeakers
        )
    }

    public func startLocalPreview(view: UIView, cameraId: String? = nil) {
        if let cameraId, !cameraId.isEmpty { preferredCameraId = cameraId }
        applyPreferredCamera()
        trtc.startLocalPreview(Self.isFrontCamera(preferredCameraId), view: view)
    }

    public func stopLocalPreview() {
        trtc.stopLocalPreview()
    }

    public func startLocalAudioPreview(microphoneId: String? = nil) {
        if let microphoneId, !microphoneId.isEmpty { preferredMicrophoneId = microphoneId }
        applyPreferredMicrophone()
        trtc.startLocalAudio(.default)
        trtc.enableAudioVolumeEvaluation(Self.audioVolumeIntervalMs)
        audioPreviewActive = true
    }

    public func stopLocalAudioPreview() {
        guard audioPreviewActive else { return }
        trtc.enableAudioVolumeEvaluation(0)
        trtc.stopLocalAudio()
        audioPreviewActive = false
        audioLevelListener?(0)
    }

    public func setLocalAudioLevelListener(_ listener: ((Int) -> Void)?) {
        audioLevelListener = listener
    }

    public func playTestTone() {
        applyPreferredSpeaker()
        AudioServicesPlaySystemSound(Self.testToneSoundId)
    }

    public func setPreferredDevices(_ selection: TrtcDeviceSelection) {
        if let cameraId = selection.cameraId, !cameraId.isEmpty { preferredCameraId = cameraId }
        if let microphoneId = selection.microphoneId, !microphoneId.isEmpty {
            preferredMicrophoneId = microphoneId
        }
        if let speakerId = selection.speakerId, !speakerId.isEmpty { preferredSpeakerId = speakerId }
        applyPreferredCamera()
        applyPreferredMicrophone()
        applyPreferredSpeaker()
    }

    public func setLocalAudioMuted(_ muted: Bool) { trtc.muteLocalAudio(muted) }
    public func setLocalVideoMuted(_ muted: Bool) {
        trtc.muteLocalVideo(.big, mute: muted)
    }
    /// 开始屏幕采集并推辅流。
    ///
    /// 走 App 内采集（`startScreenCaptureInApp`）而非 ReplayKit Broadcast：后者需要宿主
    /// 额外集成 Broadcast Extension 与 App Group，不能由 SDK 单方面满足。
    /// 用户仍需在系统弹窗里确认，因此实际状态以 `localScreenShareAvailable` 事件为准。
    public func startScreenShare() {
        guard !screenSharing else { return }
        let encParam = TRTCVideoEncParam()
        encParam.videoResolution = Self.screenShareResolution
        encParam.videoFps = Self.screenShareFps
        encParam.videoBitrate = Self.screenShareBitrateKbps
        encParam.enableAdjustRes = true
        trtc.startScreenCapture(inApp: .sub, encParam: encParam)
    }

    public func stopScreenShare() {
        guard screenSharing else { return }
        trtc.stopScreenCapture()
    }

    public func startRemoteVideo(
        userId: String,
        view: UIView,
        streamType: EduStreamType = .camera
    ) throws {
        trtc.startRemoteView(
            try requireText(userId, name: "userId"),
            streamType: Self.trtcStreamType(streamType),
            view: view
        )
    }
    public func stopRemoteVideo(
        userId: String,
        streamType: EduStreamType = .camera
    ) throws {
        trtc.stopRemoteView(
            try requireText(userId, name: "userId"),
            streamType: Self.trtcStreamType(streamType)
        )
    }

    @discardableResult
    public func sendCustomMessage(
        _ data: Data,
        commandId: Int = trtcWhiteboardCommandId,
        reliable: Bool = true,
        ordered: Bool = true
    ) throws -> Bool {
        guard entered else { throw adapterError("TRTC room is not entered") }
        guard !data.isEmpty, data.count <= trtcMaximumCustomMessageBytes else {
            throw adapterError("custom message must be 1..\(trtcMaximumCustomMessageBytes) bytes")
        }
        guard reliable == ordered else {
            throw adapterError("TRTC requires reliable and ordered to have the same value")
        }
        return trtc.sendCustomCmdMsg(commandId, data: data, reliable: reliable, ordered: ordered)
    }

    public func destroy() {
        callbackStateLock.lock()
        callbacksActive = false
        callbackStateLock.unlock()
        // A preview may exist before enterRoom, so release capture explicitly.
        trtc.stopScreenCapture()
        trtc.stopLocalPreview()
        trtc.stopLocalAudio()
        trtc.stopAllRemoteView()
        trtc.enableAudioVolumeEvaluation(0)
        audioPreviewActive = false
        audioLevelListener = nil
        if classId != nil { trtc.exitRoom() }
        trtc.removeDelegate(self)
        classId = nil
        userId = nil
        entered = false
    }

    public func onError(_ errCode: TXLiteAVError, errMsg: String?, extInfo: [AnyHashable: Any]?) {
        emitCallback { self.options.onError(TrtcAdapterError(code: Int(errCode.rawValue), message: errMsg ?? "")) }
    }

    public func onEnterRoom(_ result: Int) {
        guard result >= 0 else {
            emitCallback { self.options.onError(TrtcAdapterError(code: result, message: "TRTC enterRoom failed")) }
            return
        }
        guard let room = classId, let uid = userId else { return }
        entered = true
        emitCallback { self.options.onEvent(.entered(classId: room, userId: uid, elapsedMs: result)) }
    }

    public func onExitRoom(_ reason: Int) {
        let room = classId
        classId = nil
        userId = nil
        entered = false
        emitCallback { self.options.onEvent(.exited(classId: room, reason: reason)) }
    }

    public func onRemoteUserEnterRoom(_ userId: String) {
        emitCallback { self.options.onEvent(.remoteUserEntered(userId: userId)) }
    }

    public func onRemoteUserLeaveRoom(_ userId: String, reason: Int) {
        emitCallback { self.options.onEvent(.remoteUserLeft(userId: userId, reason: reason)) }
    }

    public func onUserAudioAvailable(_ userId: String, available: Bool) {
        emitCallback { self.options.onEvent(.remoteAudioAvailable(userId: userId, available: available)) }
    }

    public func onUserVideoAvailable(_ userId: String, available: Bool) {
        emitCallback {
            self.options.onEvent(
                .remoteVideoAvailable(userId: userId, available: available, streamType: .camera)
            )
        }
    }

    public func onUserSubStreamAvailable(_ userId: String, available: Bool) {
        emitCallback {
            self.options.onEvent(
                .remoteVideoAvailable(userId: userId, available: available, streamType: .screen)
            )
        }
    }

    public func onScreenCaptureStarted() {
        screenSharing = true
        emitCallback { self.options.onEvent(.localScreenShareAvailable(available: true)) }
    }

    /// 用户在系统录屏条上停止，或 ReplayKit 被系统中断时同样走这里。
    public func onScreenCaptureStopped(_ reason: Int32) {
        screenSharing = false
        emitCallback { self.options.onEvent(.localScreenShareAvailable(available: false)) }
    }

    public func onFirstVideoFrame(_ userId: String, streamType: TRTCVideoStreamType, width: Int32, height: Int32) {
        emitCallback {
            self.options.onEvent(
                .firstVideoFrame(
                    userId: userId,
                    streamType: Self.eduStreamType(streamType),
                    width: Int(width),
                    height: Int(height)
                )
            )
        }
    }

    public func onRecvCustomCmdMsgUserId(
        _ userId: String,
        cmdID: Int,
        seq: UInt32,
        message: Data
    ) {
        emitCallback {
            self.options.onCustomMessage(
                TrtcCustomMessage(userId: userId, commandId: cmdID, sequence: seq, data: message)
            )
        }
    }

    public func onConnectionLost() {
        emitCallback { self.options.onEvent(.connectionLost(recoverable: true)) }
    }

    public func onNetworkQuality(_ localQuality: TRTCQualityInfo, remoteQuality: [TRTCQualityInfo]) {
        let remotes = remoteQuality.compactMap { info -> TrtcRemoteNetworkQuality? in
            let remoteUserId = info.userId ?? ""
            guard !remoteUserId.isEmpty else { return nil }
            return TrtcRemoteNetworkQuality(userId: remoteUserId, quality: Int(info.quality.rawValue))
        }
        emitCallback {
            self.options.onEvent(
                .networkQuality(
                    localQuality: Int(localQuality.quality.rawValue),
                    uplinkNetworkQuality: nil,
                    downlinkNetworkQuality: nil,
                    remoteQualities: remotes
                )
            )
        }
    }

    public func onUserVoiceVolume(_ userVolumes: [TRTCVolumeInfo]?, totalVolume: Int) {
        let local = userVolumes?.first { info in
            let volumeUserId = info.userId ?? ""
            return volumeUserId.isEmpty || volumeUserId == userId
        }
        let volume = Int(local?.volume ?? 0)
        emitCallback {
            self.audioLevelListener?(volume)
            self.options.onEvent(.localVoiceLevel(level: volume))
        }
    }

    public func onRecvSEIMsg(_ userId: String, message: Data) {
        guard let serverMs = decodeEduSdkClockSei(message) else { return }
        emitCallback { self.options.onEvent(.sei(userId: userId, serverMs: serverMs)) }
    }

    private func emitCallback(_ block: @escaping () -> Void) {
        callbackQueue.async { [weak self] in
            guard let self else { return }
            self.callbackStateLock.lock()
            let active = self.callbacksActive
            self.callbackStateLock.unlock()
            guard active else { return }
            block()
        }
    }

    private func requireText(_ raw: String, name: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw adapterError("\(name) is required") }
        return value
    }

    private func adapterError(_ message: String) -> NSError {
        NSError(domain: "com.edukits.edusdk.adapter.rtc.trtc", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func listMicrophones() -> [TrtcMediaDevice] {
        let session = AVAudioSession.sharedInstance()
        var inputs = session.availableInputs ?? []
        if inputs.isEmpty {
            try? session.setCategory(
                .playAndRecord,
                mode: .videoChat,
                options: [.allowBluetooth, .defaultToSpeaker]
            )
            inputs = session.availableInputs ?? []
        }
        let devices = inputs.compactMap { port -> TrtcMediaDevice? in
            let deviceId = port.uid
            guard !deviceId.isEmpty else { return nil }
            let label = port.portName.isEmpty ? deviceId : port.portName
            return TrtcMediaDevice(deviceId: deviceId, label: label, kind: Self.kindMicrophone)
        }
        return devices.isEmpty ? Self.fallbackMicrophones : devices
    }

    private func applyPreferredCamera() {
        guard preferredCameraId != nil else { return }
        let manager = trtc.getDeviceManager()
        let wantFront = Self.isFrontCamera(preferredCameraId)
        if manager.isFrontCamera() != wantFront {
            manager.switchCamera(wantFront)
        }
    }

    private func applyPreferredMicrophone() {
        guard let deviceId = preferredMicrophoneId, deviceId != Self.microphoneIdDefault else { return }
        let session = AVAudioSession.sharedInstance()
        guard let port = session.availableInputs?.first(where: { $0.uid == deviceId }) else { return }
        try? session.setPreferredInput(port)
    }

    private func applyPreferredSpeaker() {
        guard let deviceId = preferredSpeakerId else { return }
        let route: TXAudioRoute = Self.isSpeakerphone(deviceId) ? .speakerphone : .earpiece
        trtc.getDeviceManager().setAudioRoute(route)
    }

    private static func isFrontCamera(_ deviceId: String?) -> Bool {
        guard let deviceId, !deviceId.isEmpty else { return true }
        return deviceId == cameraIdFront || deviceId.localizedCaseInsensitiveContains(cameraHintFront)
    }

    private static func isSpeakerphone(_ deviceId: String?) -> Bool {
        guard let deviceId, !deviceId.isEmpty else { return true }
        return deviceId == speakerIdSpeakerphone
            || deviceId.localizedCaseInsensitiveContains(speakerHintSpeakerphone)
    }

    private static let kindCamera = "camera"
    private static let kindMicrophone = "microphone"
    private static let kindSpeaker = "speaker"
    private static let cameraIdFront = "front"
    private static let cameraIdBack = "back"
    private static let cameraHintFront = "front"
    private static let microphoneIdDefault = "default"
    private static let microphoneLabelDefault = "Microphone"
    private static let speakerIdSpeakerphone = "speakerphone"
    private static let speakerIdEarpiece = "earpiece"
    private static let speakerHintSpeakerphone = "speaker"
    private static let speakerLabelSpeakerphone = "Speaker"
    private static let speakerLabelEarpiece = "Earpiece"
    private static let audioVolumeIntervalMs: UInt = 200
    private static let testToneSoundId: SystemSoundID = 1052
    /// 屏幕共享以文字清晰度优先，分辨率高于摄像头流、帧率低于摄像头流。
    private static let screenShareResolution: TRTCVideoResolution = ._1280_720
    private static let screenShareFps: Int32 = 10
    private static let screenShareBitrateKbps: Int32 = 1_600

    private static func trtcStreamType(_ streamType: EduStreamType) -> TRTCVideoStreamType {
        streamType == .screen ? .sub : .big
    }

    private static func eduStreamType(_ streamType: TRTCVideoStreamType) -> EduStreamType {
        streamType == .sub ? .screen : .camera
    }
    private static let fallbackCameras = [
        TrtcMediaDevice(deviceId: cameraIdFront, label: "Front Camera", kind: kindCamera),
        TrtcMediaDevice(deviceId: cameraIdBack, label: "Back Camera", kind: kindCamera),
    ]
    private static let fallbackMicrophones = [
        TrtcMediaDevice(deviceId: microphoneIdDefault, label: microphoneLabelDefault, kind: kindMicrophone),
    ]
    private static let fallbackSpeakers = [
        TrtcMediaDevice(deviceId: speakerIdSpeakerphone, label: speakerLabelSpeakerphone, kind: kindSpeaker),
        TrtcMediaDevice(deviceId: speakerIdEarpiece, label: speakerLabelEarpiece, kind: kindSpeaker),
    ]
}

public func createTencentTrtcIosAdapter(
    options: TencentTrtcIosAdapterOptions = TencentTrtcIosAdapterOptions()
) -> TencentTrtcIosAdapter {
    TencentTrtcIosAdapter(options: options)
}

private func decodeEduSdkClockSei(_ data: Data) -> Int64? {
    let marker = Data([0x45, 0x64, 0x75, 0x53, 0x64, 0x6b, 0x43, 0x6c, 0x6f, 0x63, 0x6b, 0x00, 0x00, 0x00, 0x00, 0x01])
    guard let range = data.range(of: marker) else { return nil }
    guard let text = String(data: data.suffix(from: range.upperBound), encoding: .utf8),
          let jsonStart = text.firstIndex(of: "{"),
          let value = try? JSONSerialization.jsonObject(with: Data(text[jsonStart...].utf8)) as? [String: Any],
          (value["v"] as? NSNumber)?.intValue == 1,
          let serverMs = value["t"] as? NSNumber else { return nil }
    return serverMs.int64Value
}
#endif
