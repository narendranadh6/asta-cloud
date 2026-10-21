import Foundation
import Observation

/// Loads one page (an artist or an album) and remembers whether it is loading, ready or failed.
/// UI-free, so it is unit tested off-device.
@MainActor
@Observable
final class PageLoader<Page: Sendable> {
    enum Phase {
        case loading
        case loaded(Page)
        case failed(Error)
    }

    private(set) var phase: Phase = .loading
    private let fetch: @MainActor () async throws -> Page

    init(fetch: @escaping @MainActor () async throws -> Page) {
        self.fetch = fetch
    }

    var page: Page? {
        if case let .loaded(page) = phase { return page }
        return nil
    }

    func load() async {
        if page == nil { phase = .loading }
        do {
            phase = .loaded(try await fetch())
        } catch is CancellationError {
            return
        } catch {
            // Keep what we have if a refresh fails.
            if page == nil { phase = .failed(error) }
        }
    }
}

extension PageLoader where Page == ArtistPage {
    static func artist(_ id: String, api: MusicAPI) -> PageLoader {
        PageLoader { try await api.artist(id: id) }
    }
}

extension PageLoader where Page == AlbumPage {
    static func album(_ id: String, api: MusicAPI) -> PageLoader {
        PageLoader { try await api.album(id: id) }
    }
}
