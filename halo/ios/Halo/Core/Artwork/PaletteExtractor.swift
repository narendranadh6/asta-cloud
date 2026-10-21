import Foundation

/// An sRGB color with components in 0…1. Plain data so it can be computed off the main thread,
/// cached, and tested without UIKit.
public struct HaloRGB: Equatable, Hashable, Sendable, Codable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func channel(_ c: Double) -> Double {
            c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// WCAG contrast ratio, 1…21.
    public func contrast(with other: HaloRGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    public static let white = HaloRGB(red: 1, green: 1, blue: 1)

    // MARK: HSL

    var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let lightness = (maxC + minC) / 2
        guard maxC != minC else { return (0, 0, lightness) }
        let delta = maxC - minC
        let saturation = lightness > 0.5 ? delta / (2 - maxC - minC) : delta / (maxC + minC)
        var hue: Double
        switch maxC {
        case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue /= 6
        return (hue, saturation, lightness)
    }

    init(hue: Double, saturation: Double, lightness: Double) {
        func component(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1 / 6 { return p + (q - p) * 6 * t }
            if t < 1 / 2 { return q }
            if t < 2 / 3 { return p + (q - p) * (2 / 3 - t) * 6 }
            return p
        }
        guard saturation > 0 else {
            self.init(red: lightness, green: lightness, blue: lightness)
            return
        }
        let q = lightness < 0.5 ? lightness * (1 + saturation) : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        self.init(red: component(p, q, hue + 1 / 3), green: component(p, q, hue),
                  blue: component(p, q, hue - 1 / 3))
    }
}

/// Colors derived from a song's artwork for the player's ambient background.
public struct ArtworkPalette: Equatable, Hashable, Sendable, Codable {
    /// Deep background color. White text on it always meets 7:1 contrast.
    public var base: HaloRGB
    /// A second, lighter background color for gradients.
    public var glow: HaloRGB
    /// The most vivid color, for small accents (progress, active toggles). At least 3:1 on `base`.
    public var accent: HaloRGB

    public init(base: HaloRGB, glow: HaloRGB, accent: HaloRGB) {
        self.base = base
        self.glow = glow
        self.accent = accent
    }

    /// Halo's own colors, used before artwork loads or when there is none.
    public static let halo = ArtworkPalette(
        base: HaloRGB(red: 0.10, green: 0.06, blue: 0.12),
        glow: HaloRGB(red: 0.33, green: 0.12, blue: 0.24),
        accent: HaloRGB(red: 1.0, green: 0.42, blue: 0.21))

    /// A stable palette from text (e.g. the artist name) when artwork fails to load, so
    /// every song still gets its own color.
    public static func fallback(seed: String) -> ArtworkPalette {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 { hash = (hash ^ UInt64(byte)) &* 1099511628211 }
        let hue = Double(hash % 360) / 360
        return PaletteExtractor.finish(
            dominant: HaloRGB(hue: hue, saturation: 0.55, lightness: 0.35),
            vivid: HaloRGB(hue: hue, saturation: 0.8, lightness: 0.6))
    }
}

/// Picks a restrained palette from artwork pixels. Runs on a tiny sample (about 24×24), so it
/// costs well under a millisecond; callers still run it off the main thread and cache it.
public enum PaletteExtractor {
    /// Minimum contrast of white text on the background.
    public static let textContrast = 7.0
    /// Minimum contrast of the accent on the background.
    public static let accentContrast = 3.0

    /// `rgba` holds 4 bytes per pixel (red, green, blue, alpha), row by row.
    public static func palette(rgba: [UInt8], width: Int, height: Int) -> ArtworkPalette? {
        guard width > 0, height > 0, rgba.count >= width * height * 4 else { return nil }
        // 4 bits per channel: 4096 buckets, each remembering its count and color sum.
        var counts = [Int](repeating: 0, count: 4096)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: 4096)
        var total = 0
        for pixel in 0..<(width * height) {
            let offset = pixel * 4
            guard rgba[offset + 3] > 128 else { continue }  // ignore transparent pixels
            let r = rgba[offset], g = rgba[offset + 1], b = rgba[offset + 2]
            let bucket = Int(r >> 4) << 8 | Int(g >> 4) << 4 | Int(b >> 4)
            counts[bucket] += 1
            sums[bucket].0 += Double(r)
            sums[bucket].1 += Double(g)
            sums[bucket].2 += Double(b)
            total += 1
        }
        guard total > 0 else { return nil }
        let buckets: [(color: HaloRGB, count: Int)] = counts.indices.compactMap { index in
            let count = counts[index]
            guard count > 0 else { return nil }
            let sum = sums[index]
            let n = Double(count) * 255
            return (HaloRGB(red: sum.0 / n, green: sum.1 / n, blue: sum.2 / n), count)
        }
        // Dominant: the most common color, nudged toward colorful over grey.
        let dominant = buckets.max { score($0, colorfulWeight: 0.6) < score($1, colorfulWeight: 0.6) }!
        // Vivid: the most saturated color that still covers a meaningful area.
        let minimumShare = max(1, total / 50)
        let vivid = buckets.filter { $0.count >= minimumShare }
            .max { score($0, colorfulWeight: 3) < score($1, colorfulWeight: 3) } ?? dominant
        return finish(dominant: dominant.color, vivid: vivid.color)
    }

    private static func score(_ bucket: (color: HaloRGB, count: Int), colorfulWeight: Double) -> Double {
        let (_, saturation, lightness) = bucket.color.hsl
        // Very dark or very light pixels make poor backgrounds and accents.
        let usable = lightness < 0.06 || lightness > 0.94 ? 0.2 : 1
        return Double(bucket.count).squareRoot() * (1 + colorfulWeight * saturation) * usable
    }

    /// Turns raw picks into a palette that is always readable.
    static func finish(dominant: HaloRGB, vivid: HaloRGB) -> ArtworkPalette {
        let (hue, saturation, _) = dominant.hsl
        // Background: same hue, calmer saturation, dark enough for white text.
        var base = HaloRGB(hue: hue, saturation: min(saturation, 0.55), lightness: 0.2)
        while base.contrast(with: .white) < textContrast {
            let (h, s, l) = base.hsl
            base = HaloRGB(hue: h, saturation: s, lightness: l - 0.02)
        }
        let glow = HaloRGB(hue: hue, saturation: min(saturation * 1.1, 0.65),
                           lightness: min(base.hsl.lightness + 0.14, 0.36))
        let (vHue, vSaturation, _) = vivid.hsl
        var accent = HaloRGB(hue: vHue, saturation: max(vSaturation, 0.45), lightness: 0.62)
        while accent.contrast(with: base) < accentContrast && accent.hsl.lightness < 0.95 {
            let (h, s, l) = accent.hsl
            accent = HaloRGB(hue: h, saturation: s, lightness: l + 0.04)
        }
        return ArtworkPalette(base: base, glow: glow, accent: accent)
    }
}
