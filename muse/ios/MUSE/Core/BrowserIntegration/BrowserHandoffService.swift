import Foundation

/// Where a YouTube link should be opened.
public enum BrowserDestination: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Brave via its documented `brave://open-url` deep link, with HTTPS fallback.
    case brave
    /// A plain HTTPS link handed to iOS (default browser, or the YouTube app if iOS
    /// routes the universal link there).
    case systemDefault

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .brave: "Brave"
        case .systemDefault: "Default browser"
        }
    }
}

public enum HandoffError: Error, Equatable, Sendable, LocalizedError {
    case invalidVideoID
    case invalidPlaylistID
    case demoContent
    case openFailed

    public var errorDescription: String? {
        switch self {
        case .invalidVideoID: "This doesn't look like a valid YouTube video."
        case .invalidPlaylistID: "This doesn't look like a valid YouTube playlist."
        case .demoContent:
            "This is a demo-catalog item, not a real YouTube video. Configure YouTube search "
                + "on the server to get real results."
        case .openFailed: "iOS couldn't open the link. Check that a browser is available."
        }
    }
}

public struct HandoffResult: Equatable, Sendable {
    public enum Opener: String, Sendable {
        case brave
        case systemDefault
    }

    public var openedWith: Opener
    public var url: URL
    /// True when Brave was preferred but the HTTPS fallback was used instead.
    public var usedFallback: Bool
}

/// Abstraction over `UIApplication` so handoff logic is unit tested without UIKit.
@MainActor
public protocol URLOpening: AnyObject {
    func canOpen(_ url: URL) -> Bool
    func open(_ url: URL) async -> Bool
}

@MainActor
public protocol BrowserHandoffService: AnyObject {
    func canOpenBrave() -> Bool
    func destinationDescription() -> String
    @discardableResult
    func openYouTubeVideo(id: String) async throws -> HandoffResult
    @discardableResult
    func openYouTubePlaylist(id: String) async throws -> HandoffResult
}

/// Brave adapter with an ordinary HTTPS fallback.
///
/// MUSE only hands a URL to another app. It cannot see or control what happens next:
/// no play/pause, no queue, no progress, no background-audio or ad-blocking guarantees.
@MainActor
public final class BraveBrowserHandoffService: BrowserHandoffService {
    private let opener: URLOpening
    private let preference: @MainActor () -> BrowserDestination

    public init(opener: URLOpening, preference: @escaping @MainActor () -> BrowserDestination) {
        self.opener = opener
        self.preference = preference
    }

    public func canOpenBrave() -> Bool {
        opener.canOpen(BraveURLBuilder.detectionURL)
    }

    public func destinationDescription() -> String {
        switch preference() {
        case .brave:
            canOpenBrave()
                ? "Opens in Brave"
                : "Brave not detected — opens in your default browser"
        case .systemDefault:
            "Opens in your default browser"
        }
    }

    public func openYouTubeVideo(id: String) async throws -> HandoffResult {
        guard let url = YouTubeIdentifier.watchURL(videoID: id) else {
            throw HandoffError.invalidVideoID
        }
        return try await open(url)
    }

    public func openYouTubePlaylist(id: String) async throws -> HandoffResult {
        guard let url = YouTubeIdentifier.playlistURL(playlistID: id) else {
            throw HandoffError.invalidPlaylistID
        }
        return try await open(url)
    }

    /// Opens a track, refusing demo-catalog items.
    @discardableResult
    public func open(track: Track) async throws -> HandoffResult {
        guard !track.isDemo else { throw HandoffError.demoContent }
        return try await openYouTubeVideo(id: track.videoId)
    }

    private func open(_ httpsURL: URL) async throws -> HandoffResult {
        let wantsBrave = preference() == .brave
        if wantsBrave, canOpenBrave(), let braveURL = BraveURLBuilder.openURL(for: httpsURL) {
            if await opener.open(braveURL) {
                return HandoffResult(openedWith: .brave, url: braveURL, usedFallback: false)
            }
        }
        if await opener.open(httpsURL) {
            return HandoffResult(openedWith: .systemDefault, url: httpsURL, usedFallback: wantsBrave)
        }
        throw HandoffError.openFailed
    }
}

#if canImport(UIKit)
import UIKit

/// Production opener using Apple's supported URL-opening APIs.
@MainActor
public final class UIApplicationURLOpener: URLOpening {
    public init() {}

    public func canOpen(_ url: URL) -> Bool {
        UIApplication.shared.canOpenURL(url)
    }

    public func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url, options: [:])
    }
}
#endif
