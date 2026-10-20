#if canImport(SwiftUI)
import SwiftUI

/// Halo design tokens. Dark-first; all text styles are Dynamic Type text styles.
/// Palette: "Sunset Ember", warm orange/magenta with a gold highlight, balanced by a cool
/// cyan accent and a cool charcoal ground.
enum HaloColor {
    static let background = Color(hex: 0x0D0B12)
    static let surface = Color(hex: 0x1C1620)
    static let primary = Color(hex: 0xFF6B35)
    static let secondary = Color(hex: 0xE83F6F)
    static let accent = Color(hex: 0x4CC9F0)
    static let text = Color(hex: 0xFFF8F0)
    static let mutedText = Color(hex: 0xB3A9B4)
    /// Warm highlight used sparingly (ratings, "new", active states).
    static let gold = Color(hex: 0xFFC145)
    static let separator = Color.white.opacity(0.08)
    static let danger = Color(hex: 0xFF5C7A)
    static let success = Color(hex: 0x4CD9A0)

    static var neon: LinearGradient {
        LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
    static var cool: LinearGradient {
        // Cool-to-warm: cyan into magenta.
        LinearGradient(colors: [accent, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func moodGradient(_ mood: Mood) -> LinearGradient {
        let colors: [Color] = switch mood {
        case .calm: [Color(hex: 0x3A7BD5), Color(hex: 0x00D2FF)]
        case .happy: [Color(hex: 0xF7971E), Color(hex: 0xFFD200)]
        case .focused: [primary, accent]
        case .energetic: [secondary, Color(hex: 0xFF5F6D)]
        case .romantic: [Color(hex: 0xEE0979), secondary]
        case .sleep: [Color(hex: 0x141E30), Color(hex: 0x4B3F8F)]
        case .workout: [Color(hex: 0xFF416C), Color(hex: 0xFF4B2B)]
        case .travel: [Color(hex: 0x11998E), accent]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// 4-point spacing scale. Screen gutters use `md`; rails separate with `lg`.
enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48
    static let cornerSmall: CGFloat = Radius.small
    static let corner: CGFloat = Radius.medium
    static let cornerLarge: CGFloat = Radius.large
}

/// Corner radii. Always used with `.continuous` corners.
enum Radius {
    /// Rows, small artwork, inline notices.
    static let small: CGFloat = 8
    /// Cards and rail artwork.
    static let medium: CGFloat = 14
    /// Hero surfaces and sheets.
    static let large: CGFloat = 22
}

/// Artwork sizes. One size per role so rails line up across Halo.
enum ArtSize {
    /// List rows.
    static let row: CGFloat = 48
    /// Compact cards (Sparks, mini-player).
    static let compact: CGFloat = 64
    /// Standard rail cards.
    static let card: CGFloat = 140
    /// Featured rail cards (mixes, new releases).
    static let feature: CGFloat = 180
    /// Round artist portraits in rails.
    static let artist: CGFloat = 112
}

/// Surface elevations. Higher levels sit visually closer to the listener.
enum Surface {
    static let base = HaloColor.background
    static let raised = HaloColor.surface
    static let overlay = Color(hex: 0x2A2130)
}

/// Halo's type ramp: expanded SF for display, standard SF for reading. Every style is a
/// Dynamic Type text style so it scales with the listener's settings.
enum HaloFont {
    /// Screen heroes and greetings.
    static let display = Font.system(.largeTitle, weight: .bold).width(.expanded)
    static let hero = display
    /// Screen and detail titles.
    static let title = Font.system(.title2, weight: .bold).width(.expanded)
    /// Rail and section headings.
    static let section = Font.system(.title3, weight: .semibold).width(.expanded)
    /// Card titles and emphasised rows.
    static let headline = Font.system(.headline)
    static let body = Font.system(.body)
    /// Secondary lines: artist names, counts, dates.
    static let meta = Font.system(.subheadline)
    static let caption = Font.system(.caption)
    /// Small uppercase labels (section eyebrows, badges).
    static let eyebrow = Font.system(.caption2, weight: .bold).width(.expanded)
}

/// Motion tokens. Use `HaloMotion.animation(_:reduceMotion:)` so Reduce Motion is respected.
enum HaloMotion {
    /// Default for state changes and navigation-adjacent movement.
    static let standard = Animation.spring(response: 0.38, dampingFraction: 0.86)
    /// Press feedback and small toggles.
    static let quick = Animation.easeOut(duration: 0.15)
    /// Large surfaces (mini-player ↔ Now Playing, sheets).
    static let emphasized = Animation.spring(response: 0.5, dampingFraction: 0.82)

    static func animation(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : animation
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity)
    }
}
#endif
