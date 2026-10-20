import Foundation
import Observation

/// Loads Discover's shelves. Every shelf is real provider data: the official YouTube
/// most-popular music chart plus live and remix searches. Shelves fail independently.
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
        case all = "All", trending = "Trending", live = "Live", remixes = "Remixes"
        var id: String { rawValue }
        var shelves: [Shelf] {
            switch self {
            case .all: Shelf.allCases
            case .trending: [.trending]
            case .live: [.live]
            case .remixes: [.remixes]
            }
        }
    }

    enum ShelfState {
        case loading
        case loaded([Track])
        case failed(Error)
    }

    var filter: Filter = .all
    private(set) var shelves: [Shelf: ShelfState] = [:]
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
        let (t, l, r) = await (trending, live, remixes)
        apply(.trending, t.map { ($0.items, $0.provider) })
        apply(.live, l.map { ($0.items, $0.provider) })
        apply(.remixes, r.map { ($0.items, $0.provider) })
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
