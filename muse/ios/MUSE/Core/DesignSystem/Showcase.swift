#if canImport(SwiftUI)
import SwiftUI

/// The glowing MUSE AI orb used in the tab bar and the AI DJ header.
/// Rotates slowly unless Reduce Motion is on.
struct AIOrb: View {
    var size: CGFloat = 56
    var isActive = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rotation: Double = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(MUSEColor.secondary.opacity(isActive ? 0.55 : 0.35))
                .blur(radius: size * 0.28)
                .scaleEffect(1.15)
            Circle()
                .fill(AngularGradient(
                    colors: [MUSEColor.accent, MUSEColor.primary, MUSEColor.secondary,
                             MUSEColor.accent],
                    center: .center))
                .rotationEffect(.degrees(rotation))
            Circle()
                .fill(RadialGradient(
                    colors: [.white.opacity(0.85), .white.opacity(0.0)],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 1, endRadius: size * 0.45))
                .blendMode(.screen)
            Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1)
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
                rotation = 360
            }
        }
        .accessibilityHidden(true)
    }
}

/// Gradient artwork tile with a symbol, used where real artwork isn't available
/// (moods, genres, collections). Never pretends to be album art.
struct ArtTile: View {
    var gradient: LinearGradient
    var symbol: String
    var title: String
    var subtitle: String?
    var height: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Spacing.corner, style: .continuous)
                    .fill(gradient)
                Image(systemName: symbol)
                    .font(.system(size: height * 0.32, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .frame(height: height)
            .overlay {
                RoundedRectangle(cornerRadius: Spacing.corner, style: .continuous)
                    .strokeBorder(.white.opacity(0.12))
            }
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(MUSEColor.text)
                .lineLimit(1)
            if let subtitle {
                Text(subtitle).font(.caption).foregroundStyle(MUSEColor.mutedText).lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Horizontally scrolling single-selection chips (the mockup's filter rows).
struct ChipBar<Value: Hashable>: View {
    var options: [Value]
    @Binding var selection: Value
    var label: (Value) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                ForEach(options, id: \.self) { option in
                    Chip(title: label(option), isSelected: option == selection) {
                        selection = option
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}

/// Rounded coloured icon used in settings-style rows.
struct IconTile: View {
    var symbol: String
    var color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color))
            .accessibilityHidden(true)
    }
}

/// Settings row: coloured icon, title, optional subtitle.
struct IconRow: View {
    var symbol: String
    var color: Color
    var title: String
    var subtitle: String?

    var body: some View {
        HStack(spacing: Spacing.sm) {
            IconTile(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(MUSEColor.text)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(MUSEColor.mutedText)
                }
            }
        }
    }
}

enum GenreArt {
    static let all: [(name: String, symbol: String, colors: [Color])] = [
        ("Pop", "sparkles", [Color(hex: 0xEE0979), Color(hex: 0xFF6A00)]),
        ("Lo-fi", "headphones", [Color(hex: 0x1F3B57), Color(hex: 0x4CC9F0)]),
        ("Indie", "guitars", [Color(hex: 0x11998E), Color(hex: 0x38EF7D)]),
        ("Hip Hop", "music.mic", [Color(hex: 0xE83F6F), Color(hex: 0xFF6B35)]),
        ("Melody", "music.note", [Color(hex: 0x4CC9F0), Color(hex: 0xE83F6F)]),
        ("Classical", "pianokeys", [Color(hex: 0x1C1620), Color(hex: 0xFFC145)]),
        ("EDM", "waveform", [Color(hex: 0xE83F6F), Color(hex: 0x4CC9F0)]),
        ("Devotional", "sun.haze", [Color(hex: 0xFFC145), Color(hex: 0xFF6B35)]),
    ]

    static func gradient(_ colors: [Color]) -> LinearGradient {
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
#endif
