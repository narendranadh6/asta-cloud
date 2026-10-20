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

enum Spacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
    static let cornerSmall: CGFloat = 10
    static let corner: CGFloat = 18
    static let cornerLarge: CGFloat = 28
}

enum HaloFont {
    static let hero = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let title = Font.system(.title2, design: .rounded).weight(.bold)
    static let section = Font.system(.title3, design: .rounded).weight(.semibold)
    static let headline = Font.system(.headline, design: .rounded)
    static let body = Font.system(.body)
    static let caption = Font.system(.caption)
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
