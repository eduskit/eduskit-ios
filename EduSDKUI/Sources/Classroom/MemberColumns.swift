import EduSDK

enum MemberColumns {
    static let stageStatusOn = "on"

    static func split(
        onStageUsers: [StageUser],
        members: [ClassroomMember]
    ) -> (onStage: [ClassroomMember], audience: [ClassroomMember]) {
        let directory = Dictionary(uniqueKeysWithValues: members.map { ($0.userId, $0) })
        let onStageIds = Set(onStageUsers.map(\.userId))
        let onStage = onStageUsers.map { user in
            directory[user.userId] ?? ClassroomMember(
                userId: user.userId,
                stageStatus: stageStatusOn,
                displayName: user.displayName
            )
        }
        let audience = members.filter { member in
            member.stageStatus != stageStatusOn && !onStageIds.contains(member.userId)
        }
        return (onStage, audience)
    }
}
