import SwiftUI

private enum AvatarTokens {
    static let iconScale: CGFloat = 0.6
}

/// Centered circular avatar used when an on-stage tile has no video stream.
struct CenteredTileAvatar: View {
    let avatarUrl: String?
    var size: CGFloat = EduDimens.tileAvatarSize

    var body: some View {
        RemoteAvatarImage(avatarUrl: avatarUrl)
            .frame(width: size, height: size)
            .clipShape(Circle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// SwiftUI owns the image request; only successfully loaded pixels replace the
/// bundled person glyph. Identity normalization belongs to Rust Core.
struct RemoteAvatarImage: View {
    let avatarUrl: String?

    private var placeholder: some View {
        GeometryReader { geometry in
            EduIcon(EduIcons.person,
                    size: min(geometry.size.width, geometry.size.height) * AvatarTokens.iconScale,
                    tint: EduColors.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(EduColors.surfaceVariant)
    }

    var body: some View {
        AsyncImage(url: avatarUrl.flatMap { URL(string: $0) }) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                placeholder
            }
        }
        .id(avatarUrl)
    }
}
