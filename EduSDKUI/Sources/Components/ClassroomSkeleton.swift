import SwiftUI

/// Static placeholders deliberately avoid shimmer/flashing and respect reduced motion.
struct ClassroomSkeleton: View {
    enum Kind { case board, list, video, videoColumn }
    var kind: Kind = .list
    var body: some View {
        GeometryReader { geo in
            if kind == .board {
                VStack(alignment: .leading, spacing: 12) {
                    bar.frame(width: geo.size.width * 0.28, height: 10)
                    bar.frame(width: geo.size.width * 0.46, height: 10)
                    bar
                    bar.frame(height: 10)
                }.padding(20)
                    .frame(width: geo.size.width * 0.76, height: geo.size.height * 0.76)
                    .background(EduColors.surfaceLowest, in: RoundedRectangle(cornerRadius: 8))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(EduColors.surfaceLow)
            } else if kind == .videoColumn {
                VStack(spacing: 8) { ForEach(0..<3) { _ in bar.frame(height: max(0, geo.size.width - MobileClassroomTokens.gap * 2) * MobileClassroomTokens.boardAspectHeight / MobileClassroomTokens.boardAspectWidth) } }.padding(MobileClassroomTokens.gap)
            } else if kind == .video {
                HStack(spacing: 8) { ForEach(0..<3) { _ in bar.frame(width: MobileClassroomTokens.stageWidth, height: MobileClassroomTokens.stageHeight) } }
                    .padding(.horizontal, 12).padding(.vertical, 8)
            } else {
                VStack(spacing: 12) {
                    ForEach(0..<3) { _ in
                        HStack(spacing: 12) {
                            Circle().fill(EduColors.surfaceContainer).frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 10) {
                                bar.frame(height: 12)
                                bar.frame(width: max(0, geo.size.width * 0.5), height: 12)
                            }
                        }.frame(height: MobileClassroomTokens.memberRow)
                    }
                    Spacer(minLength: 0)
                }.padding(12)
            }
        }
        .background(kind == .videoColumn ? Color(hex: MobileClassroomTokens.landscapeVideo) : EduColors.surfaceLowest).clipped().allowsHitTesting(false)
        .accessibilityElement(children: .ignore).accessibilityLabel(EduI18n.text("statusConnecting"))
        .accessibilityIdentifier("classroom-skeleton")
    }
    private var bar: some View { RoundedRectangle(cornerRadius: 6).fill(kind == .videoColumn ? Color(hex: MobileClassroomTokens.landscapeOutline) : EduColors.surfaceContainer) }
}
