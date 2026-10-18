import Foundation
import Observation

/// Search state machine: idle → loading → loaded/empty/failed, with token pagination.
@MainActor
@Observable
final class SearchViewModel {
    enum Phase {
        case idle
        case loading
        case loaded
        case empty
        case failed(Error)
    }

    var query = ""
    var kind: SearchKind = .song
    private(set) var results: [Track] = []
    private(set) var phase: Phase = .idle
    private(set) var nextPageToken: String?
    private(set) var isLoadingMore = false
    private(set) var loadMoreError: Error?
    private(set) var provider: MetadataProvider?
    private(set) var suggestions: [String] = []
    private(set) var lastSubmitted: (query: String, kind: SearchKind)?

    static let pageSize = 20
    private var generation = 0

    var canLoadMore: Bool { nextPageToken != nil && !isLoadingMore }

    func submit(api: MusicAPI, onRecord: ((String, SearchKind) -> Void)? = nil) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            reset()
            return
        }
        generation += 1
        let current = generation
        phase = .loading
        results = []
        nextPageToken = nil
        loadMoreError = nil
        lastSubmitted = (trimmed, kind)
        do {
            let response = try await api.search(
                query: trimmed, kind: kind, pageToken: nil, limit: Self.pageSize)
            guard current == generation else { return }  // a newer search superseded this one
            results = response.items
            nextPageToken = response.nextPageToken
            provider = response.provider
            phase = response.items.isEmpty ? .empty : .loaded
            onRecord?(trimmed, kind)
        } catch is CancellationError {
            return
        } catch {
            guard current == generation else { return }
            phase = .failed(error)
        }
    }

    func loadMore(api: MusicAPI) async {
        guard let token = nextPageToken, !isLoadingMore, let last = lastSubmitted else { return }
        let current = generation
        isLoadingMore = true
        loadMoreError = nil
        defer { isLoadingMore = false }
        do {
            let response = try await api.search(
                query: last.query, kind: last.kind, pageToken: token, limit: Self.pageSize)
            guard current == generation else { return }
            let existing = Set(results.map(\.videoId))
            results.append(contentsOf: response.items.filter { !existing.contains($0.videoId) })
            nextPageToken = response.nextPageToken
        } catch {
            guard current == generation else { return }
            loadMoreError = error
        }
    }

    func retry(api: MusicAPI) async {
        if let last = lastSubmitted {
            query = last.query
            kind = last.kind
        }
        await submit(api: api)
    }

    func refreshSuggestions(api: MusicAPI) async {
        let prefix = query.trimmingCharacters(in: .whitespaces)
        do {
            try await Task.sleep(nanoseconds: 250_000_000)  // debounce keystrokes
            suggestions = try await api.suggestions(prefix: prefix)
        } catch {
            if !(error is CancellationError) { suggestions = [] }
        }
    }

    func reset() {
        generation += 1
        results = []
        nextPageToken = nil
        phase = .idle
        lastSubmitted = nil
    }

    func shouldLoadMore(after track: Track) -> Bool {
        guard canLoadMore, let index = results.firstIndex(of: track) else { return false }
        return index >= results.count - 5
    }
}
