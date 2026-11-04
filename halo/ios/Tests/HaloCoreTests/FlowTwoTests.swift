import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

final class ListeningSignalTests: XCTestCase {
    private let song = NowPlayingContext(trackID: "audius:s1", artist: "Sid Sriram")

    func testShortSkipsAreSessionOnlyAndNeverDislikes() {
        var state = SessionState()
        state.record(.skip(heard: 8, duration: 240), for: song)
        XCTAssertEqual(state.inferredArtistWeights["sid sriram"] ?? 0, -0.1, accuracy: 0.001)
        XCTAssertEqual(state.excludedTracks["audius:s1"], .session)  // not .profile
        XCTAssertTrue(state.excludedArtists.isEmpty)
        // Many short skips still stay under one explicit "not too much".
        for _ in 0..<10 { state.record(.skip(heard: 3, duration: 200), for: song) }
        XCTAssertEqual(state.inferredArtistWeights["sid sriram"] ?? 0, -SessionState.SignalWeights.cap, accuracy: 0.001)
    }

    func testLateSkipsCompletionsAndReplaysWeighDifferently() {
        var state = SessionState()
        state.record(.skip(heard: 150, duration: 200), for: song)
        XCTAssertEqual(state.inferredArtistWeights["sid sriram"] ?? 0, -0.03, accuracy: 0.001)
        XCTAssertNil(state.excludedTracks["audius:s1"])  // heard most of it: can come back
        state.record(.complete, for: song)
        state.record(.replay, for: song)
        XCTAssertEqual(state.inferredArtistWeights["sid sriram"] ?? 0, 0.17, accuracy: 0.001)
        XCTAssertEqual(state.keeps, ["audius:s1"])
    }

    func testExplicitRequestsOverrideInferredSignals() {
        var state = SessionState()
        for _ in 0..<4 { state.record(.skip(heard: 2, duration: 200), for: song) }
        state.apply(IntentParser.parse("More from this artist"), current: song)
        XCTAssertEqual(state.effectiveArtistWeights["sid sriram"] ?? 0, 0.6, accuracy: 0.001)
        let request = SessionCandidatesRequest(state: state)
        XCTAssertEqual(request.artistWeights["sid sriram"] ?? 0, 0.6, accuracy: 0.001)
    }

    func testLockStopsDriftButSkippedSongStillDoesntRepeat() {
        var state = SessionState()
        state.locked = true
        state.record(.skip(heard: 5, duration: 200), for: song)
        XCTAssertNil(state.inferredArtistWeights["sid sriram"])
        XCTAssertEqual(state.excludedTracks["audius:s1"], .session)
    }
}

final class TodayExclusionTests: XCTestCase {
    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    func testTodayEndsAtLocalMidnightInTheGivenTimeZone() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        // 23:30 in Kolkata on 4 Nov = 18:00 UTC.
        let late = date("2026-11-04T18:00:00Z")
        XCTAssertEqual(SessionState.nextLocalMidnight(after: late, in: kolkata), date("2026-11-04T18:30:00Z"))
        // The same instant in UTC is still 4 Nov: midnight is six hours later.
        XCTAssertEqual(SessionState.nextLocalMidnight(after: late, in: TimeZone(identifier: "UTC")!),
                       date("2026-11-05T00:00:00Z"))
    }

    func testDaylightSavingDaysStillEndAtMidnight() {
        let newYork = TimeZone(identifier: "America/New_York")!
        // 1 Nov 2026 is the fall-back day (25 hours). Noon local = 17:00 UTC (EST after 2 am).
        let noon = date("2026-11-01T17:00:00Z")
        XCTAssertEqual(SessionState.nextLocalMidnight(after: noon, in: newYork), date("2026-11-02T05:00:00Z"))
    }

    func testTodayExclusionsExpireAndArePersistedBetweenDrives() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let evening = date("2026-11-04T14:00:00Z")  // 19:30 local
        var state = SessionState()
        state.apply(EntityResolver().resolve(IntentParser.parse("Don't play Anirudh today")).delta,
                    current: nil, now: evening, timeZone: kolkata)
        XCTAssertEqual(state.activeExcludedArtists(at: evening), ["anirudh ravichander"])
        let saved = state.todayExclusions(at: evening)
        XCTAssertEqual(saved["anirudh ravichander"], date("2026-11-04T18:30:00Z"))
        let afterMidnight = date("2026-11-04T19:00:00Z")
        XCTAssertEqual(state.activeExcludedArtists(at: afterMidnight), [])
        var nextDrive = SessionState()
        nextDrive.restoreTodayExclusions(saved, now: date("2026-11-04T16:00:00Z"))
        XCTAssertEqual(nextDrive.activeExcludedArtists(at: date("2026-11-04T16:00:00Z")), ["anirudh ravichander"])
        var tomorrow = SessionState()
        tomorrow.restoreTodayExclusions(saved, now: afterMidnight)
        XCTAssertTrue(tomorrow.excludedArtists.isEmpty)
        // Session exclusions don't expire at midnight.
        state.apply(IntentParser.parse("No more Thaman"), current: nil, now: evening, timeZone: kolkata)
        XCTAssertTrue(state.activeExcludedArtists(at: afterMidnight).contains("thaman"))
    }
}

final class FlowRankingTests: XCTestCase {
    private func candidate(_ id: String, artist: String, energy: Double = 0.5, preview: Bool = false,
                           stream: Bool = true) -> SessionCandidate {
        SessionCandidate(
            track: Track(id: "audius:\(id)", source: .audius, sourceId: id, title: id, artist: artist,
                         streamUrl: stream ? "https://s.test/\(id)" : nil, isPreview: preview,
                         energy: energy, attribution: Attribution(provider: .audius, label: "Audius")),
            score: 0, fit: ["rank": 0.5], source: "intent")
    }

    func testUnplayableTracksNeverRankWhateverTheirScore() {
        var state = SessionState()
        state.vibe[.energy] = VibeTarget(0.9)
        let pool = [candidate("preview", artist: "A", energy: 0.9, preview: true),
                    candidate("nostream", artist: "B", energy: 0.9, stream: false),
                    candidate("ok", artist: "C", energy: 0.1)]
        XCTAssertEqual(SessionRanker.rank(pool, for: state).map(\.sourceId), ["ok"])
        var refused = pool[2]
        refused.track.playbackAuthorized = false  // the server's rights check said no
        XCTAssertTrue(SessionRanker.rank([refused], for: state).isEmpty)
    }

    func testTheSameArtistNeverPlaysTwiceInARowWhenAnotherCan() {
        let pool = [candidate("a1", artist: "A", energy: 0.9), candidate("a2", artist: "A", energy: 0.88),
                    candidate("b1", artist: "B", energy: 0.5), candidate("c1", artist: "C", energy: 0.4)]
        var state = SessionState()
        state.vibe[.energy] = VibeTarget(0.9)
        let order = SessionRanker.rank(pool, for: state).map(\.artist)
        XCTAssertEqual(order.first, "A")
        for (first, second) in zip(order, order.dropFirst()) { XCTAssertNotEqual(first, second) }
        state.record(.complete, for: NowPlayingContext(trackID: "audius:x", artist: "A"))
        XCTAssertNotEqual(SessionRanker.rank(pool, for: state).first?.artist, "A")  // just heard A
    }

    func testRecentArtistsAreSentButOnlySpacingUsesThem() {
        var state = SessionState()
        state.record(.complete, for: NowPlayingContext(trackID: "audius:x", artist: "Mani Sharma"))
        XCTAssertEqual(SessionCandidatesRequest(state: state).recentArtists, ["mani sharma"])
        // Same weights as the server's session-v3: no score penalty, only spacing.
        XCTAssertNil(SessionRanker.weights["variety"])
    }
}

@MainActor
final class DriveFlowTests: XCTestCase {
    func testDriveFeedsCompletionsReplaysAndSkipsAndResetForgetsThem() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        let store = MemoryTodayExclusionStore()
        let drive = DriveSession(api: FakeMusicAPI(), player: player, speaker: RecordingSpeaker(),
                                 todayStore: store)
        drive.start()
        await drive.handle("Play energetic Telugu songs")
        engine.startPlaying()
        let first = SessionState.key(player.currentTrack!.artist)
        engine.finishTrack()
        XCTAssertEqual(drive.state.inferredArtistWeights[first] ?? 0, 0.05, accuracy: 0.001)
        XCTAssertEqual(drive.state.recentArtists.last, first)
        await drive.handle("Don't play this singer today")
        XCTAssertFalse(store.load().isEmpty)  // kept until midnight
        drive.resetSession()
        XCTAssertTrue(drive.state.inferredArtistWeights.isEmpty)
        XCTAssertTrue(drive.state.excludedArtists.isEmpty)
        XCTAssertTrue(store.load().isEmpty)
        XCTAssertEqual(player.queue.contextTitle, "Halo Drive")  // still playing
    }

    func testTodayExclusionsFromAnEarlierDriveApplyUntilMidnight() {
        let store = MemoryTodayExclusionStore(["thaman": Date().addingTimeInterval(3600)])
        let drive = DriveSession(api: FakeMusicAPI(), player: PlayerController(engine: FakeEngine()),
                                 speaker: nil, todayStore: store)
        drive.start()
        XCTAssertEqual(drive.state.activeExcludedArtists(), ["thaman"])
    }

    func testFlowUpdatesDuringADriveKeepTheListenersQueuedSongs() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        let drive = DriveSession(api: FakeMusicAPI(), player: player, speaker: nil)
        drive.start()
        await drive.handle("Play energetic Telugu songs")
        engine.startPlaying()
        player.addToQueue([makeTrack(91), makeTrack(92)])
        for command in ["More energy", "No sad songs", "Newer", "Same vibe but English", "Undo"] {
            await drive.handle(command)
            XCTAssertEqual(player.queue.upNext(.user).map(\.track.id), ["audius:t91", "audius:t92"], command)
            XCTAssertEqual(player.queue.upNext.prefix(2).map(\.track.id), ["audius:t91", "audius:t92"], command)
        }
    }
}
