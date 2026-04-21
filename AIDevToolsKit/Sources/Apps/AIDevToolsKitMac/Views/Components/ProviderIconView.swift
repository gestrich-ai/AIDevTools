import AppKit
import AIOutputSDK
import SwiftUI

struct ProviderIconView: View {
    let icon: AIProviderIcon?
    var size: CGFloat = 16

    var body: some View {
        if let image = displayImage {
            Image(nsImage: image)
                .renderingMode(.template)
                .frame(width: size, height: size)
                .foregroundStyle(brandColor)
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: size))
                .foregroundStyle(brandColor)
                .frame(width: size, height: size)
        }
    }

    private var brandColor: Color {
        switch icon {
        case .anthropic: Color(red: 0.80, green: 0.44, blue: 0.24)
        case .openAI:    Color(red: 121.0 / 255.0, green: 143.0 / 255.0, blue: 248.0 / 255.0)
        case nil:        .secondary
        }
    }

    private var image: NSImage? {
        guard let resource else { return nil }
        guard let url = Bundle.module.url(
            forResource: resource.name,
            withExtension: resource.extension
        ) else { return nil }
        guard let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }

    private var displayImage: NSImage? {
        guard let image else { return nil }
        let targetSize = NSSize(width: size, height: size)
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize))
        resized.unlockFocus()
        resized.isTemplate = true
        return resized
    }

    private var resource: (name: String, extension: String)? {
        switch icon {
        case .anthropic:
            ("anthropic", "png")
        case .openAI:
            ("openai", "png")
        case nil:
            nil
        }
    }
}
