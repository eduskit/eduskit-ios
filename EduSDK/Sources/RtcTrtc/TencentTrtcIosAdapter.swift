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

public enum TrtcAdapterEvent {
    case entered(classId: String, userId: String, elapsedMs: Int)
    case exited(classId: String?, reason: Int)
    case remoteUserEntered(userId: String)
    case remoteUserLeft(userId: String, reason: Int)
    case remoteAudioAvailable(userId: String, available: Bool)
    case remoteVideoAvailable(userId: String, available: Bool, streamType: Int)
    case connectionLost(recoverable: Bool)
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
    private var classId: String?
    private var userId: String?
    private var entered = false
    private var preferredCameraId: String?
    private var preferredMicrophoneId: String?
    private var preferredSpeakerId: String?
    private var audioPreviewActive = false
    private var audioLevelListener: ((Int) -> Void)?
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
        trtc.enterRoom(vendorParams, appScene: .videoCall)
    }

    public func exitRoom() {
        guard classId != nil else { return }
        trtc.exitRoom()
    }

    public func startLocalAudio() {
        applyPreferredMicrophone()
        trtc.startLocalAudio(.default)
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
    public func startRemoteVideo(
        userId: String,
        view: UIView,
        streamType: TRTCVideoStreamType = .big
    ) throws {
        trtc.startRemoteView(try requireText(userId, name: "userId"), streamType: streamType, view: view)
    }
    public func stopRemoteVideo(
        userId: String,
        streamType: TRTCVideoStreamType = .big
    ) throws {
        trtc.stopRemoteView(try requireText(userId, name: "userId"), streamType: streamType)
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
                .remoteVideoAvailable(userId: userId, available: available, streamType: Int(TRTCVideoStreamType.big.rawValue))
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

    public func onUserVoiceVolume(_ userVolumes: [TRTCVolumeInfo]?, totalVolume: Int) {
        let local = userVolumes?.first { info in
            let volumeUserId = info.userId ?? ""
            return volumeUserId.isEmpty || volumeUserId == userId
        }
        let volume = Int(local?.volume ?? 0)
        emitCallback { self.audioLevelListener?(volume) }
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
#endif
