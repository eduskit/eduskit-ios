import SwiftUI

/// The scrim may fill the classroom; courseware content must remain bounded.
/// Header/footer stay outside the caller's scrolling content, including with IME open.
struct CoursewarePanelViewport<Content: View>: View {
    let preferredHeight: CGFloat
    var alignBottom = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            let inset = MobileClassroomTokens.inset
            let width = min(640, max(0, geo.size.width - inset * 2))
            let height = min(preferredHeight, min(560, max(0, geo.size.height * 0.82)))
            content()
                .frame(width: width, height: height)
                .background(EduColors.surfaceLowest, in: RoundedRectangle(cornerRadius: 20))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(EduColors.outlineVariant, lineWidth: 1))
                .shadow(color: .black.opacity(0.12), radius: 20, y: 8)
                .position(x: geo.size.width / 2, y: alignBottom ? geo.size.height - height / 2 - inset : geo.size.height / 2)
        }
    }
}
