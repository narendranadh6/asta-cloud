import Foundation
import XCTest
#if canImport(MUSECore)
@testable import MUSECore
#else
@testable import MUSE
#endif

@MainActor
final class SearchViewModelTests: XCTestCase {
    private func catalog(_ count: Int) -> [Track] {
        (0..<count).map { index in
            let id = "demo" + String(format: "%07d", index)
            return Track(videoId: id, title: "Song \(index)", channelTitle: "Artist",
                         watchUrl: "https://www.youtube.com/watch?v=\(id)",
                         attribution: Attribution(provider: .demo, label: "demo"))
        }
    }

    func testSubmitPaginatesAndDeduplicates() async {
        let api = MockMusicAPI(catalog: catalog(45))
        let model = SearchViewModel()
        model.query = "song"
        var recorded: [String] = []
        await model.submit(api: api) { query, _ in recorded.append(query) }
        XCTAssertEqual(model.results.count, 20)
        guard case .loaded = model.phase else { return XCTFail("expected loaded") }
        XCTAssertTrue(model.canLoadMore)
        XCTAssertEqual(recorded, ["song"])

        await model.loadMore(api: api)
        await model.loadMore(api: api)
        XCTAssertEqual(model.results.count, 45)
        XCTAssertEqual(Set(model.results.map(\.videoId)).count, 45)
        XCTAssertFalse(model.canLoadMore)
        let calls = await api.searchCalls
        XCTAssertEqual(calls.map(\.pageToken), [nil, "20", "40"])
    }

    func testEmptyAndBlankQueries() async {
        let api = MockMusicAPI(catalog: catalog(3))
        let model = SearchViewModel()
        model.query = "   "
        await model.submit(api: api)
        guard case .idle = model.phase else { return XCTFail("blank query should stay idle") }
        model.query = "zzz-nothing"
        await model.submit(api: api)
        guard case .empty = model.phase else { return XCTFail("expected empty") }
    }

    func testFailureThenRetry() async {
        let api = MockMusicAPI(catalog: catalog(3))
        await api.setFailure(.offline)
        let model = SearchViewModel()
        model.query = "song"
        await model.submit(api: api)
        guard case let .failed(error) = model.phase else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? APIError, .offline)
        await model.retry(api: api)
        guard case .loaded = model.phase else { return XCTFail("expected recovery") }
        XCTAssertEqual(model.results.count, 3)
    }

    func testLoadMoreFailureKeepsResults() async {
        let api = MockMusicAPI(catalog: catalog(30))
        let model = SearchViewModel()
        model.query = "song"
        await model.submit(api: api)
        await api.setFailure(.timedOut)
        await model.loadMore(api: api)
        XCTAssertEqual(model.results.count, 20)
        XCTAssertNotNil(model.loadMoreError)
        await model.loadMore(api: api)
        XCTAssertEqual(model.results.count, 30)
        XCTAssertNil(model.loadMoreError)
    }
}

@MainActor
final class AIDJViewModelTests: XCTestCase {
    func testSendProducesEditableDraft() async {
        let api = MockMusicAPI()
        let model = AIDJViewModel()
        model.input = "late-night coding"
        await model.send(api: api)
        XCTAssertEqual(model.messages.map(\.role), [.user, .assistant])
        let index = try? XCTUnwrap(model.messages.last?.draftIndex)
        XCTAssertEqual(index, 0)
        XCTAssertFalse(model.drafts[0].queue.isEmpty)
        XCTAssertEqual(model.input, "")

        let first = model.drafts[0].queue.items[0].id
        model.drafts[0].queue.remove(id: first)
        XCTAssertFalse(model.drafts[0].queue.items.contains { $0.id == first })
    }

    func testErrorsAreShownAsMessages() async {
        let api = MockMusicAPI()
        await api.setFailure(.server(status: 429, code: "rate_limited", message: "Slow down", retryAfter: 30))
        let model = AIDJViewModel()
        model.input = "anything"
        await model.send(api: api)
        XCTAssertEqual(model.messages.last?.role, .error)
        XCTAssertEqual(model.messages.last?.text, "Slow down")
        XCTAssertFalse(model.isThinking)
    }
}

@MainActor
final class PlaylistStudioViewModelTests: XCTestCase {
    func testRequestMapping() async {
        let model = PlaylistStudioViewModel()
        model.description = "  sunday chai  "
        model.genresText = "melody, , acoustic ,lofi"
        model.language = "Telugu"
        model.mood = .calm
        model.useEnergy = true
        model.energy = 35
        model.durationMinutes = 500
        let request = model.request(excluding: ["aaaaaaaaaaa"])
        XCTAssertEqual(request.description, "sunday chai")
        XCTAssertEqual(request.genres, ["melody", "acoustic", "lofi"])
        XCTAssertEqual(request.language, "Telugu")
        XCTAssertEqual(request.energy, 35)
        XCTAssertEqual(request.durationMinutes, 300)
        XCTAssertEqual(request.excludeVideoIds, ["aaaaaaaaaaa"])
        model.useEnergy = false
        model.language = ""
        XCTAssertNil(model.request().energy)
        XCTAssertNil(model.request().language)
    }

    func testGenerateAndRegenerateKeepsRenamedTitle() async {
        let api = MockMusicAPI()
        let model = PlaylistStudioViewModel()
        model.description = "focus"
        model.durationMinutes = 10
        await model.generate(api: api)
        XCTAssertNotNil(model.draft)
        model.draft?.title = "My Focus"
        let shown = model.draft!.queue.items.map(\.track.videoId)
        await model.regenerate(api: api, shownIDs: shown)
        XCTAssertEqual(model.draft?.title, "My Focus")
        XCTAssertTrue(Set(model.draft!.queue.items.map(\.track.videoId)).isDisjoint(with: shown))
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    func testPersistsAndResets() async {
        let defaults = UserDefaults(suiteName: "muse.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertEqual(settings.browserPreference, .brave)
        XCTAssertTrue(settings.syncPlaylists)
        settings.browserPreference = .systemDefault
        settings.activeMood = .focused
        settings.hasCompletedOnboarding = true
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.browserPreference, .systemDefault)
        XCTAssertEqual(reloaded.activeMood, .focused)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
        reloaded.reset()
        XCTAssertEqual(AppSettings(defaults: defaults).browserPreference, .brave)
        XCTAssertFalse(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }
}

@MainActor
final class DiscoverViewModelTests: XCTestCase {
    func testLoadsAllShelvesAndFilters() async {
        let api = MockMusicAPI()
        let model = DiscoverViewModel()
        await model.load(api: api, language: nil)
        let trending = model.tracks(in: .trending)
        XCTAssertFalse(trending.isEmpty)
        XCTAssertEqual(trending.map(\.viewCount), trending.map(\.viewCount).sorted { ($0 ?? 0) > ($1 ?? 0) })
        XCTAssertEqual(model.provider, .demo)
        model.filter = .live
        XCTAssertEqual(model.visibleShelves, [.live])
    }

    func testOneShelfFailingDoesNotBreakOthers() async {
        let api = MockMusicAPI()
        await api.setFailure(.offline)  // the first request to run fails
        let model = DiscoverViewModel()
        await model.load(api: api, language: "Telugu")
        let failed = DiscoverViewModel.Shelf.allCases.filter {
            if case .failed = model.shelves[$0] { return true } else { return false }
        }
        XCTAssertEqual(failed.count, 1)
        await model.load(api: api, language: "Telugu")  // retry recovers
        XCTAssertTrue(DiscoverViewModel.Shelf.allCases.allSatisfy {
            if case .loaded = model.shelves[$0] { return true } else { return false }
        })
    }
}
