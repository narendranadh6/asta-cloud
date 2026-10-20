import Foundation
import Observation

/// Loads Discover's shelves. Every shelf is real, playable music: tracks trending this week
/// on Audius and Jamendo (overall and per genre), plus open listening data from ListenBrainz
/// (fresh releases, most listened). Shelves fail independently.
@MainActor
@Observable
final class DiscoverViewModel {
    enum Shelf: String, CaseIterable, Identifiable, Sendable {
        case trending = "Trending this week"
        case electronic = "Electronic"
        case hipHop = "Hip-hop"
        case lofi = "Lo-fi & chill"
        var id: String { rawValue }

        /// Genre filter sent to the catalog (Audius genre names); nil means all genres.
        var genre: String? {
            switch self {
            case .trending: nil
            case .electronic: "Electronic"
            case .hipHop: "Hip-Hop/Rap"
            case .lofi: "Lo-Fi"
            }
        }
    }

    enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all = "All", new = "New", trending = "Trending", genres = "Genres"
        var id: String { rawValue }
        var shelves: [Shelf] {
            switch self {
            case .all: Shelf.allCases
            case .new: []
            case .trending: [.trending]
            case .genres: [.electronic, .hipHop, .lofi]
            }
        }
        /// Whether the ListenBrainz shelves are shown.
        var showsOpenData: Bool { self == .all || self == .new }
    }

    enum ShelfState {
        case loading
        case loaded([Track])
        case failed(Error)
    }

    /// State of a ListenBrainz shelf. `disabled` means the server has it turned off.
    enum OpenDataState<Value> {
        case loading
        case loaded(Value)
        case disabled
        case failed(Error)
    }

    var filter: Filter = .all
    private(set) var shelves: [Shelf: ShelfState] = [:]
    private(set) var freshReleases: OpenDataState<[FreshRelease]> = .loading
    private(set) var mostListened: OpenDataState<[PopularRecording]> = .loading
    private(set) var sources: [String] = []

    var visibleShelves: [Shelf] { filter.shelves }

    func load(api: MusicAPI, language: String?) async {
        for shelf in Shelf.allCases where shelves[shelf] == nil || isFailed(shelf) {
            shelves[shelf] = .loading
        }
        await withTaskGroup(of: (Shelf, Result<TrendingResponse, Error>).self) { group in
            for shelf in Shelf.allCases {
                group.addTask {
                    (shelf, await Self.capture {
                        try await api.trending(genre: shelf.genre, limit: 12)
                    })
                }
            }
            for await (shelf, result) in group {
                apply(shelf, result.map { ($0.items, $0.sources) })
            }
        }
        async let fresh = Self.capture { try await api.freshReleases(days: 14, upcoming: false, limit: 20) }
        async let popular = Self.capture { try await api.mostListened(range: .week, limit: 10) }
        freshReleases = Self.openData(await fresh)
        mostListened = Self.openData(await popular)
    }

    private static func openData<Value>(_ result: Result<Value, Error>) -> OpenDataState<Value> {
        switch result {
        case let .success(value): return .loaded(value)
        case let .failure(error as APIError) where error.code == "discovery_disabled": return .disabled
        case let .failure(error): return .failed(error)
        }
    }

    func tracks(in shelf: Shelf) -> [Track] {
        if case let .loaded(items) = shelves[shelf] { return items }
        return []
    }

    private func isFailed(_ shelf: Shelf) -> Bool {
        if case .failed = shelves[shelf] { return true }
        return false
    }

    private func apply(_ shelf: Shelf, _ result: Result<([Track], [String]), Error>) {
        switch result {
        case let .success((items, sources)):
            shelves[shelf] = .loaded(items)
            if !sources.isEmpty { self.sources = sources }
        case let .failure(error):
            shelves[shelf] = .failed(error)
        }
    }

    private static func capture<T: Sendable>(_ work: @Sendable () async throws -> T) async
        -> Result<T, Error>
    {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
