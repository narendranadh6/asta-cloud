import SwiftUI

/// Where every part of the player sits, collapsed (mini player) and expanded (Now Playing).
/// The layer interpolates between the two with one number, so the transition can follow a
/// finger as well as a spring.
struct PlayerGeometry {
    static let miniHeight: CGFloat = 64
    static let miniArt: CGFloat = 44
    static let miniCorner: CGFloat = 18
    /// Height of the Now Playing header (grabber, "Playing from", More).
    static let headerHeight: CGFloat = 64

    var size: CGSize
    var insets: EdgeInsets
    var tabBarHeight: CGFloat
    var accessibilitySize: Bool

    var mini: CGRect {
        CGRect(x: Spacing.xs, y: size.height - insets.bottom - tabBarHeight - Self.miniHeight - 6,
               width: size.width - Spacing.xs * 2, height: Self.miniHeight)
    }

    var full: CGRect { CGRect(origin: .zero, size: size) }

    var miniArt: CGRect {
        let inset = (Self.miniHeight - Self.miniArt) / 2
        return CGRect(x: mini.minX + inset, y: mini.minY + inset, width: Self.miniArt, height: Self.miniArt)
    }

    var artSide: CGFloat {
        if accessibilitySize { return size.width * 0.5 }
        let usable = size.height - insets.top - insets.bottom
        return max(min(size.width - Spacing.lg * 2, usable * 0.44, 440), 120)
    }

    var fullArt: CGRect {
        CGRect(x: (size.width - artSide) / 2, y: insets.top + Self.headerHeight,
               width: artSide, height: artSide)
    }

    /// How far a drag has to travel to go all the way between the two states.
    var travel: CGFloat { max(mini.minY, 1) }
}

/// A page Now Playing can open in the tabs behind it.
enum PlayerRoute {
    case artist(ArtistRoute)
    case album(AlbumRoute)
}

/// Small math helpers for the transition.
enum PlayerMath {
    static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

    static func lerp(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t),
               width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
    }

    /// 0 before `start`, 1 after `end`, eased in between.
    static func window(_ t: CGFloat, _ start: CGFloat, _ end: CGFloat) -> CGFloat {
        let x = min(max((t - start) / (end - start), 0), 1)
        return x * x * (3 - 2 * x)
    }
}
