import SwiftUI
import UIKit

/// The song's own environment behind Now Playing: deep base color from the artwork, a glow
/// near the top, a soft wash of the cover itself, and a darker floor behind the controls.
/// No live blur: the cover is a tiny decoded copy stretched up, which is naturally soft and
/// costs almost nothing to draw.
struct AmbientBackground: View {
    var palette: ArtworkPalette
    var artworkURL: URL?

    @Environment(\.colorSchemeContrast) private var contrast
    @State private var wash: (url: URL, image: UIImage)?

    var body: some View {
        ZStack {
            palette.color(\.base)
            if contrast != .increased, let wash, wash.url == artworkURL {
                Image(uiImage: wash.image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
                    .opacity(0.32)
                    .transition(.opacity)
            }
            RadialGradient(
                colors: [palette.color(\.glow).opacity(0.85), .clear],
                center: UnitPoint(x: 0.3, y: 0.12), startRadius: 0, endRadius: 520)
            // The floor keeps controls and text on a dark, even ground.
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.35),
                    .init(color: palette.color(\.base).opacity(0.92), location: 0.72),
                    .init(color: palette.color(\.base), location: 1),
                ],
                startPoint: .top, endPoint: .bottom)
        }
        .animation(HaloMotion.ambient, value: palette)
        .animation(HaloMotion.ambient, value: wash?.url)
        .task(id: artworkURL) {
            guard let url = artworkURL,
                  let image = await ArtworkPipeline.shared.image(for: url, maxPixels: 32),
                  !Task.isCancelled else { return }
            wash = (url, image)
        }
        .accessibilityHidden(true)
    }
}
