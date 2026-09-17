import SwiftUI

/// 进课骨架：joinSuccess 前避免白屏；横屏 / 竖屏 / 桌面分形。
struct ClassroomSkeletonView: View {
    var isLandscape: Bool = false
    var isPhone: Bool = true

    private enum Tokens {
        static let gap: CGFloat = 12
        static let pad: CGFloat = 16
        static let pulseDuration: Double = 1.2
        static let portraitFooterHeight: CGFloat = 72
        static let landscapeFooterHeight: CGFloat = 52
        static let landscapeFooterMaxWidth: CGFloat = 420
        static let landscapeFooterBottomPad: CGFloat = 8
        static let desktopRailWidth: CGFloat = 172
        static let desktopFooterHeight: CGFloat = 64
        static let desktopFooterMaxWidth: CGFloat = 420
        static let pulseDimOpacity: Double = 0.55
        static let pulseBrightOpacity: Double = 0.95
    }

    @State private var pulse = false

    var body: some View {
        Group {
            if isLandscape {
                landscapeBody
            } else if isPhone {
                portraitBody
            } else {
                desktopBody
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EduColors.surfaceLowest)
        .onAppear {
            withAnimation(.easeInOut(duration: Tokens.pulseDuration).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private var portraitBody: some View {
        VStack(spacing: 0) {
            bone(radius: EduDimens.radiusXl)
                .frame(height: EduDimens.headerHeightPhone)
            bone(radius: 0)
            bone(radius: EduDimens.radiusXl)
                .frame(height: Tokens.portraitFooterHeight)
        }
    }

    private var landscapeBody: some View {
        ZStack {
            bone(radius: 0)
            VStack(spacing: 0) {
                bone(radius: 0)
                    .frame(height: EduDimens.headerHeightPhone)
                Spacer(minLength: 0)
                bone(radius: EduDimens.radiusXl)
                    .frame(height: Tokens.landscapeFooterHeight)
                    .frame(maxWidth: Tokens.landscapeFooterMaxWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Tokens.pad)
                    .padding(.bottom, Tokens.landscapeFooterBottomPad)
            }
        }
    }

    private var desktopBody: some View {
        VStack(spacing: Tokens.gap) {
            bone(radius: EduDimens.radiusXl)
                .frame(height: EduDimens.headerHeight)
            HStack(spacing: Tokens.gap) {
                bone(radius: EduDimens.radiusXl)
                bone(radius: EduDimens.radiusXl)
                    .frame(width: Tokens.desktopRailWidth)
            }
            bone(radius: EduDimens.radiusXl)
                .frame(height: Tokens.desktopFooterHeight)
                .frame(maxWidth: Tokens.desktopFooterMaxWidth)
                .frame(maxWidth: .infinity)
        }
        .padding(Tokens.pad)
    }

    private func bone(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(EduColors.surfaceLow.opacity(pulse ? Tokens.pulseDimOpacity : Tokens.pulseBrightOpacity))
    }
}
