import PRRadarModelsService
import SwiftUI

/// Circular avatar image for a GitHub author.
/// Shows the avatar from `avatarURL` when available; falls back to initials derived from `displayName`.
struct GitHubAvatarView: View {

    static let avatarSmall: CGFloat = 18
    static let avatarLarge: CGFloat = 33

    let displayName: String
    let avatarURL: String?
    let size: CGFloat

    init(login: String, name: String? = nil, avatarURL: String? = nil, size: CGFloat = 20) {
        self.displayName = name.flatMap { $0.isEmpty ? nil : $0 } ?? login
        self.avatarURL = avatarURL
        self.size = size
    }

    init(author: GitHubAuthor, size: CGFloat = 20) {
        self.init(login: author.login, name: author.name, avatarURL: author.avatarURL, size: size)
    }

    init(author: PRMetadata.Author, size: CGFloat = 20) {
        self.init(login: author.login, name: author.name, avatarURL: author.avatarURL, size: size)
    }

    var body: some View {
        Group {
            if let urlString = avatarURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initialsView
                }
                .frame(width: size, height: size)
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        Circle()
            .fill(Color.secondary.opacity(0.3))
            .overlay(
                Text(initials)
                    .font(.system(size: size * 0.4, weight: .medium))
                    .foregroundStyle(.secondary)
            )
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        if parts.count >= 2,
           let first = parts.first?.first,
           let last = parts.last?.first {
            return "\(first)\(last)".uppercased()
        }
        return String(displayName.prefix(2)).uppercased()
    }
}
