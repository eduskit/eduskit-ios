import XCTest
import EduSDK
@testable import EduSDKUI

final class AvatarProjectionTest: XCTestCase {
    func testClearedMemberAvatarDoesNotRestoreTheJoinPhoto() {
        let json = #"{"id":"teacher","displayName":"Teacher","roleLabel":"teacher","avatarUrl":null,"onStage":true,"audioMuted":true,"videoMuted":true,"liveStreamName":null,"livePlaying":false,"networkStatus":"unknown","canRemoveFromStage":false}"#
        let teacher = try! JSONDecoder().decode(ClassroomParticipantView.self, from: Data(json.utf8))
        var snapshot = UiSnapshot()
        snapshot.featuredTeacher = ClassroomParticipant(teacher)
        snapshot.teacherUserId = "teacher"
        snapshot.teacherAvatarUrl = "https://cdn.example/old.png"
        snapshot.members = [ClassroomMember(userId: "teacher", avatarUrl: nil)]
        XCTAssertEqual(snapshot.featuredTeacherParticipant()?.displayName, "Teacher")
        XCTAssertNil(snapshot.featuredTeacherParticipant()?.avatarUrl)
    }
}
