import EduSDK

extension UiSnapshot {
    func isTeacherVideoMainStage() -> Bool { classroomView.teacherVideoStage }
    func featuredTeacherParticipant() -> ClassroomParticipant? { featuredTeacher }
}

/// 正在共享屏幕的人，及其显示名。Core 保证同一时刻至多一路共享。
struct ScreenSharePresenter: Equatable {
    let userId: String
    let displayName: String
}

extension UiSnapshot {
    /// 共享期间主舞台让位给辅流。谁在共享完全由 Core 的 `screenShareUserIds` 决定，
    /// UI 不做挑选，只负责把显示名补齐。
    func screenSharePresenter() -> ScreenSharePresenter? {
        guard let userId = screenShareUserIds.first else { return nil }
        let name = members.first { $0.userId == userId }?.displayName
        return ScreenSharePresenter(
            userId: userId,
            displayName: name?.isEmpty == false ? name! : userId
        )
    }
}
