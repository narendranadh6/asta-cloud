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
        XCTAssertEqual(response.provider, .youtube)
        XCTAssertEqual(response.items.count, 3)
        let track = response.items[0]
        XCTAssertTrue(YouTubeIdentifier.isValidVideoID(track.videoId))
        XCTAssertEqual(track.attribution.label, "YouTube")
        XCTAssertNotNil(track.artworkURL)
        XCTAssertNotNil(track.publishedAt)
        XCTAssertNotNil(response.nextPageToken)
    }

    func testDecodesPlaylistWithNaiveMicrosecondDates() throws {
        let playlist = try JSONDecoder.halo.decode(RemotePlaylist.self, from: Fixture.data("playlist"))
        XCTAssertEqual(playlist.name, "Evening")
        XCTAssertEqual(playlist.items?.map(\.position), [0, 1, 2])
        XCTAssertEqual(playlist.itemCount, 3)
    }

    func testDecodesChatDraft() throws {
        let chat = try JSONDecoder.halo.decode(AIChatResponse.self, from: Fixture.data("chat"))
        let draft = try XCTUnwrap(chat.draft)
        XCTAssertFalse(draft.tracks.isEmpty)
        XCTAssertFalse(draft.queries.isEmpty)
        XCTAssertFalse(draft.tracks[0].reasons.isEmpty)
    }

    func testDecodesPreferencesAndTaste() throws {
        let prefs = try JSONDecoder.halo.decode(Preferences.self, from: Fixture.data("preferences"))
        XCTAssertTrue(prefs.personalizationEnabled)
        XCTAssertEqual(prefs.moods, [.calm])
        XCTAssertNotNil(prefs.personalizationConsentAt)
        let taste = try JSONDecoder.halo.decode(TasteProfile.self, from: Fixture.data("taste"))
        XCTAssertTrue(taste.basis.contains("cannot see what you play in Brave"))
    }

    func testDecodesUpNextAndHealth() throws {
        let next = try JSONDecoder.halo.decode(UpNextResponse.self, from: Fixture.data("upnext"))
        XCTAssertFalse(next.tracks.isEmpty)
        XCTAssertFalse(next.tracks.contains { $0.track.videoId == next.seedVideoId })
        XCTAssertNotNil(next.tracks[0].source)
        let health = try JSONDecoder.halo.decode(HealthResponse.self, from: Fixture.data("health"))
        XCTAssertTrue(health.isSearchConfigured)
        let missing = try JSONDecoder.halo.decode(HealthResponse.self, from: Data(
            #"{"status":"degraded","metadata_provider":"youtube","ai_planner":"heuristic","checks":{"youtube":"not_configured"}}"#.utf8))
        XCTAssertFalse(missing.isSearchConfigured)
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
