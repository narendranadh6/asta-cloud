#if canImport(SwiftUI) && DEBUG
import SwiftUI

/// Every Halo design token and component on one screen, for review and screenshots.
/// Debug builds only.
struct DesignCatalogView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                typeRamp
                palette
                Rail(title: "Rail with cards", eyebrow: "Because you saved Glory Box") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: Spacing.sm) {
                            ArtworkCard(title: "Feature card", subtitle: "Artist · 2026",
                                        size: ArtSize.feature, badge: "Album")
                            ArtworkCard(title: "Standard card", subtitle: "Artist")
                            ArtistBubble(name: "Artist")
                        }
                    }
                }
                Rail(title: "Loading rail", eyebrow: "Skeleton") { SkeletonRail(style: .card, count: 3) }
                Rail(title: "Loading rows") { SkeletonRail(style: .rows, count: 2) }
                EmptyStateView(
                    title: "Nothing saved yet", message: "Save songs you like and they'll appear here.",
                    systemImage: "heart", actionTitle: "Search music", action: {})
                    .haloCard()
                HStack(spacing: Spacing.sm) {
                    Button("Primary") {}.buttonStyle(NeonButtonStyle())
                    Button("Secondary") {}.buttonStyle(NeonButtonStyle(prominent: false))
                }
                radii
            }
            .padding(Spacing.md)
        }
        .haloScreen()
        .navigationTitle("Design system")
    }

    private var typeRamp: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text("Display").font(HaloFont.display)
            Text("Title").font(HaloFont.title)
            Text("Section").font(HaloFont.section)
            Text("Headline").font(HaloFont.headline)
            Text("Body text for reading.").font(HaloFont.body)
            Text("Meta · artist · 3:42").font(HaloFont.meta).foregroundStyle(HaloColor.mutedText)
            Text("EYEBROW").font(HaloFont.eyebrow).foregroundStyle(HaloColor.primary)
        }
        .foregroundStyle(HaloColor.text)
    }

    private var palette: some View {
        let swatches: [(String, Color)] = [
            ("Base", Surface.base), ("Raised", Surface.raised), ("Overlay", Surface.overlay),
            ("Primary", HaloColor.primary), ("Secondary", HaloColor.secondary),
            ("Accent", HaloColor.accent), ("Gold", HaloColor.gold),
        ]
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: Spacing.xs)],
                         spacing: Spacing.xs) {
            ForEach(swatches, id: \.0) { name, color in
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: Radius.small, style: .continuous)
                        .fill(color).frame(height: 44)
                        .overlay(RoundedRectangle(cornerRadius: Radius.small).strokeBorder(.white.opacity(0.1)))
                    Text(name).font(.caption2).foregroundStyle(HaloColor.mutedText)
                }
            }
        }
    }

    private var radii: some View {
        HStack(spacing: Spacing.sm) {
            ForEach([("S", Radius.small), ("M", Radius.medium), ("L", Radius.large)], id: \.0) { name, radius in
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(HaloColor.neon).frame(width: 64, height: 64)
                    .overlay(Text(name).font(HaloFont.headline).foregroundStyle(.white))
            }
        }
    }
}
#endif
