import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Contract tests: fixtures are real responses captured from the Halo backend.
final class DecodingTests: XCTestCase {
    func testDecodesSearchResponse() throws {
        let response = try JSONDecoder.halo.decode(SearchResponse.self, from: Fixture.data("search"))
        XCTAssertEqual(response.sources, ["audius", "itunes"])
        XCTAssertEqual(response.items.count, 3)
        XCTAssertTrue(response.items.allSatisfy { TrackID.isValid($0.id) && $0.streamURL != nil })
        let preview = response.items[0]
        XCTAssertEqual(preview.source, .itunes)
        XCTAssertTrue(preview.isPreview)
        XCTAssertEqual(preview.attribution.label, "Preview courtesy of Apple Music")
        XCTAssertEqual(preview.externalURL?.host, "music.apple.com")
        let full = response.items[1]
        XCTAssertEqual(full.source, .audius)
        XCTAssertFalse(full.isPreview)
        XCTAssertNotNil(full.artworkURL)
        XCTAssertNotNil(response.nextPageToken)
    }

    func testDecodesMusicBrainzTrackMetadata() throws {
        let meta = try JSONDecoder.halo.decode(
            TrackMetadataResponse.self, from: Fixture.data("track_metadata"))
        XCTAssertTrue(meta.matched)
        let recording = try XCTUnwrap(meta.recording)
        XCTAssertEqual(recording.artistName, "Portishead")
        XCTAssertEqual(recording.isrcs, ["GBF089400250"])
        let album = try XCTUnwrap(recording.album)
        XCTAssertEqual(album.title, "Dummy")
        XCTAssertEqual(album.labels.first?.name, "Go! Beat")
        XCTAssertNotNil(album.coverArtURL)
        XCTAssertEqual(recording.musicBrainzURL?.host, "musicbrainz.org")
        XCTAssertEqual(meta.artist?.name, "Portishead")
    }

    func testDecodesListenBrainzShelvesAndArtistProfile() throws {
        let fresh = try JSONDecoder.halo.decode([FreshRelease].self, from: Fixture.data("fresh_releases"))
        XCTAssertEqual(fresh.first?.releaseName, "Profound Mysteries IV")
        XCTAssertNotNil(fresh.first?.coverArtURL)
        let top = try JSONDecoder.halo.decode([PopularRecording].self, from: Fixture.data("most_listened"))
        XCTAssertEqual(top.first?.searchQuery, "Ellie Goulding Love Me Like You Do")
        let profile = try JSONDecoder.halo.decode(
            ArtistProfileResponse.self, from: Fixture.data("artist_profile"))
        XCTAssertEqual(profile.sources, ["MusicBrainz", "ListenBrainz"])
        XCTAssertEqual(profile.popularRecordings.first?.title, "Roads")
    }

    func testDecodesHomeFeedAndToleratesUnknownLayouts() throws {
        let feed = try JSONDecoder.halo.decode(HomeFeed.self, from: Fixture.data("home"))
        XCTAssertTrue(feed.personalized)
        XCTAssertEqual(feed.sections.first?.type, "because_you_like")
        XCTAssertEqual(feed.sections.first?.layout, .artistRail)
        XCTAssertEqual(feed.sections.first?.eyebrow, "Because you saved Aarav Strings")
        let trending = try XCTUnwrap(feed.sections.first { $0.type == "trending" })
        XCTAssertEqual(trending.items.first?.kind, .track)
        XCTAssertEqual(trending.items.first?.track?.id, trending.items.first?.id)
        XCTAssertNotNil(trending.items.first?.track?.streamURL)
        let future = try XCTUnwrap(feed.sections.last)
        XCTAssertEqual(future.layout, .unknown)
        XCTAssertEqual(future.items.first?.kind, .unknown)
    }

    func testHomeFeedSkipsItemsAndSectionsItCannotRead() throws {
        // An old-style YouTube item and a section missing required fields.
        let json = #"""
        {"personalized": false, "generated_at": "2026-10-20T12:00:00Z", "sections": [
          {"id": "trending", "type": "trending", "title": "Trending", "layout": "rail", "score": 1,
           "items": [
             {"kind": "track", "id": "x", "title": "Old", "track": {"video_id": "dQw4w9WgXcQ"}},
             {"kind": "query", "id": "q", "title": "Lo-fi", "query": "lofi"}]},
          {"id": "broken", "type": "broken", "layout": "rail", "score": 0.5}
        ]}
        """#
        let feed = try JSONDecoder.halo.decode(HomeFeed.self, from: Data(json.utf8))
        XCTAssertEqual(feed.sections.map(\.id), ["trending"])
        XCTAssertEqual(feed.sections.first?.items.map(\.id), ["q"])
    }

    func testDecodesPlaylistWithNaiveMicrosecondDates() throws {
        let playlist = try JSONDecoder.halo.decode(RemotePlaylist.self, from: Fixture.data("playlist"))
        XCTAssertEqual(playlist.name, "Evening")
        XCTAssertEqual(playlist.items?.map(\.position), [0, 1, 2])
        XCTAssertEqual(playlist.itemCount, 3)
        XCTAssertTrue(playlist.items?.allSatisfy { $0.streamUrl != nil && TrackID.isValid($0.trackId) } == true)
    }

    func testDecodesChatDraft() throws {
        let chat = try JSONDecoder.halo.decode(AIChatResponse.self, from: Fixture.data("chat"))
        let draft = try XCTUnwrap(chat.draft)
        XCTAssertFalse(draft.tracks.isEmpty)
        XCTAssertFalse(draft.queries.isEmpty)
        XCTAssertFalse(draft.tracks[0].reasons.isEmpty)
        XCTAssertFalse(draft.sources.isEmpty)
    }

    func testDecodesPreferencesAndTaste() throws {
        let prefs = try JSONDecoder.halo.decode(Preferences.self, from: Fixture.data("preferences"))
        XCTAssertTrue(prefs.personalizationEnabled)
        XCTAssertEqual(prefs.moods, [.calm])
        XCTAssertNotNil(prefs.personalizationConsentAt)
        let taste = try JSONDecoder.halo.decode(TasteProfile.self, from: Fixture.data("taste"))
        XCTAssertTrue(taste.basis.contains("activity inside Halo"))
    }

    func testDecodesUpNextAndHealth() throws {
        let next = try JSONDecoder.halo.decode(UpNextResponse.self, from: Fixture.data("upnext"))
        XCTAssertFalse(next.tracks.isEmpty)
        XCTAssertFalse(next.tracks.contains { $0.track.id == next.seedTrackId })
        XCTAssertNotNil(next.tracks[0].source)
        let health = try JSONDecoder.halo.decode(HealthResponse.self, from: Fixture.data("health"))
        XCTAssertTrue(health.isCatalogConfigured)
        XCTAssertEqual(health.musicSources, ["audius", "itunes"])
        let missing = try JSONDecoder.halo.decode(HealthResponse.self, from: Data(
            #"{"status":"degraded","music_sources":[],"ai_planner":"heuristic","checks":{"catalog":"not_configured"}}"#.utf8))
        XCTAssertFalse(missing.isCatalogConfigured)
    }

    func testUnknownTrackSourceDecodes() throws {
        let json = #"{"id":"future:1","source":"soundcloud","source_id":"1","title":"T","artist":"A","is_preview":false,"attribution":{"provider":"soundcloud","label":"X"}}"#
        let track = try JSONDecoder.halo.decode(Track.self, from: Data(json.utf8))
        XCTAssertEqual(track.source, .unknown)
        XCTAssertNil(track.streamURL)
    }

    func testTrackIDValidation() {
        for valid in ["audius:D7KyD", "jamendo:1532771", "itunes:1440833098"] {
            XCTAssertTrue(TrackID.isValid(valid), valid)
        }
        for invalid in ["", "D7KyD", "youtube:dQw4w9WgXcQ", "audius:", "audius:a/b", "audius:a b",
                        "spotify:x", "audius:" + String(repeating: "x", count: 41)] {
            XCTAssertFalse(TrackID.isValid(invalid), invalid)
        }
    }

    func testOnlyWebURLsAreLoaded() {
        let track = Track(
            id: "audius:x", source: .audius, sourceId: "x", title: "T", artist: "A",
            artworkUrl: "javascript:alert(1)", streamUrl: "file:///etc/passwd",
            externalUrl: "https://audius.co/x", attribution: Attribution(provider: .audius, label: "Audius"))
        XCTAssertNil(track.artworkURL)
        XCTAssertNil(track.streamURL)
        XCTAssertNotNil(track.externalURL)
    }

    func testDecodesRadioStations() throws {
        let json = #"[{"id":"a","name":"Live FM","stream_url":"https://s.test/live","homepage":null,"favicon":null,"tags":["jazz"],"country_code":"IN","language":"telugu","codec":"MP3","bitrate":128,"popularity":5},{"id":"b","name":"Bad","stream_url":"javascript:x","tags":[],"popularity":0}]"#
        let stations = try JSONDecoder.halo.decode([RadioStation].self, from: Data(json.utf8))
        XCTAssertEqual(stations[0].streamURL?.absoluteString, "https://s.test/live")
        XCTAssertNil(stations[1].streamURL)
    }

    func testDateParser() throws {
        let micro = try XCTUnwrap(HaloDateParser.parse("2026-10-18T08:01:02.123456Z"))
        let plain = try XCTUnwrap(HaloDateParser.parse("2026-10-18T08:01:02Z"))
        XCTAssertEqual(micro.timeIntervalSince(plain), 0.123456, accuracy: 0.000_01)
        let offset = try XCTUnwrap(HaloDateParser.parse("2026-10-18T10:01:02+02:00"))
        XCTAssertEqual(offset, plain)
        let naive = try XCTUnwrap(HaloDateParser.parse("2026-10-18T08:01:02.5"))
        XCTAssertEqual(naive.timeIntervalSince(plain), 0.5, accuracy: 0.000_01)
        let negative = try XCTUnwrap(HaloDateParser.parse("2026-10-18T03:01:02-05:00"))
        XCTAssertEqual(negative, plain)
        XCTAssertNil(HaloDateParser.parse("yesterday"))
    }
}
