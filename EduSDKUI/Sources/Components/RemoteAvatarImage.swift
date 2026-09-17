import SwiftUI

/// Centered circular avatar used when an on-stage tile has no video stream.
struct CenteredTileAvatar: View {
    let avatarUrl: String?
    let initials: String
    var size: CGFloat = EduDimens.tileAvatarSize
    var fontSize: CGFloat = EduDimens.tileAvatarFont

    var body: some View {
        RemoteAvatarImage(avatarUrl: avatarUrl) {
            Text(initials.isEmpty ? "?" : initials)
                .font(EduFont.sans(fontSize, weight: .bold))
                .foregroundStyle(EduColors.onSurfaceVariant)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(EduColors.surfaceVariant)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Renders a remote HTTP(S) avatar while preserving the existing initials fallback.
struct RemoteAvatarImage<Fallback: View>: View {
    let avatarUrl: String?
    let fallback: () -> Fallback

    init(
        avatarUrl: String?,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.avatarUrl = avatarUrl
        self.fallback = fallback
    }

    private var url: URL? {
        guard let value = avatarUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http"
        else { return nil }
        return url
    }

    var body: some View {
        if let url {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                } else {
                    fallback()
                }
            }
        } else {
            fallback()
        }
    }
}
