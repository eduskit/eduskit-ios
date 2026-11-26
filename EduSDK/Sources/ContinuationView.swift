import Foundation

// Read-only Core wire projection. No platform policy or fallback defaults.
public struct ContinuationPreferences: Codable, Sendable {
    public let autoWindow: Bool
    public let backgroundAudio: Bool
    public let backgroundMicrophone: Bool
    enum CodingKeys: String, CodingKey {
        case autoWindow = "auto_window"
        case backgroundAudio = "background_audio"
        case backgroundMicrophone = "background_microphone"
    }
}

public struct ContinuationSettings: Codable, Sendable {
    public let media: ContinuationPreferences
    public let classroomBack: String?
    public let windowClose: String?
    enum CodingKeys: String, CodingKey {
        case media = "media"
        case classroomBack = "classroom_back"
        case windowClose = "window_close"
    }
}

public struct ContinuationSettingsView: Codable, Sendable {
    public let settings: ContinuationSettings
    public let storage: String
    enum CodingKeys: String, CodingKey {
        case settings = "settings"
        case storage = "storage"
    }
}

public struct ContinuationView: Codable, Sendable {
    public let settings: ContinuationSettingsView?
    public let windowState: String
    public let content: String
    public let playbackAllowed: Bool
    public let microphoneAllowed: Bool
    public let cameraAllowed: Bool
    public let screenShareAllowed: Bool
    public let returnEntry: Bool
    public let autoEntrySuppressed: Bool
    public let limitations: [String]
    enum CodingKeys: String, CodingKey {
        case settings = "settings"
        case windowState = "window_state"
        case content = "content"
        case playbackAllowed = "playback_allowed"
        case microphoneAllowed = "microphone_allowed"
        case cameraAllowed = "camera_allowed"
        case screenShareAllowed = "screen_share_allowed"
        case returnEntry = "return_entry"
        case autoEntrySuppressed = "auto_entry_suppressed"
        case limitations = "limitations"
    }
}

