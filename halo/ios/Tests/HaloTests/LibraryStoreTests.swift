#if canImport(SwiftData)
import SwiftData
import XCTest
@testable import Halo

/// Persistence tests against an in-memory SwiftData store (run in Xcode on macOS).
@MainActor
final class LibraryStoreTests: XCTestCase {
    private var container: ModelContainer!
    private var store: LibraryStore!

    override func setUp() async throws {
        container = try LibrarySchema.makeContainer(inMemory: true)
        store = LibraryStore(context: container.mainContext)
    }

    private func track(_ index: Int, provider: MetadataProvider = .youtube) -> Track {
        let id = String(format: "trk%08d", index)
        return Track(videoId: id, title: "Song \(index)", channelTitle: "Artist \(index % 3)",
                     durationSeconds: 200, watchUrl: "https://www.youtube.com/watch?v=\(id)",
                     attribution: Attribution(provider: provider, label: "YouTube"))
    }

    func testCreatePlaylistPersistsOrder() throws {
        let playlist = store.createPlaylist(name: "  Road   Trip ", tracks: (0..<4).map { track($0) })
        XCTAssertEqual(playlist.name, "Road Trip")
        XCTAssertEqual(playlist.orderedItems.map(\.videoId), (0..<4).map { track($0).videoId })
        XCTAssertEqual(playlist.totalDurationSeconds, 800)

        // Survives a fresh context on the same container (simulated relaunch of the store).
        let fresh = ModelContext(container)
        let fetched = try fresh.fetch(FetchDescriptor<PlaylistEntity>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched[0].orderedItems.map(\.position), [0, 1, 2, 3])
    }

    func testAddMoveRemoveKeepPositionsContiguous() {
        let playlist = store.createPlaylist(name: "P", tracks: (0..<3).map { track($0) })
        store.add(track(9), to: playlist, at: 1)
        XCTAssertEqual(playlist.orderedItems.map(\.title), ["Song 0", "Song 9", "Song 1", "Song 2"])
        store.moveItems(fromOffsets: IndexSet(integer: 0), toOffset: 4, in: playlist)
        XCTAssertEqual(playlist.orderedItems.map(\.title), ["Song 9", "Song 1", "Song 2", "Song 0"])
        store.removeItems(atOffsets: IndexSet(integer: 1), from: playlist)
        XCTAssertEqual(playlist.orderedItems.map(\.title), ["Song 9", "Song 2", "Song 0"])
        XCTAssertEqual(playlist.orderedItems.map(\.position), [0, 1, 2])
        XCTAssertTrue(playlist.needsSync)
    }

    func testSaveToggleAndDiscovered() {
        let song = track(1)
        store.recordDiscovered(song)
        XCTAssertFalse(store.isSaved(videoId: song.videoId))
        store.setSaved(true, track: song)
        XCTAssertTrue(store.isSaved(videoId: song.videoId))
        XCTAssertEqual(store.savedTracks().count, 1)
        store.setSaved(false, track: song)
        XCTAssertTrue(store.savedTracks().isEmpty)
    }

    func testRecentSearchesDeduplicateAndCap() throws {
        for index in 0..<40 { store.recordSearch("query \(index)", kind: .song) }
        store.recordSearch("QUERY 39", kind: .song)
        let all = try container.mainContext.fetch(FetchDescriptor<RecentSearchEntity>())
        XCTAssertEqual(all.count, LibraryStore.recentSearchLimit)
        XCTAssertEqual(all.filter { $0.query.lowercased() == "query 39" }.count, 1)
    }

    func testYouTubePlaylistIDValidation() {
        let playlist = store.createPlaylist(name: "Linked")
        XCTAssertFalse(store.setYouTubePlaylistID("evil&list=1", on: playlist))
        XCTAssertNil(playlist.youtubePlaylistID)
        XCTAssertTrue(store.setYouTubePlaylistID("PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf", on: playlist))
        XCTAssertEqual(playlist.youtubePlaylistID, "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
    }

    func testRetentionPurgesOldDiscoveriesAndRefreshesMetadata() async throws {
        let old = Date().addingTimeInterval(-40 * 24 * 3600)
        let stale = store.recordDiscovered(track(1), now: old)
        let savedOld = store.recordDiscovered(track(2), now: old)
        savedOld.isSaved = true
        store.save()
        XCTAssertNotNil(stale.modelContext)
        let api = FakeMusicAPI(catalog: [])
        await store.enforceRetention(using: api)
        XCTAssertNil(store.trackEntity(videoId: track(1).videoId))
        let kept = try XCTUnwrap(store.trackEntity(videoId: track(2).videoId))
        XCTAssertFalse(kept.isAvailable)  // mock returns 404 → marked unavailable
        XCTAssertNil(kept.artworkURLString)
    }

    func testWipeAndExport() throws {
        store.createPlaylist(name: "Export", tracks: [track(1)])
        store.setArtist("Velvet Atlas", excluded: false)
        let json = try XCTUnwrap(String(data: store.exportJSON(), encoding: .utf8))
        XCTAssertTrue(json.contains("Velvet Atlas"))
        XCTAssertTrue(json.contains("Export"))
        store.wipeAll()
        XCTAssertTrue(store.allPlaylists().isEmpty)
        XCTAssertTrue(store.artists(excluded: false).isEmpty)
    }

    func testSyncServiceMirrorsPlaylist() async throws {
        let catalog = (0..<4).map { track($0) }
        let api = FakeMusicAPI(catalog: catalog)
        let sync = PlaylistSyncService(api: api, store: store)
        let playlist = store.createPlaylist(name: "Sync", tracks: Array(catalog.prefix(3)))
        try await sync.sync(playlist)
        let remoteID = try XCTUnwrap(playlist.remoteID)
        XCTAssertFalse(playlist.needsSync)

        store.removeItems(atOffsets: IndexSet(integer: 0), from: playlist)
        store.add(catalog[3], to: playlist, at: 0)
        try await sync.sync(playlist)
        let remote = try await api.playlist(id: remoteID)
        XCTAssertEqual(remote.items?.map(\.videoId), playlist.orderedItems.map(\.videoId))
    }
}
#endif
