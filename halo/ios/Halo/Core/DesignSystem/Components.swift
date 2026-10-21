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
                          ? AnyShapeStyle(HaloColor.surface)
                          : AnyShapeStyle(.ultraThinMaterial))
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(HaloColor.surface.opacity(reduceTransparency ? 0 : 0.55))
                    }
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [HaloColor.primary.opacity(0.45), .white.opacity(0.06)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1)
            }
    }
}

extension View {
    func haloCard(cornerRadius: CGFloat = Spacing.corner) -> some View {
        modifier(GlassCard(cornerRadius: cornerRadius))
    }

    /// Standard screen chrome: Halo background and dark scheme.
    func haloScreen() -> some View {
        background(BackgroundGlow().ignoresSafeArea())
            .toolbarBackground(HaloColor.background.opacity(0.8), for: .navigationBar)
            .scrollContentBackground(.hidden)
    }
}

/// Subtle neon glow behind screens. Static (no animation) and dimmer with Reduce Motion.
struct BackgroundGlow: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            HaloColor.background
            if settings.glowEffects {
                RadialGradient(
                    colors: [HaloColor.primary.opacity(reduceMotion ? 0.18 : 0.28), .clear],
                    center: .topLeading, startRadius: 10, endRadius: 420)
                RadialGradient(
                    colors: [HaloColor.secondary.opacity(reduceMotion ? 0.10 : 0.16), .clear],
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
            .font(HaloFont.headline)
            .foregroundStyle(HaloColor.text)
            .padding(.vertical, Spacing.sm)
            .padding(.horizontal, Spacing.lg)
            .frame(minHeight: 44)
            .background {
                Capsule(style: .continuous)
                    .fill(prominent ? AnyShapeStyle(HaloColor.neon) : AnyShapeStyle(HaloColor.surface))
            }
            .overlay {
                if !prominent {
                    Capsule().strokeBorder(HaloColor.primary.opacity(0.6), lineWidth: 1)
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

/// Where a song comes from. Previews get a gold "Preview" badge so a 30-second clip is never
/// mistaken for the full song.
struct SourceBadge: View {
    var isPreview: Bool
    var source: TrackSource?

    var body: some View {
        Text(isPreview ? "Preview" : (source?.label ?? "Full song"))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isPreview ? Color.black : HaloColor.text)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(isPreview ? AnyShapeStyle(HaloColor.gold)
                                                 : AnyShapeStyle(Surface.overlay)))
            .accessibilityLabel(isPreview ? "30-second preview" : "Full song from \(source?.label ?? "Halo")")
    }
}

struct TrackRow: View {
    var track: any TrackDisplayable
    var subtitle: String?
    var showsAttribution = true
    /// Shows a play button; tapping the rest of the row still navigates.
    var onPlay: (() -> Void)?

    @Environment(PlayerController.self) private var player

    private var isCurrent: Bool { player.currentTrack?.id == track.trackID }

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HaloArtwork(url: track.artworkURL, size: ArtSize.row + 8)
                .overlay {
                    if isCurrent {
                        Image(systemName: "waveform")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, isActive: player.phase == .playing)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(.black.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.small, style: .continuous))
                    }
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(HaloFont.headline)
                    .foregroundStyle(isCurrent ? HaloColor.primary : HaloColor.text)
                    .lineLimit(2)
                Text(subtitle ?? track.artist)
                    .font(.subheadline)
                    .foregroundStyle(HaloColor.mutedText)
                    .lineLimit(1)
                if showsAttribution {
                    HStack(spacing: Spacing.xs) {
                        SourceBadge(isPreview: track.isPreview, source: (track as? Track)?.source)
                        if track.durationSeconds != nil && !track.isPreview {
                            Text(DurationFormatter.clock(track.durationSeconds))
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(HaloColor.mutedText)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if let onPlay {
                Button(action: onPlay) {
                    Image(systemName: isCurrent && player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(HaloColor.neon)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isCurrent && player.isPlaying ? "Pause \(track.title)" : "Play \(track.title)")
            }
        }
        .padding(.vertical, Spacing.xxs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
    }
}

struct SectionHeader: View {
    var title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(HaloFont.section)
                .foregroundStyle(HaloColor.text)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HaloColor.accent)
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
            .foregroundStyle(HaloColor.text)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(HaloColor.neon)
                                          : AnyShapeStyle(HaloColor.surface)))
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
            ProgressView().tint(HaloColor.primary)
            Text(message).font(.subheadline).foregroundStyle(HaloColor.mutedText)
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
        .foregroundStyle(HaloColor.text)
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
            .foregroundStyle(HaloColor.mutedText)
            .padding(Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .haloCard(cornerRadius: Spacing.cornerSmall)
    }
}
#endif
