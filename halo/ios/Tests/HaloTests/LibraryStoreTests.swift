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

    private func track(_ index: Int) -> Track {
        let id = String(format: "trk%05d", index)
        return Track(id: "audius:\(id)", source: .audius, sourceId: id, title: "Song \(index)",
                     artist: "Artist \(index % 3)", durationSeconds: 200,
                     streamUrl: "https://api.audius.co/v1/tracks/\(id)/stream?app_name=Halo",
                     attribution: Attribution(provider: .audius, label: "Audius"))
    }

    func testCreatePlaylistPersistsOrder() throws {
        let playlist = store.createPlaylist(name: "  Road   Trip ", tracks: (0..<4).map { track($0) })
        XCTAssertEqual(playlist.name, "Road Trip")
        XCTAssertEqual(playlist.orderedItems.map(\.trackID), (0..<4).map { track($0).id })
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
        XCTAssertFalse(store.isSaved(trackID: song.id))
        store.setSaved(true, track: song)
        XCTAssertTrue(store.isSaved(trackID: song.id))
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

    func testPlaylistItemsKeepWhatThePlayerNeeds() throws {
        let playlist = store.createPlaylist(name: "Offline-safe", tracks: [track(1)])
        let item = try XCTUnwrap(playlist.orderedItems.first)
        let restored = Track(item: item)
        XCTAssertEqual(restored.id, track(1).id)
        XCTAssertEqual(restored.streamURL, track(1).streamURL)
        XCTAssertFalse(restored.isPreview)
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
        XCTAssertNil(store.trackEntity(trackID: track(1).id))
        let kept = try XCTUnwrap(store.trackEntity(trackID: track(2).id))
        XCTAssertFalse(kept.isAvailable)  // mock returns 404 → marked unavailable
        XCTAssertNil(kept.streamURLString)  // can no longer play
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
        XCTAssertEqual(remote.items?.map(\.trackId), playlist.orderedItems.map(\.trackID))
    }
}
#endif
