import Foundation
import EduSDK

/// 由 Headless SDK 的成员与上台快照投影得到的 UI 展示模型。
public struct ClassroomParticipant: Identifiable, Hashable {
    public let id: String
    public let displayName: String
    public let roleLabel: String?
    public let avatarUrl: String?
    public let onStage: Bool
    public let audioMuted: Bool
    public let videoMuted: Bool

    public init(
        id: String,
        displayName: String,
        roleLabel: String? = nil,
        avatarUrl: String? = nil,
        onStage: Bool = false,
        audioMuted: Bool = true,
        videoMuted: Bool = true
    ) {
        self.id = id
        self.displayName = displayName
        self.roleLabel = roleLabel
        self.avatarUrl = avatarUrl
        self.onStage = onStage
        self.audioMuted = audioMuted
        self.videoMuted = videoMuted
    }
}

extension ClassroomParticipant {
    init(_ view: ClassroomParticipantView) {
        self.init(id: view.id, displayName: view.displayName, roleLabel: view.roleLabel,
                  avatarUrl: view.avatarUrl, onStage: view.onStage,
                  audioMuted: view.audioMuted, videoMuted: view.videoMuted)
    }
}
