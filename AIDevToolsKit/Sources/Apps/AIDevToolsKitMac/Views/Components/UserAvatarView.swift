import AppKit
import SwiftUI

struct UserAvatarView: View {
    let photoURL: URL?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.blue)
                    .padding(size * 0.08)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var image: NSImage? {
        guard let photoURL else { return nil }
        return NSImage(contentsOf: photoURL)
    }
}
