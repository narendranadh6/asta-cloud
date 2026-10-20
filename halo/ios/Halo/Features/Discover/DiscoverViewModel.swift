import Foundation
import Observation

/// Loads Discover's shelves. Every shelf is real provider data: the official YouTube
/// most-popular music chart, live and remix searches, and open listening data from
/// ListenBrainz (fresh releases, most listened). Shelves fail independently.
@MainActor
@Observable
final class DiscoverViewModel {
    enum Shelf: String, CaseIterable, Identifiable, Sendable {
        case trending = "Top on YouTube"
        case live = "Live performances"
        case remixes = "Remixes"
        var id: String { rawValue }
    }

    enum Filter: String, CaseIterable, Identifiable, Sendable {
        case all = "All", new = "New", trending = "Trending", live = "Live", remixes = "Remixes"
        var id: String { rawValue }
        var shelves: [Shelf] {
            switch self {
            case .all: Shelf.allCases
            case .new: []
            case .trending: [.trending]
            case .live: [.live]
            case .remixes: [.remixes]
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
    private(set) var provider: MetadataProvider?

    var visibleShelves: [Shelf] { filter.shelves }

    func load(api: MusicAPI, language: String?) async {
        for shelf in Shelf.allCases where shelves[shelf] == nil || isFailed(shelf) {
            shelves[shelf] = .loading
        }
        let prefix = language.map { "\($0) " } ?? ""
        async let trending = Self.capture { try await api.trending(pageToken: nil, limit: 12) }
        async let live = Self.capture {
            try await api.search(query: "\(prefix)live concert", kind: .live, pageToken: nil, limit: 12)
        }
        async let remixes = Self.capture {
            try await api.search(query: "\(prefix)remix", kind: .remix, pageToken: nil, limit: 12)
        }
        async let fresh = Self.capture { try await api.freshReleases(days: 14, upcoming: false, limit: 20) }
        async let popular = Self.capture { try await api.mostListened(range: .week, limit: 10) }
        let (t, l, r) = await (trending, live, remixes)
        apply(.trending, t.map { ($0.items, $0.provider) })
        apply(.live, l.map { ($0.items, $0.provider) })
        apply(.remixes, r.map { ($0.items, $0.provider) })
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

    private func apply(_ shelf: Shelf, _ result: Result<([Track], MetadataProvider), Error>) {
        switch result {
        case let .success((items, provider)):
            shelves[shelf] = .loaded(items)
            self.provider = provider
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
