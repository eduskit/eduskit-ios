import EduSDK

extension UiSnapshot {
    func isTeacherVideoMainStage() -> Bool {
        let phase = joinProgress.phase
        return (phase == .domainsInitializing || phase == .joined) &&
            joinProgress.whiteboard == .disabled
    }

    func featuredTeacherParticipant() -> ClassroomParticipant? {
        let id = teacherUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !id.isEmpty else { return nil }
        let member = members.first { $0.userId == id }
        let displayName: String = {
            if let name = member?.displayName, !name.isEmpty { return name }
            if let name = teacherDisplayName, !name.isEmpty { return name }
            return id
        }()
        let stream = streamInfos.first { $0.userId == id }
        return ClassroomParticipant(
            id: id,
            displayName: displayName,
            roleLabel: member?.role,
            avatarUrl: member?.avatarUrl ?? teacherAvatarUrl,
            initials: nil,
            onStage: true,
            audioMuted: stream?.audioMuted ?? true,
            videoMuted: stream?.videoMuted ?? true
        )
    }
}

func stripParticipantsExcludingTeacher(
    _ stageParticipants: [ClassroomParticipant],
    teacherUserId: String?
) -> [ClassroomParticipant] {
    let id = teacherUserId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !id.isEmpty else { return stageParticipants }
    return stageParticipants.filter { $0.id != id }
}
