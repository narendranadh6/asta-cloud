import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

final class EntityPageDecodingTests: XCTestCase {
    func testDecodesArtistAndAlbumPagesFromTheServerShape() throws {
        let track = #"{"id":"jamendo:1","source":"jamendo","source_id":"1","title":"First","artist":"Kaveri Echo","artist_id":"77","album":"Rivers","album_id":"900","duration_seconds":200,"stream_url":"https://j/1.mp3","is_preview":false,"license":{"name":"CC BY 4.0","url":"https://creativecommons.org/licenses/by/4.0/"},"attribution":{"provider":"jamendo","label":"Jamendo"}}"#
        let artistJSON = #"{"id":"jamendo:77","source":"jamendo","name":"Kaveri Echo","handle":null,"artwork_url":"https://j/a.jpg","cover_url":null,"bio":null,"follower_count":null,"external_url":"https://jamendo.com/a/77","attribution":{"provider":"jamendo","label":"Jamendo"},"top_tracks":[\#(track)],"albums":[{"id":"jamendo:900","source":"jamendo","title":"Rivers","artist":"Kaveri Echo","artist_id":"jamendo:77","artwork_url":null,"release_date":"2025-04-01","track_count":2,"external_url":null}]}"#
        let artist = try JSONDecoder.halo.decode(ArtistPage.self, from: Data(artistJSON.utf8))
        XCTAssertEqual(artist.topTracks.first?.albumId, "900")
        XCTAssertEqual(artist.albums.first?.year, "2025")
        XCTAssertEqual(artist.externalURL?.host, "jamendo.com")

        let albumJSON = #"{"id":"jamendo:900","source":"jamendo","title":"Rivers","artist":"Kaveri Echo","artist_id":"jamendo:77","artwork_url":"https://j/r.jpg","artwork_url_large":null,"release_date":"2025-04-01","track_count":2,"external_url":null,"attribution":{"provider":"jamendo","label":"Jamendo"},"tracks":[\#(track),\#(track)]}"#
        let album = try JSONDecoder.halo.decode(AlbumPage.self, from: Data(albumJSON.utf8))
        XCTAssertEqual(album.totalSeconds, 400)
        XCTAssertEqual(album.largeArtworkURL?.lastPathComponent, "r.jpg")  // falls back to artwork
    }

    func testTracksLinkToTheirArtistAndAlbumPages() {
        var track = makeTrack(1)
        XCTAssertNil(track.artistPageID)
        track.artistId = "u1"
        XCTAssertEqual(track.artistPageID, "audius:u1")
        XCTAssertNil(track.albumPageID)
        track.albumId = "PlA1"
        XCTAssertEqual(track.albumPageID, "audius:PlA1")
        track.artistId = "../etc"
        XCTAssertNil(track.artistPageID)  // never builds an unsafe path
        track.source = .itunes
        track.artistId = "123"
        XCTAssertNil(track.artistPageID)  // previews have no artist pages
    }
}

@MainActor
final class PageLoaderTests: XCTestCase {
    func testLoadsArtistAndAlbumAndReportsFailures() async {
        let api = FakeMusicAPI()
        let artist = PageLoader<ArtistPage>.artist("audius:tstArtist", api: api)
        await artist.load()
        XCTAssertEqual(artist.page?.topTracks.count, 4)
        XCTAssertEqual(artist.page?.albums.first?.id, "audius:tstAlbum")

        let album = PageLoader<AlbumPage>.album("audius:tstAlbum", api: api)
        await album.load()
        XCTAssertEqual(album.page?.tracks.count, 3)

        let missing = PageLoader<ArtistPage>.artist("audius:nobody", api: api)
        await missing.load()
        guard case let .failed(error) = missing.phase else { return XCTFail("expected failure") }
        XCTAssertEqual((error as? APIError)?.status, 404)

        // A failed refresh keeps the page already on screen.
        await api.setFailure(.offline)
        await artist.load()
        XCTAssertNotNil(artist.page)
    }
}
