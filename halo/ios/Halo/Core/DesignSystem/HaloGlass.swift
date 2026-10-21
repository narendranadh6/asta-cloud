#if canImport(SwiftUI)
import SwiftUI

/// Halo's three surface levels. Glass is only for things that float above the music, and
/// glass never sits on glass.
///
/// * ground: the screen or the song's ambient background (opaque)
/// * glass: mini player, dock, queue sheet, toasts
/// * solid: primary controls and text, never translucent
enum HaloMaterial {
    /// Tint mixed into glass so it picks up the song's color without losing legibility.
    static let tintOpacity = 0.08
    static let highlight = Color.white.opacity(0.12)
    static let contrastStroke = Color.white.opacity(0.32)
    static let shadow = Color.black.opacity(0.32)
}

/// A floating glass surface. Uses Apple's Liquid Glass on iOS 26 and a material fallback on
/// earlier versions; becomes solid with Reduce Transparency and gains a clear edge with
/// Increase Contrast.
struct HaloGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background(shape.fill(Surface.raised))
                .overlay(shape.strokeBorder(contrastEdge, lineWidth: 1))
        } else {
            glass(content)
        }
    }

    @ViewBuilder
    private func glass(_ content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.tint(tint?.opacity(0.18)), in: shape)
                .overlay(shape.strokeBorder(contrast == .increased ? HaloMaterial.contrastStroke : .clear,
                                            lineWidth: 1))
        } else {
            materialFallback(content)
        }
        #else
        materialFallback(content)
        #endif
    }

    private func materialFallback(_ content: Content) -> some View {
        content
            .background {
                shape.fill(.ultraThinMaterial)
                    .overlay(shape.fill((tint ?? HaloColor.surface).opacity(HaloMaterial.tintOpacity)))
                    .shadow(color: HaloMaterial.shadow, radius: 18, y: 8)
            }
            .overlay {
                // A thin highlight along the top edge gives the glass its thickness.
                shape.strokeBorder(
                    contrast == .increased
                        ? AnyShapeStyle(HaloMaterial.contrastStroke)
                        : AnyShapeStyle(LinearGradient(
                            colors: [HaloMaterial.highlight, .clear],
                            startPoint: .top, endPoint: .bottom)),
                    lineWidth: contrast == .increased ? 1 : 0.5)
            }
    }

    private var contrastEdge: Color {
        contrast == .increased ? HaloMaterial.contrastStroke : HaloColor.separator
    }
}

extension View {
    /// Floating glass (mini player, dock, sheets). See `HaloMaterial`.
    func haloGlass(cornerRadius: CGFloat = Radius.large, tint: Color? = nil) -> some View {
        modifier(HaloGlassSurface(cornerRadius: cornerRadius, tint: tint))
    }
}

extension HaloMotion {
    /// The player's open/close spring (mini player ↔ Now Playing).
    static let player = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Ambient background crossfade between songs.
    static let ambient = Animation.easeInOut(duration: 0.6)
}
#endif
