import Foundation
import Observation

/// Loads the server-driven Home feed. Until the first load finishes (or when the server is
/// unreachable) Home shows `HomeViewModel.offlineSections`: the sections that work from data
/// on the device, so Home is never blank.
@MainActor
@Observable
final class HomeViewModel {
    private(set) var sections: [HomeSection] = HomeViewModel.offlineSections
    private(set) var isLoading = false
    private(set) var lastError: Error?
    private(set) var isPersonalized = false
    private(set) var hasLoadedFromServer = false

    /// Loads the feed, retrying once after a short pause if the first attempt fails.
    func loadWithRetry(api: MusicAPI, retryDelay: UInt64 = 1_500_000_000) async {
        await load(api: api)
        guard lastError != nil, !hasLoadedFromServer, !Task.isCancelled else { return }
        try? await Task.sleep(nanoseconds: retryDelay)
        await load(api: api)
    }

    func load(api: MusicAPI) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let feed = try await api.home()
            sections = Self.renderable(feed.sections)
            isPersonalized = feed.personalized
            hasLoadedFromServer = true
            lastError = nil
        } catch is CancellationError {
        } catch {
            lastError = error
            // Keep the last good feed; only a feed that never loaded falls back.
            if !hasLoadedFromServer { sections = Self.offlineSections }
        }
    }

    /// Sections this version of the app knows how to draw, in the server's order.
    static func renderable(_ sections: [HomeSection]) -> [HomeSection] {
        sections.filter { section in
            switch section.layout {
            case .unknown: false
            case .local: localTypes.contains(section.type)
            default: !section.items.isEmpty
            }
        }
    }

    /// Sections the app fills from SwiftData.
    static let localTypes: Set<String> = ["recently_discovered", "your_playlists", "continue_exploring"]

    static let offlineSections: [HomeSection] = [
        HomeSection(
            id: "moods", type: "moods", title: "Play something for…", layout: .tiles,
            items: [
                ("focused", "Focus", "Deep work"), ("calm", "Chill", "Relax & unwind"),
                ("workout", "Workout", "High energy"), ("sleep", "Late Night", "Mellow beats"),
                ("happy", "Feel Good", "Positive vibes"), ("travel", "Travel", "Explore the world"),
            ].map { HomeItem(kind: .mood, id: $0.0, title: $0.1, subtitle: $0.2) },
            score: 90),
        HomeSection(id: "recently_discovered", type: "recently_discovered",
                    title: "Recently discovered", eyebrow: "Songs you opened in Halo",
                    layout: .local, score: 88),
        HomeSection(id: "your_playlists", type: "your_playlists", title: "Your playlists",
                    layout: .local, score: 60),
        HomeSection(id: "continue_exploring", type: "continue_exploring",
                    title: "Continue exploring", eyebrow: "Your recent searches",
                    layout: .local, score: 40),
    ]
}
