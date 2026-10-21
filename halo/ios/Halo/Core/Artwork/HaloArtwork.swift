#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI
import UIKit

/// Cover art everywhere in Halo. Decoded at the size it's shown and cached, so it appears
/// instantly when it has been seen before and fades in otherwise.
struct HaloArtwork: View {
    var url: URL?
    /// Point size of a square cover; nil fills the proposed width (Now Playing).
    var size: CGFloat? = 56
    var cornerRadius: CGFloat = Radius.small
    /// For flexible sizes, the largest side to decode, in points.
    var maxPointSize: CGFloat = ArtworkPoints.nowPlaying

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: (url: URL, image: UIImage)?

    var body: some View {
        // A square base sets the size; the image fills it without changing the layout.
        Color.clear
            .frame(width: size, height: size)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ArtworkPlaceholder()
                if let image = currentImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .animation(.easeOut(duration: 0.2), value: loaded?.url)
        .task(id: url) { await load() }
        .accessibilityHidden(true)
    }

    private var maxPixels: Int { Int((size ?? maxPointSize) * displayScale) }

    /// A cached image shows on the first frame; otherwise the last one loaded for this URL.
    private var currentImage: UIImage? {
        guard let url else { return nil }
        if let loaded, loaded.url == url { return loaded.image }
        return ArtworkPipeline.shared.memory.image(forKey: ArtworkMemoryCache.key(url, maxPixels))
    }

    private func load() async {
        guard let url else {
            loaded = nil
            return
        }
        if let image = await ArtworkPipeline.shared.image(for: url, maxPixels: maxPixels),
           !Task.isCancelled {
            loaded = (url, image)
        }
    }
}

/// Point sizes the player decodes at; prefetching uses the same values so it hits the cache.
enum ArtworkPoints {
    static let mini: CGFloat = 44
    static let nowPlaying: CGFloat = 400
}

/// Shown while artwork loads or when there is none: Halo's gradient and a music note.
struct ArtworkPlaceholder: View {
    var body: some View {
        ZStack {
            HaloColor.cool.opacity(0.6)
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}

extension ArtworkPalette {
    func color(_ keyPath: KeyPath<ArtworkPalette, HaloRGB>) -> Color {
        let rgb = self[keyPath: keyPath]
        return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}
#endif
