import Foundation
import UIKit
import AVKit
import EduSDK

/// Native facts and IO wiring. Core owns settings, capture and window policy.
final class ClassroomContinuationBinding {
    private let options: EduClassroomOptions
    private let worker = DispatchQueue(label: "edusdk.ui.continuation.environment")
    private var environment: [String: Any] = [:] // worker only
    private var report: ContinuationEnvironmentReport? // worker only
    private var owner: UUID? // worker only
    private var closed = false // worker only
    private var observers: [NSObjectProtocol] = [] // Main only
    private weak var scene: UIWindowScene? // Main only
    private var shown = false // Main only
    private let onFailure: (Error) -> Void

    init(options: EduClassroomOptions, onFailure: @escaping (Error) -> Void) {
        precondition(Thread.isMainThread)
        self.options = options; self.onFailure = onFailure
        for name in [UIScene.didActivateNotification, UIScene.willDeactivateNotification,
                     UIScene.willEnterForegroundNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.didDisconnectNotification, UIApplication.didBecomeActiveNotification,
                     UIApplication.willResignActiveNotification, UIApplication.willEnterForegroundNotification,
                     UIApplication.didEnterBackgroundNotification, UIApplication.protectedDataDidBecomeAvailableNotification,
                     UIApplication.protectedDataWillBecomeUnavailableNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] event in
                self?.sample(event)
            })
        }
        sample(nil)
    }
    func presentation(visible: Bool, scene: UIWindowScene?) {
        precondition(Thread.isMainThread)
        shown = visible
        if let scene { self.scene = scene }
        sample(nil)
    }
    private func sample(_ event: Notification?) {
        precondition(Thread.isMainThread)
        let changed = event?.object as? UIScene
        func state(_ candidate: UIScene) -> UIScene.ActivationState {
            if candidate === changed {
                switch event?.name {
                case UIScene.didActivateNotification: return .foregroundActive
                case UIScene.willDeactivateNotification, UIScene.willEnterForegroundNotification: return .foregroundInactive
                case UIScene.didEnterBackgroundNotification: return .background
                case UIScene.didDisconnectNotification: return .unattached
                default: break
                }
            }
            return candidate.activationState
        }
        let scenes = UIApplication.shared.connectedScenes
        // UIKit also supports applications without Scene sessions.
        var applicationState = UIApplication.shared.applicationState
        switch event?.name {
        case UIApplication.didBecomeActiveNotification: applicationState = .active
        case UIApplication.willResignActiveNotification, UIApplication.willEnterForegroundNotification: applicationState = .inactive
        case UIApplication.didEnterBackgroundNotification: applicationState = .background
        default: break
        }
        // Another scene of this app is not this classroom. Until the classroom scene is known, do not invent a background transition.
        let classroomScene = scene
        let appForeground: Bool
        let active: Bool
        if let classroomScene {
            let activation = state(classroomScene)
            appForeground = activation == .foregroundActive || activation == .foregroundInactive
            active = activation == .foregroundActive
        } else if scenes.isEmpty {
            appForeground = applicationState != .background
            active = applicationState == .active
        } else {
            appForeground = true
            active = true
        }
        let classroomVisible = shown && appForeground
        // Scene inactivity does not prove the device is locked. Never cache unlocked into background.
        let value: [String: Any] = ["app_foreground": appForeground, "classroom_visible": classroomVisible,
                                   "window_minimized": false, "lock_state": active ? "unlocked" : "unknown"]
        let application = UIApplication.shared
        let protectionChanging = event?.name == UIApplication.protectedDataWillBecomeUnavailableNotification
        worker.async {
            guard !self.closed else { return }
            var sampled = value
            // Apple permits this property off Main. False proves protected-device lock;
            // true alone does not prove unlock because data protection can be disabled.
            if !application.isProtectedDataAvailable { sampled["lock_state"] = "locked" }
            else if protectionChanging { sampled["lock_state"] = "unknown" }
            self.environment = sampled
            self.publish()
        }
    }
    func configure() throws -> String {
        precondition(!Thread.isMainThread)
        return try worker.sync {
            guard !closed, let host = options.continuation else { throw retired() }
            let defaults: Any = host.defaults.map { ["auto_window": $0.autoWindow,
                "background_audio": $0.backgroundAudio, "background_microphone": $0.backgroundMicrophone] } as Any? ?? NSNull()
            return try encode(["type": "configure", "platform": "mobile",
                "scope": ["application": options.appId, "tenant": host.tenantId, "account": options.userId, "device": host.deviceId],
                "host_defaults": defaults, "host": ["window": host.allowWindow, "background_audio": host.allowBackgroundAudio,
                    "background_microphone": host.allowBackgroundMicrophone],
                "capabilities": capabilities(), "environment": environment])
        }
    }
    func subscribe(_ callback: @escaping ContinuationEnvironmentReport) throws -> () -> Void {
        precondition(!Thread.isMainThread)
        let id = UUID()
        try worker.sync {
            guard !closed else { throw retired() }
            owner = id; report = callback; publish()
        }
        return { [weak self] in
            self?.worker.async { [weak self] in
                guard let self, self.owner == id else { return }
                self.owner = nil; self.report = nil
            }
        }
    }
    func close() {
        worker.async { self.closed = true; self.report = nil; self.owner = nil }
        DispatchQueue.main.async {
            self.observers.forEach(NotificationCenter.default.removeObserver)
            self.observers.removeAll()
        }
    }
    private func publish() {
        guard let report, let id = owner else { return }
        do {
            let request = try encode(["type": "environment", "environment": environment, "capabilities": capabilities()])
            report(request) { [weak self] result in
                self?.worker.async { [weak self] in
                    guard let self, !self.closed, self.owner == id else { return }
                    if case .failure(let error) = result { self.onFailure(error) }
                }
            }
        } catch { onFailure(error) }
    }
    private func capabilities() -> [String: String] {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        let backgroundAudio = modes.contains("audio")
        let microphone = AVAudioSession.sharedInstance().recordPermission
        let window: String
        if #available(iOS 15.0, *), AVPictureInPictureController.isPictureInPictureSupported() {
            window = "available"
        } else {
            window = "unavailable"
        }
        // The window port reparents the live whiteboard surface. It does not use a still image.
        let whiteboard = window
        let microphoneCapability: String = {
            guard backgroundAudio else { return "unavailable" }
            switch microphone {
            case .granted: return "available"
            case .denied: return "unavailable"
            case .undetermined: return "unknown"
            @unknown default: return "unknown"
            }
        }()
        return [
            "manual_window": window,
            "automatic_window": window,
            "background_audio": backgroundAudio ? "available" : "unavailable",
            "background_microphone": microphoneCapability,
            "background_camera": "unavailable",
            "background_screen_share": "unavailable",
            "whiteboard_window": whiteboard,
        ]
    }
    private func encode(_ value: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: value), as: UTF8.self)
    }
    private func retired() -> Error { NSError(domain: "EduSDK.ClassroomEnvironmentRetired", code: 1) }
}
