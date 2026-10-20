#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: Surfaces

/// Translucent card with a faint neon edge. Falls back to an opaque surface when the
/// user enables Reduce Transparency.
struct GlassCard: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var cornerRadius: CGFloat = Spacing.corner

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(reduceTransparency
                          ? AnyShapeStyle(MUSEColor.surface)
                          : AnyShapeStyle(.ultraThinMaterial))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(MUSEColor.surface.opacity(reduceTransparency ? 0 : 0.55))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [MUSEColor.primary.opacity(0.45), .white.opacity(0.06)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            }
    }
}

extension View {
    func museCard(cornerRadius: CGFloat = Spacing.corner) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    /// Standard screen chrome: MUSE background and dark scheme.
    func museScreen() -> some View {
        background(BackgroundGlow().ignoresSafeArea())
            .toolbarBackground(MUSEColor.background.opacity(0.8), for: .navigationBar)
            .scrollContentBackground(.hidden)
    }
}

/// Subtle neon glow behind screens. Static (no animation) and dimmer with Reduce Motion.
struct BackgroundGlow: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            MUSEColor.background
            if settings.glowEffects {
                RadialGradient(
                    colors: [MUSEColor.primary.opacity(reduceMotion ? 0.18 : 0.28), .clear],
                    center: .topLeading, startRadius: 10, endRadius: 420)
                RadialGradient(
                    colors: [MUSEColor.secondary.opacity(reduceMotion ? 0.10 : 0.16), .clear],
                    center: .topTrailing, startRadius: 10, endRadius: 360)
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Buttons

struct NeonButtonStyle: ButtonStyle {
    var prominent = true
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MUSEFont.headline)
            .foregroundStyle(MUSEColor.text)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 44)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? AnyShapeStyle(MUSEColor.neon) : AnyShapeStyle(MUSEColor.surface))
            }
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(MUSEColor.primary.opacity(0.6), lineWidth: 1)
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

enum Haptics {
    @MainActor
    static func tap(enabled: Bool = true) {
        #if canImport(UIKit)
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    @MainActor
    static func success(enabled: Bool = true) {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    @MainActor
    static func warning(enabled: Bool = true) {
        #if canImport(UIKit)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

// MARK: Artwork & rows

struct ArtworkView: View {
    var url: URL?
    var size: CGFloat? = 56
    var cornerRadius: CGFloat = Spacing.cornerSmall

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().scaledToFill()
            default:
                ZStack {
                    MUSEColor.cool.opacity(0.6)
                    Image(systemName: "music.note")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// Source attribution shown next to YouTube metadata (YouTube API Services requirement).
struct AttributionBadge: View {
    var body: some View {
        Label("YouTube", systemImage: "play.rectangle.fill")
            .labelStyle(.titleAndIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(MUSEColor.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color(hex: 0xC4302B).opacity(0.85)))
            .accessibilityLabel("Source: YouTube")
    }
}

struct TrackRow: View {
    var track: any TrackDisplayable
    var subtitle: String?
    var showsAttribution = true

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ArtworkView(url: track.artworkURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(MUSEFont.headline)
                    .foregroundStyle(MUSEColor.text)
                    .lineLimit(2)
                Text(subtitle ?? track.channelTitle)
                    .font(.subheadline)
                    .foregroundStyle(MUSEColor.mutedText)
                    .lineLimit(1)
                if showsAttribution {
                    HStack(spacing: Spacing.xs) {
                        AttributionBadge()
                        if track.durationSeconds != nil {
                            Text(DurationFormatter.clock(track.durationSeconds))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(MUSEColor.mutedText)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [track.title, "by \(track.channelTitle)"]
        if let seconds = track.durationSeconds {
            parts.append(DurationFormatter.approximate(seconds))
        }
        parts.append("from YouTube")
        return parts.joined(separator: ", ")
    }
}

struct SectionHeader: View {
    var title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(MUSEFont.section)
                .foregroundStyle(MUSEColor.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MUSEColor.accent)
            }
        }
    }
}

// MARK: Chips

struct Chip: View {
    var title: String
    var systemImage: String?
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, Spacing.sm)
            .padding(.vertical, Spacing.xs)
            .frame(minHeight: 36)
            .foregroundStyle(MUSEColor.text)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(MUSEColor.neon)
                                          : AnyShapeStyle(MUSEColor.surface)))
            .overlay(Capsule().strokeBorder(.white.opacity(isSelected ? 0 : 0.12)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = Spacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
                       cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: States

struct LoadingStateView: View {
    var message = "Loading…"

    var body: some View {
        VStack(spacing: Spacing.sm) {
            ProgressView().tint(MUSEColor.primary)
            Text(message).font(.subheadline).foregroundStyle(MUSEColor.mutedText)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorStateView: View {
    var error: Error
    var retry: (() -> Void)?

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            Text(error.localizedDescription)
        } actions: {
            if let retry {
                Button("Try again", action: retry).buttonStyle(NeonButtonStyle())
            }
        }
        .foregroundStyle(MUSEColor.text)
    }

    private var title: String {
        (error as? APIError) == .offline ? "You're offline" : "Something went wrong"
    }

    private var symbol: String {
        (error as? APIError) == .offline ? "wifi.slash" : "exclamationmark.triangle"
    }
}

/// Inline notice for limitations and setup problems. Never hidden behind a tap.
struct NoticeBanner: View {
    var text: String
    var systemImage = "info.circle"

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(MUSEColor.mutedText)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .museCard(cornerRadius: Spacing.cornerSmall)
    }
}
#endif
