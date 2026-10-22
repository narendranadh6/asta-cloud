import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

@MainActor
final class RecordingSpeaker: VoiceSpeaker {
    private(set) var said: [String] = []
    private(set) var stops = 0
    func say(_ text: String, style: SpeechStyle) { said.append(text) }
    func stop() { stops += 1 }
}

final class SessionRankerTests: XCTestCase {
    private func candidate(_ track: Track) -> SessionCandidate {
        SessionCandidate(track: track, score: 0, fit: ["rank": 0.5], source: "intent")
    }

    private func track(_ id: String, artist: String, language: String?, energy: Double?,
                       released: String? = nil) -> Track {
        Track(id: "audius:\(id)", source: .audius, sourceId: id, title: id, artist: artist,
              releaseDate: released, streamUrl: "https://s.test/\(id)", language: language,
              energy: energy, attribution: Attribution(provider: .audius, label: "Audius"))
    }

    func testEnergyLanguageAndExclusionsDecideTheOrder() {
        let pool = [
            track("calm", artist: "A", language: "te", energy: 0.1),
            track("loud", artist: "B", language: "te", energy: 0.95),
            track("english", artist: "C", language: "en", energy: 0.95),
            track("unknown", artist: "D", language: nil, energy: 0.9),
        ].map(candidate)
        var state = SessionState()
        state.vibe[.energy] = VibeTarget(0.9)
        state.language = .only(.telugu)
        var ranked = SessionRanker.rank(pool, for: state).map(\.sourceId)
        XCTAssertEqual(ranked.first, "loud")
        XCTAssertFalse(ranked.contains("english"))  // "only" drops other known languages
        XCTAssertTrue(ranked.contains("unknown"))  // unknown stays, ranked lower
        state.vibe[.energy] = VibeTarget(0.1)
        ranked = SessionRanker.rank(pool, for: state).map(\.sourceId)
        XCTAssertEqual(ranked.first, "calm")
        state.excludedArtists["a"] = .session
        XCTAssertFalse(SessionRanker.rank(pool, for: state).map(\.sourceId).contains("calm"))
        XCTAssertFalse(SessionRanker.rank(pool, for: state, excluding: ["audius:loud"])
            .map(\.sourceId).contains("loud"))
    }

    func testRecencyAndArtistCap() {
        let today = ISO8601DateFormatter().date(from: "2026-06-01T00:00:00Z")!
        let pool = [
            track("old", artist: "A", language: "te", energy: 0.5, released: "1998-03-01"),
            track("new", artist: "B", language: "te", energy: 0.5, released: "2026-05-20"),
            track("b2", artist: "B", language: "te", energy: 0.5, released: "2026-05-21"),
            track("b3", artist: "B", language: "te", energy: 0.5, released: "2026-05-22"),
        ].map(candidate)
        var state = SessionState()
        state.recency = .withinDays(30)
        let recent = SessionRanker.rank(pool, for: state, today: today).map(\.sourceId)
        XCTAssertEqual(recent.last, "old")
        XCTAssertEqual(recent.filter { $0 != "old" }.count, 2)  // at most two by one artist
        state.recency = .decade(1990)
        XCTAssertEqual(SessionRanker.rank(pool, for: state, today: today).first?.sourceId, "old")
    }

    func testRequestCarriesTheSession() {
        var state = SessionState()
        state.apply(IntentParser.parse("Play energetic Telugu songs from the 90s"), current: nil)
        state.excludedArtists["anirudh"] = .session
        let request = SessionCandidatesRequest(state: state, seedTrackID: "audius:x1",
                                               entity: .mention("dsp", kind: .artist),
                                               alsoExclude: ["audius:p1", "bad id"])
        XCTAssertEqual(request.vibe.energy, 0.85)
        XCTAssertEqual(request.language?.primary, "te")
        XCTAssertEqual(request.recency, .init(mode: "decade", value: 1990))
        XCTAssertEqual(request.entity, .init(name: "dsp", kind: "artist"))
        XCTAssertEqual(request.excludedArtists, ["anirudh"])
        XCTAssertEqual(request.excludedTrackIds, ["audius:p1"])  // invalid ids never sent
        let json = String(data: try! JSONEncoder.halo.encode(request), encoding: .utf8)!
        XCTAssertTrue(json.contains("\"seed_track_id\""))
        XCTAssertTrue(json.contains("\"excluded_artists\""))
    }
}

final class HaloQueueTests: XCTestCase {
    func testStartHaloKeepsTheListenersSongsAndReplacesOnlyHalosPicks() {
        var queue = PlaybackQueue()
        queue.replace(with: [makeTrack(1), makeTrack(2), makeTrack(3)], title: "Mix")
        queue.enqueue([makeTrack(9)])
        queue.startHalo([makeTrack(20), makeTrack(21), makeTrack(22)], title: "Halo Drive")
        XCTAssertEqual(queue.current?.track.id, "audius:t20")
        XCTAssertEqual(queue.upNext.map(\.track.id), ["audius:t9", "audius:t21", "audius:t22"])
        XCTAssertEqual(queue.history.map(\.track.id), ["audius:t1"])
        XCTAssertEqual(queue.contextTitle, "Halo Drive")
        queue.replaceUpcomingFlow([makeTrack(30), makeTrack(9), makeTrack(31)])
        XCTAssertEqual(queue.upNext.map(\.track.id), ["audius:t9", "audius:t30", "audius:t31"])
        XCTAssertEqual(queue.current?.track.id, "audius:t20")
    }
}

@MainActor
final class DriveSessionTests: XCTestCase {
    private func makeDrive() -> (DriveSession, PlayerController, FakeEngine, FakeMusicAPI, RecordingSpeaker) {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        let api = FakeMusicAPI()
        let speaker = RecordingSpeaker()
        let drive = DriveSession(api: api, player: player, speaker: speaker)
        drive.start()
        return (drive, player, engine, api, speaker)
    }

    func testASpokenDriveSteersTheMusic() async {
        let (drive, player, engine, api, speaker) = makeDrive()
        await drive.handle("Halo, play some energetic Telugu songs")
        XCTAssertEqual(player.queue.contextTitle, "Halo Drive")
        XCTAssertEqual(player.currentTrack?.language, "te")
        XCTAssertEqual(drive.voiceState, .done)
        XCTAssertTrue(drive.summary.contains("Telugu"))
        XCTAssertEqual(speaker.said.last, "Switching to Telugu.")
        engine.startPlaying()

        player.addToQueue([makeTrack(77)])  // the listener's own song
        await drive.handle("Same vibe but English")
        XCTAssertEqual(drive.state.language, .only(.english))
        XCTAssertEqual(player.queue.upNext.first?.track.id, "audius:t77")  // never moved
        XCTAssertTrue(player.queue.upNext(.flow).allSatisfy { $0.track.language == "en" })
        XCTAssertEqual(speaker.said.last, "Switching to English.")

        let before = player.currentTrack?.id
        await drive.handle("Skip")
        XCTAssertNotEqual(player.currentTrack?.id, before)

        await drive.handle("Who is singing this?")
        XCTAssertEqual(speaker.said.last, player.currentTrack?.artist)
        let requests = await api.sessionRequests.count
        XCTAssertGreaterThanOrEqual(requests, 2)
    }

    func testNamesThatAreNotInTheCatalogSayNothingIsAvailable() async {
        let (drive, player, _, _, speaker) = makeDrive()
        await drive.handle("DSP songs పెట్టు")
        XCTAssertNil(player.currentTrack)
        XCTAssertEqual(speaker.said.last, "Play చేయడానికి ఏమీ లేదు.")
    }

    func testLowConfidenceNeverAgainAsksFirst() async {
        let (drive, player, engine, _, speaker) = makeDrive()
        var feedback: [Rating] = []
        drive.onFeedback = { rating, _ in feedback.append(rating) }
        await drive.handle("Play relaxing Telugu songs")
        engine.startPlaying()
        let song = player.currentTrack?.id
        await drive.handle("Don't recommend this again", confidence: 0.5)
        XCTAssertEqual(speaker.said.last, "Never play this again?")
        XCTAssertEqual(player.currentTrack?.id, song)  // nothing happened yet
        await drive.handle("yes")
        XCTAssertEqual(feedback, [.neverAgain])
        XCTAssertNotEqual(player.currentTrack?.id, song)
        XCTAssertTrue(DriveSession.isYes("అవును"))
        XCTAssertFalse(DriveSession.isNo("piano music"))
    }

    func testDuckingHoldsUntilEveryReasonEnds() {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        player.duck("listening", true)
        player.duck("speaking", true)
        player.duck("listening", false)
        XCTAssertTrue(engine.ducked)
        player.duck("speaking", false)
        XCTAssertFalse(engine.ducked)
    }

    func testOfflineKeepsPlayingAndEndingRestoresFlow() async {
        let (drive, player, engine, api, _) = makeDrive()
        await drive.handle("Play energetic Telugu songs")
        engine.startPlaying()
        let playing = player.currentTrack?.id
        await api.setFailure(.offline)
        await drive.handle("Make it calmer")  // re-ranks the pool on the phone
        XCTAssertEqual(player.currentTrack?.id, playing)
        XCTAssertEqual(drive.state.vibe[.energy]?.value ?? 0, 0.65, accuracy: 0.001)
        drive.end()
        XCTAssertFalse(drive.isActive)
        XCTAssertNil(player.flowProvider)
    }
}
