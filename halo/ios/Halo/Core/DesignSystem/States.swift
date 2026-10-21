#if canImport(SwiftUI)
import SwiftUI

// MARK: Skeletons

/// A placeholder block with a soft shimmer. Static when Reduce Motion is on.
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat = Radius.small
    var isCircle = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        shape
            .fill(Surface.raised)
            .overlay {
                if !reduceMotion {
                    GeometryReader { proxy in
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.07), .clear],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * 0.6)
                            .offset(x: phase * proxy.size.width * 1.2)
                    }
                    .clipShape(shape)
                }
            }
            .frame(width: width, height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1 }
            }
            .accessibilityHidden(true)
    }

    private var shape: AnyShape {
        isCircle ? AnyShape(Circle())
                 : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Placeholder for a rail while it loads. Matches the real card sizes so nothing jumps.
struct SkeletonRail: View {
    enum Style { case card, feature, artist, rows }

    var style: Style = .card
    var count = 4

    var body: some View {
        Group {
            switch style {
            case .rows:
                VStack(spacing: Spacing.sm) {
                    ForEach(0..<count, id: \.self) { _ in SkeletonRow() }
                }
            case .card, .feature, .artist:
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        ForEach(0..<count, id: \.self) { _ in card }
                    }
                }
                .scrollDisabled(true)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Loading")
    }

    private var size: CGFloat {
        switch style {
        case .feature: ArtSize.feature
        case .artist: ArtSize.artist
        default: ArtSize.card
        }
    }

    private var card: some View {
        VStack(alignment: style == .artist ? .center : .leading, spacing: 6) {
            SkeletonBlock(width: size, height: size, cornerRadius: Radius.medium,
                          isCircle: style == .artist)
            SkeletonBlock(width: size * 0.8, height: 12)
            SkeletonBlock(width: size * 0.5, height: 10)
        }
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: Spacing.sm) {
            SkeletonBlock(width: ArtSize.row, height: ArtSize.row)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 180, height: 12)
                SkeletonBlock(width: 110, height: 10)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: Empty state

/// Shown when a screen or section has nothing yet. Always says what to do next.
struct EmptyStateView: View {
    var title: String
    var message: String
    var systemImage = "sparkles"
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Spacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(HaloColor.neon)
                .padding(.bottom, Spacing.xxs)
            Text(title).font(HaloFont.section).foregroundStyle(HaloColor.text)
                .multilineTextAlignment(.center)
            Text(message).font(HaloFont.meta).foregroundStyle(HaloColor.mutedText)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(NeonButtonStyle(prominent: false))
                    .padding(.top, Spacing.xs)
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Rail

/// A titled horizontal rail: Halo's unit of discovery. Optional eyebrow explains why the
/// rail exists ("Because you saved…"), and an optional action opens the full list.
struct Rail<Content: View>: View {
    var title: String
    var eyebrow: String?
    var actionTitle: String?
    var action: (() -> Void)?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow.uppercased())
                        .font(HaloFont.eyebrow)
                        .tracking(0.6)
                        .foregroundStyle(HaloColor.primary)
                }
                SectionHeader(title: title, actionTitle: actionTitle, action: action)
            }
            content()
        }
    }
}

// MARK: Cards

/// Square artwork card with a title and subtitle, sized from `ArtSize`.
struct ArtworkCard: View {
    var title: String
    var subtitle: String?
    var artworkURL: URL?
    var size: CGFloat = ArtSize.card
    var badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HaloArtwork(url: artworkURL, size: size, cornerRadius: Radius.medium)
                .overlay(alignment: .topLeading) {
                    if let badge {
                        Text(badge)
                            .font(HaloFont.eyebrow)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .foregroundStyle(.white)
                            .padding(6)
                    }
                }
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(HaloColor.text).lineLimit(2)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(HaloColor.mutedText).lineLimit(1)
            }
        }
        .frame(width: size, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Round artist portrait with a name underneath.
struct ArtistBubble: View {
    var name: String
    var artworkURL: URL?
    var size: CGFloat = ArtSize.artist

    var body: some View {
        VStack(spacing: Spacing.xs) {
            HaloArtwork(url: artworkURL, size: size, cornerRadius: size / 2)
                .overlay(Circle().strokeBorder(HaloColor.neon, lineWidth: 2).padding(-3))
            Text(name).font(.subheadline.weight(.semibold))
                .foregroundStyle(HaloColor.text).lineLimit(1)
        }
        .frame(width: size + 6)
        .accessibilityElement(children: .combine)
    }
}
#endif
