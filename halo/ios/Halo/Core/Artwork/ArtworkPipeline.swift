#if canImport(UIKit) && canImport(ImageIO)
import ImageIO
import os
import UIKit

/// Loads artwork once, decodes it at the size it is shown, and keeps it in memory, so track
/// changes and scrolling never decode or download twice. Colors for the player come from the
/// same pipeline and are cached per URL.
actor ArtworkPipeline {
    static let shared = ArtworkPipeline()

    /// Decoded images, readable synchronously so a cached cover shows on the first frame.
    nonisolated let memory = ArtworkMemoryCache()

    private let session: URLSession
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var palettes: [URL: ArtworkPalette] = [:]
    private var paletteOrder: [URL] = []
    private let signposter = OSSignposter(subsystem: "app.halo", category: "artwork")

    init() {
        let configuration = URLSessionConfiguration.default
        // Compressed bytes on disk, so a relaunch doesn't download covers again.
        configuration.urlCache = URLCache(memoryCapacity: 8 << 20, diskCapacity: 150 << 20)
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.timeoutIntervalForRequest = 20
        session = URLSession(configuration: configuration)
    }

    /// The image decoded so its longest side is at most `maxPixels`.
    func image(for url: URL, maxPixels: Int) async -> UIImage? {
        let key = ArtworkMemoryCache.key(url, maxPixels)
        if let cached = memory.image(forKey: key) { return cached }
        if let running = inFlight[key] { return await running.value }
        // Detached: downloads and decodes run in parallel, not one at a time on this actor.
        let task = Task<UIImage?, Never>.detached(priority: .userInitiated) { [session, signposter] in
            guard let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true
            else { return nil }
            let state = signposter.beginInterval("decode")
            defer { signposter.endInterval("decode", state) }
            return Self.downsample(data, maxPixels: maxPixels)
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { memory.insert(image, forKey: key) }
        return image
    }

    /// Warms the cache for songs about to play (previous, next).
    func prefetch(_ urls: [URL], maxPixels: Int) {
        for url in urls where memory.image(forKey: ArtworkMemoryCache.key(url, maxPixels)) == nil {
            Task(priority: .utility) { _ = await image(for: url, maxPixels: maxPixels) }
        }
    }

    /// The ambient palette for a cover. Uses a 24-pixel copy; computed once per URL.
    func palette(for url: URL) async -> ArtworkPalette? {
        if let cached = palettes[url] { return cached }
        guard let small = await image(for: url, maxPixels: 64), let cgImage = small.cgImage else {
            return nil
        }
        let state = signposter.beginInterval("palette")
        let palette = Self.samplePixels(cgImage, side: 24).flatMap {
            PaletteExtractor.palette(rgba: $0, width: 24, height: 24)
        }
        signposter.endInterval("palette", state)
        if let palette { remember(palette, for: url) }
        return palette
    }

    private func remember(_ palette: ArtworkPalette, for url: URL) {
        palettes[url] = palette
        paletteOrder.append(url)
        if paletteOrder.count > 300 { palettes[paletteOrder.removeFirst()] = nil }
    }

    /// Decodes straight to the target size; the full-size bitmap is never created.
    private static func downsample(_ data: Data, maxPixels: Int) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(maxPixels, 16),
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func samplePixels(_ image: CGImage, side: Int) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }
}

/// Thread-safe decoded-image cache (NSCache evicts under memory pressure).
final class ArtworkMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.totalCostLimit = 40 << 20  // about 40 MB of decoded pixels
    }

    static func key(_ url: URL, _ maxPixels: Int) -> String { "\(maxPixels)|\(url.absoluteString)" }

    func image(forKey key: String) -> UIImage? { cache.object(forKey: key as NSString) }

    func insert(_ image: UIImage, forKey key: String) {
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        cache.setObject(image, forKey: key as NSString, cost: cost)
    }
}
#endif
