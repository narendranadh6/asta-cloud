import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

@MainActor
final class SearchViewModelTests: XCTestCase {
    private func catalog(_ count: Int) -> [Track] {
        (0..<count).map { index in makeTrack(index) }
    }

    func testSubmitPaginatesAndDeduplicates() async {
        let api = FakeMusicAPI(catalog: catalog(45))
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
        XCTAssertEqual(Set(model.results.map(\.id)).count, 45)
        XCTAssertFalse(model.canLoadMore)
        let calls = await api.searchCalls
        XCTAssertEqual(calls.map(\.pageToken), [nil, "20", "40"])
    }

    func testEmptyAndBlankQueries() async {
        let api = FakeMusicAPI(catalog: catalog(3))
        let model = SearchViewModel()
        model.query = "   "
        await model.submit(api: api)
        guard case .idle = model.phase else { return XCTFail("blank query should stay idle") }
        model.query = "zzz-nothing"
        await model.submit(api: api)
        guard case .empty = model.phase else { return XCTFail("expected empty") }
    }

    func testFailureThenRetry() async {
        let api = FakeMusicAPI(catalog: catalog(3))
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
        let api = FakeMusicAPI(catalog: catalog(30))
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
        let api = FakeMusicAPI()
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
        let api = FakeMusicAPI()
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
        XCTAssertEqual(request.excludeTrackIds, ["aaaaaaaaaaa"])
        model.useEnergy = false
        model.language = ""
        XCTAssertNil(model.request().energy)
        XCTAssertNil(model.request().language)
    }

    func testGenerateAndRegenerateKeepsRenamedTitle() async {
        let api = FakeMusicAPI()
        let model = PlaylistStudioViewModel()
        model.description = "focus"
        model.durationMinutes = 10
        await model.generate(api: api)
        XCTAssertNotNil(model.draft)
        model.draft?.title = "My Focus"
        let shown = model.draft!.queue.items.map(\.track.id)
        await model.regenerate(api: api, shownIDs: shown)
        XCTAssertEqual(model.draft?.title, "My Focus")
        XCTAssertTrue(Set(model.draft!.queue.items.map(\.track.id)).isDisjoint(with: shown))
    }
}

@MainActor
final class AppSettingsTests: XCTestCase {
    func testPersistsAndResets() async {
        let defaults = UserDefaults(suiteName: "halo.tests.\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.syncPlaylists)
        settings.activeMood = .focused
        settings.hasCompletedOnboarding = true
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.activeMood, .focused)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
        reloaded.reset()
        XCTAssertTrue(AppSettings(defaults: defaults).syncPlaylists)
        XCTAssertFalse(AppSettings(defaults: defaults).hasCompletedOnboarding)
    }
}

@MainActor
final class DiscoverViewModelTests: XCTestCase {
    func testLoadsAllShelvesAndFilters() async {
        let api = FakeMusicAPI()
        let model = DiscoverViewModel()
        await model.load(api: api, language: nil)
        let trending = model.tracks(in: .trending)
        XCTAssertFalse(trending.isEmpty)
        XCTAssertEqual(trending.map(\.playCount), trending.map(\.playCount).sorted { ($0 ?? 0) > ($1 ?? 0) })
        XCTAssertEqual(model.sources, ["audius"])
        let genres = await api.trendingGenres
        XCTAssertEqual(Set(genres), [nil, "Electronic", "Hip-Hop/Rap", "Lo-Fi"])
        model.filter = .genres
        XCTAssertEqual(model.visibleShelves, [.electronic, .hipHop, .lofi])
    }

    func testOneShelfFailingDoesNotBreakOthers() async {
        let api = FakeMusicAPI()
        await api.setFailure(.offline)  // the first request to run fails
        let model = DiscoverViewModel()
        await model.load(api: api, language: "Telugu")
        var failed = DiscoverViewModel.Shelf.allCases.filter {
            if case .failed = model.shelves[$0] { return true } else { return false }
        }.count
        if case .failed = model.freshReleases { failed += 1 }
        if case .failed = model.mostListened { failed += 1 }
        XCTAssertEqual(failed, 1)
        await model.load(api: api, language: "Telugu")  // retry recovers
        XCTAssertTrue(DiscoverViewModel.Shelf.allCases.allSatisfy {
            if case .loaded = model.shelves[$0] { return true } else { return false }
        })
        guard case .loaded = model.freshReleases, case .loaded = model.mostListened else {
            return XCTFail("ListenBrainz shelves should recover")
        }
    }

    func testLoadsListenBrainzShelves() async {
        let model = DiscoverViewModel()
        await model.load(api: FakeMusicAPI(), language: nil)
        guard case let .loaded(fresh) = model.freshReleases,
              case let .loaded(popular) = model.mostListened
        else { return XCTFail("expected ListenBrainz shelves") }
        XCTAssertFalse(fresh.isEmpty)
        XCTAssertEqual(popular.count, 10)
        XCTAssertEqual(popular.first?.searchQuery, "\(popular[0].artistName) \(popular[0].title)")
        model.filter = .new
        XCTAssertEqual(model.visibleShelves, [])
        XCTAssertTrue(model.filter.showsOpenData)
    }

    func testDisabledListenBrainzIsHiddenNotAnError() async {
        let api = FakeMusicAPI()
        await api.setDiscoveryDisabled(true)
        let model = DiscoverViewModel()
        await model.load(api: api, language: nil)
        guard case .disabled = model.freshReleases, case .disabled = model.mostListened else {
            return XCTFail("expected disabled")
        }
        guard case .loaded = model.shelves[.trending] else { return XCTFail("catalog still loads") }
    }
}

@MainActor
final class HomeViewModelTests: XCTestCase {
    func testStartsWithOfflineSectionsThenUsesServerOrder() async {
        let model = HomeViewModel()
        XCTAssertEqual(model.sections.map(\.type).first, "moods")
        await model.load(api: FakeMusicAPI())
        XCTAssertTrue(model.hasLoadedFromServer)
        XCTAssertEqual(model.sections.map(\.type), ["moods", "trending"])
    }

    func testDropsUnknownAndEmptySections() {
        let sections = [
            HomeSection(id: "a", type: "future", title: "?", layout: .unknown,
                        items: [HomeItem(kind: .query, id: "x", title: "x")], score: 99),
            HomeSection(id: "b", type: "trending", title: "Empty", layout: .rail, score: 50),
            HomeSection(id: "c", type: "your_playlists", title: "Yours", layout: .local, score: 40),
            HomeSection(id: "d", type: "someday_local", title: "?", layout: .local, score: 30),
        ]
        XCTAssertEqual(HomeViewModel.renderable(sections).map(\.id), ["c"])
    }

    func testFailureKeepsLastGoodFeed() async {
        let api = FakeMusicAPI()
        let model = HomeViewModel()
        await model.load(api: api)
        await api.setFailure(.offline)
        await model.load(api: api)
        XCTAssertEqual(model.sections.map(\.type), ["moods", "trending"])
        XCTAssertEqual(model.lastError as? APIError, .offline)
    }

    func testFirstLoadFailureFallsBackToDeviceSections() async {
        let api = FakeMusicAPI()
        await api.setFailure(.offline)
        let model = HomeViewModel()
        await model.load(api: api)
        XCTAssertFalse(model.hasLoadedFromServer)
        XCTAssertEqual(model.sections, HomeViewModel.offlineSections)
    }
}

@MainActor
final class HomeRetryTests: XCTestCase {
    func testRetriesOnceAfterFirstFailure() async {
        let api = FakeMusicAPI()
        await api.setFailure(.offline)  // only the first request fails
        let model = HomeViewModel()
        await model.loadWithRetry(api: api, retryDelay: 1_000_000)
        XCTAssertTrue(model.hasLoadedFromServer)
        XCTAssertNil(model.lastError)
    }
}
