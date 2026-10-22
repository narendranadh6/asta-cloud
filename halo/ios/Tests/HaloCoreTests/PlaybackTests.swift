import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

func makeTrack(_ n: Int, playable: Bool = true, preview: Bool = false) -> Track {
    Track(
        id: "audius:t\(n)", source: .audius, sourceId: "t\(n)", title: "Song \(n)",
        artist: "Artist \(n)", durationSeconds: 200,
        streamUrl: playable ? "https://stream.test/t\(n).mp3" : nil, isPreview: preview,
        attribution: Attribution(provider: .audius, label: "Audius"))
}

/// Deterministic RNG so shuffle tests are repeatable.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}

final class PlaybackQueueTests: XCTestCase {
    func testAdvanceAndRepeatModes() {
        var queue = PlaybackQueue()
        queue.replace(with: (1...3).map { makeTrack($0) }, startAt: 1)
        XCTAssertEqual(queue.current?.track.id, "audius:t2")
        XCTAssertEqual(queue.upNext.map(\.track.id), ["audius:t3"])
        XCTAssertEqual(queue.advance(automatic: true)?.track.id, "audius:t3")
        XCTAssertNil(queue.advance(automatic: true))  // end of queue, repeat off
        queue.repeatMode = .all
        XCTAssertEqual(queue.advance(automatic: true)?.track.id, "audius:t1")
        queue.repeatMode = .one
        XCTAssertEqual(queue.advance(automatic: true)?.track.id, "audius:t1")  // replays
        XCTAssertEqual(queue.advance(automatic: false)?.track.id, "audius:t2")  // skip still moves
        XCTAssertEqual(queue.goBack()?.track.id, "audius:t1")
        queue.repeatMode = .off
        XCTAssertNil(queue.goBack())
        XCTAssertEqual(PlaybackQueue.RepeatMode.off.next, .all)
        XCTAssertEqual(PlaybackQueue.RepeatMode.one.next, .off)
    }

    func testListenerAdditionsStayAheadOfContextAndFlow() {
        var queue = PlaybackQueue()
        queue.replace(with: [makeTrack(1), makeTrack(2), makeTrack(3)], title: "Focus Mix")
        XCTAssertEqual(queue.contextTitle, "Focus Mix")
        queue.appendFlow([makeTrack(20)])
        queue.enqueue([makeTrack(7)])  // Add to Queue
        queue.enqueue([makeTrack(8)])
        queue.playNext(makeTrack(9))  // Play Next goes first
        XCTAssertEqual(queue.upNext.map(\.track.id),
                       ["audius:t9", "audius:t7", "audius:t8", "audius:t2", "audius:t3", "audius:t20"])
        XCTAssertEqual(queue.upNext(.user).map(\.track.id), ["audius:t9", "audius:t7", "audius:t8"])
        XCTAssertEqual(queue.upNext(.flow).map(\.track.id), ["audius:t20"])
        queue.appendFlow([makeTrack(21)])  // Flow never jumps ahead
        XCTAssertEqual(queue.upNext.last?.track.id, "audius:t21")
        queue.clearUserQueue()
        XCTAssertEqual(queue.upNext.map(\.track.id), ["audius:t2", "audius:t3", "audius:t20", "audius:t21"])
        queue.removeUpcomingFlow()
        XCTAssertEqual(queue.upNext.map(\.track.id), ["audius:t2", "audius:t3"])
    }

    func testMoveWithinBandRemoveAndPromote() {
        var queue = PlaybackQueue()
        queue.replace(with: [makeTrack(1), makeTrack(2), makeTrack(3), makeTrack(4)])
        queue.enqueue([makeTrack(8), makeTrack(9)])
        queue.move(in: .context, from: IndexSet(integer: 2), to: 0)  // t4 to the front of the context
        XCTAssertEqual(queue.upNext.map(\.track.id),
                       ["audius:t8", "audius:t9", "audius:t4", "audius:t2", "audius:t3"])
        queue.move(in: .user, from: IndexSet(integer: 1), to: 0)
        XCTAssertEqual(queue.upNext(.user).map(\.track.id), ["audius:t9", "audius:t8"])
        let t3 = queue.upNext.first { $0.track.id == "audius:t3" }!
        queue.moveToNext(id: t3.id)  // swipe "Play Next" on a context row
        XCTAssertEqual(queue.upNext.first?.track.id, "audius:t3")
        XCTAssertEqual(queue.upNext.first?.origin, .user)
        queue.remove(id: queue.current!.id)  // the current item can't be removed
        XCTAssertEqual(queue.current?.track.id, "audius:t1")
        queue.remove(id: t3.id)
        XCTAssertFalse(queue.items.contains { $0.id == t3.id })
    }

    func testShuffleTouchesOnlyTheContextAndRestoresItsOrder() {
        var rng = SeededRNG(state: 7)
        var queue = PlaybackQueue()
        let tracks = (1...8).map { makeTrack($0) }
        queue.replace(with: tracks, startAt: 2, using: &rng)
        queue.enqueue([makeTrack(50)])
        queue.setShuffle(true, using: &rng)
        XCTAssertEqual(queue.current?.track.id, "audius:t3")
        XCTAssertEqual(queue.upNext.first?.track.id, "audius:t50")  // listener's song stays next
        let shuffled = queue.upNext(.context).map(\.track.id)
        XCTAssertEqual(Set(shuffled), Set(tracks[3...].map(\.id)))
        XCTAssertNotEqual(shuffled, tracks[3...].map(\.id))
        queue.advance(automatic: false)
        queue.advance(automatic: false)
        let playing = queue.current?.track.id
        queue.setShuffle(false, using: &rng)
        XCTAssertEqual(queue.current?.track.id, playing)
        let remaining = queue.upNext(.context).map(\.track.id)
        XCTAssertEqual(remaining, remaining.sorted { $0.count == $1.count ? $0 < $1 : $0.count < $1.count })
    }

    func testQueueRoundTripsThroughJSON() throws {
        var queue = PlaybackQueue()
        queue.replace(with: [makeTrack(1), makeTrack(2)], startAt: 1, title: "Road Trip")
        queue.enqueue([makeTrack(3)])
        queue.repeatMode = .all
        let data = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode(PlaybackQueue.self, from: data)
        XCTAssertEqual(decoded, queue)
    }
}

final class PlaybackPhaseTests: XCTestCase {
    func testNormalLifecycle() {
        var phase = PlaybackPhase.idle
        phase = phase.applying(.load)
        XCTAssertEqual(phase, .loading)
        XCTAssertTrue(phase.wantsToPlay)
        XCTAssertTrue(phase.isWaiting)
        phase = phase.applying(.engine(.waiting))
        XCTAssertEqual(phase, .loading)  // still opening
        phase = phase.applying(.engine(.playing))
        XCTAssertEqual(phase, .playing)
        phase = phase.applying(.engine(.waiting))
        XCTAssertEqual(phase, .buffering)  // stalled mid-song
        phase = phase.applying(.engine(.playing))
        XCTAssertEqual(phase, .playing)
        phase = phase.applying(.userPause)
        XCTAssertEqual(phase, .paused)
        XCTAssertFalse(phase.wantsToPlay)
        phase = phase.applying(.userPlay)
        XCTAssertEqual(phase, .playing)
        phase = phase.applying(.reachedEnd)
        XCTAssertEqual(phase, .ended)
        XCTAssertEqual(phase.applying(.stop), .idle)
    }

    func testSeekingRemembersWhetherToResume() {
        let fromPlaying = PlaybackPhase.playing.applying(.seekStarted(30))
        XCTAssertEqual(fromPlaying, .seeking(target: 30, resume: true))
        XCTAssertEqual(fromPlaying.applying(.engine(.waiting)), fromPlaying)  // ignored mid-seek
        XCTAssertEqual(fromPlaying.applying(.seekFinished), .playing)
        let fromPaused = PlaybackPhase.paused.applying(.seekStarted(10))
        XCTAssertEqual(fromPaused.applying(.seekFinished), .paused)
        XCTAssertEqual(fromPaused.applying(.userPlay).applying(.seekFinished), .playing)
        XCTAssertEqual(fromPaused.applying(.seekStarted(20)), .seeking(target: 20, resume: false))
    }

    func testSystemPausesAndFailures() {
        XCTAssertEqual(PlaybackPhase.playing.applying(.engine(.paused)), .paused)  // headphones out
        XCTAssertEqual(PlaybackPhase.paused.applying(.engine(.playing)), .playing)  // call ended
        XCTAssertEqual(PlaybackPhase.loading.applying(.engine(.paused)), .loading)  // stale event
        let failed = PlaybackPhase.playing.applying(.failed(.offline))
        XCTAssertEqual(failed.issue, .offline)
        XCTAssertFalse(failed.wantsToPlay)
        XCTAssertEqual(failed.applying(.engine(.playing)), failed)
        XCTAssertEqual(failed.applying(.load), .loading)
    }

    func testIssuesHavePlainWordsAndActions() {
        for issue in [PlaybackIssue.offline, .unavailable, .sourceDown, .stationDown, .nothingPlayable] {
            XCTAssertFalse(issue.title.isEmpty)
            XCTAssertFalse(issue.message.lowercased().contains("error"))
        }
        XCTAssertEqual(PlaybackIssue.unavailable.actions, [.playSimilar, .skip])
    }
}

@MainActor
final class FakeEngine: DuckableAudioEngine {
    private(set) var ducked = false
    func setDucked(_ ducked: Bool) { self.ducked = ducked }

    var onProgress: ((EngineProgress) -> Void)?
    var onStatus: ((EngineStatus) -> Void)?
    var onFinished: (() -> Void)?
    var onFailed: ((EngineFailure) -> Void)?
    var onRouteChange: ((OutputRoute?) -> Void)?
    var progressInterval: Double = 1
    private(set) var loaded: [URL] = []
    private(set) var calls: [String] = []
    private var pendingSeek: (@MainActor (Bool) -> Void)?

    func load(_ url: URL, isLive: Bool, startAt: Double) {
        loaded.append(url)
        calls.append(isLive ? "load-live" : (startAt > 0 ? "load@\(Int(startAt))" : "load"))
    }
    func play() { calls.append("play") }
    func pause() { calls.append("pause") }
    func seek(to seconds: Double, completion: @escaping @MainActor (Bool) -> Void) {
        calls.append("seek \(Int(seconds))")
        pendingSeek = completion
    }
    func finishSeek() {
        pendingSeek?(true)
        pendingSeek = nil
    }
    func stop() { calls.append("stop") }

    /// The engine opened the stream and sound started.
    func startPlaying() { onStatus?(.playing) }
}

final class MemorySessionStore: PlaybackSessionStoring, @unchecked Sendable {
    var session: PlaybackSession?
    func load() -> PlaybackSession? { session }
    func save(_ session: PlaybackSession?) { self.session = session }
}

@MainActor
final class PlayerControllerTests: XCTestCase {
    func testPlaysQueueAndAdvancesWhenATrackEnds() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        var started: [String] = []
        player.onTrackStarted = { started.append($0.id) }
        player.play([makeTrack(1), makeTrack(2, playable: false), makeTrack(3)], startAt: 0)
        XCTAssertEqual(player.phase, .loading)
        XCTAssertTrue(player.isPlaying)
        XCTAssertEqual(player.queue.items.count, 2)  // unplayable track dropped
        engine.onStatus?(.waiting)
        XCTAssertEqual(player.phase, .loading)
        engine.startPlaying()
        XCTAssertEqual(player.phase, .playing)
        engine.onProgress?(EngineProgress(position: 42, duration: 200, bufferedUntil: 90))
        XCTAssertEqual(player.clock.position, 42)
        XCTAssertEqual(player.clock.duration, 200)
        XCTAssertEqual(player.clock.bufferedFraction, 0.45)
        engine.onStatus?(.waiting)
        XCTAssertEqual(player.phase, .buffering)
        engine.startPlaying()
        engine.onFinished?()
        XCTAssertEqual(player.currentTrack?.id, "audius:t3")
        engine.startPlaying()
        engine.startPlaying()  // repeated "playing" signals count once
        XCTAssertEqual(started, ["audius:t1", "audius:t3"])
        engine.onFinished?()  // end of queue
        XCTAssertEqual(player.phase, .ended)
        player.resume()  // play again from the top
        XCTAssertEqual(player.currentTrack?.id, "audius:t1")
        XCTAssertEqual(engine.loaded.map(\.lastPathComponent), ["t1.mp3", "t3.mp3", "t1.mp3"])
    }

    func testSeekHoldsThePositionUntilTheEngineLands() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        player.play([makeTrack(1)])
        engine.startPlaying()
        engine.onProgress?(EngineProgress(position: 10, duration: 200))
        player.seek(to: 120)
        XCTAssertEqual(player.phase, .seeking(target: 120, resume: true))
        engine.onProgress?(EngineProgress(position: 11, duration: 200))  // late tick from before
        XCTAssertEqual(player.clock.position, 120)
        engine.finishSeek()
        XCTAssertEqual(player.phase, .playing)
        engine.onProgress?(EngineProgress(position: 121, duration: 200))
        XCTAssertEqual(player.clock.position, 121)
    }

    func testTransportPreviousRestartsThenGoesBack() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        player.play([makeTrack(1), makeTrack(2)], startAt: 1)
        engine.startPlaying()
        engine.onProgress?(EngineProgress(position: 30, duration: 200))
        player.previous()
        XCTAssertEqual(engine.calls.last, "seek 0")
        engine.finishSeek()
        XCTAssertEqual(player.currentTrack?.id, "audius:t2")
        player.previous()  // now within the first 3 seconds
        XCTAssertEqual(player.currentTrack?.id, "audius:t1")
        engine.startPlaying()
        player.togglePlayPause()
        XCTAssertEqual(player.phase, .paused)
        player.togglePlayPause()
        XCTAssertEqual(player.phase, .playing)
        player.next()
        XCTAssertEqual(player.currentTrack?.id, "audius:t2")
        player.stop()
        XCTAssertNil(player.item)
        XCTAssertEqual(player.phase, .idle)
    }

    func testFailedTracksAreSkippedButNotForever() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        player.play((1...6).map { makeTrack($0) })
        engine.onFailed?(EngineFailure(.unavailable))
        XCTAssertEqual(player.currentTrack?.id, "audius:t2")
        XCTAssertEqual(player.skippedCount, 1)
        engine.onFailed?(EngineFailure(.unavailable))
        engine.onFailed?(EngineFailure(.unavailable))  // third failure in a row stops skipping
        XCTAssertEqual(player.phase, .failed(.unavailable))
        XCTAssertEqual(player.currentTrack?.id, "audius:t3")
        player.acknowledgeSkips()
        XCTAssertEqual(player.skippedCount, 0)
    }

    func testOfflineStopsInsteadOfSkipping() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        player.play([makeTrack(1), makeTrack(2)])
        engine.onFailed?(EngineFailure(.offline, detail: "NSURLErrorDomain -1009"))
        XCTAssertEqual(player.phase, .failed(.offline))
        XCTAssertEqual(player.currentTrack?.id, "audius:t1")
        player.resume()  // "Try again"
        XCTAssertEqual(player.phase, .loading)
        XCTAssertEqual(engine.loaded.count, 2)
    }

    func testAFailingTrackGetsAFreshLinkOnceBeforeSkipping() async throws {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        var resolved: [String] = []
        player.resolveTrack = { track in
            resolved.append(track.id)
            var fresh = track
            fresh.streamUrl = "https://stream.test/fresh-\(track.sourceId).mp3"
            return fresh
        }
        player.play([makeTrack(1), makeTrack(2)])
        engine.onFailed?(EngineFailure(.unavailable))
        XCTAssertEqual(player.phase, .resolving)
        try await waitUntil { engine.loaded.count == 2 }
        XCTAssertEqual(resolved, ["audius:t1"])
        XCTAssertEqual(engine.loaded.last?.lastPathComponent, "fresh-t1.mp3")
        engine.onFailed?(EngineFailure(.unavailable))  // fails again: now skip
        XCTAssertEqual(player.currentTrack?.id, "audius:t2")
    }

    func testRestoresTheLastSessionPausedAndLoadsOnPlay() async throws {
        let store = MemorySessionStore()
        let first = PlayerController(engine: FakeEngine(), sessionStore: store)
        first.play([makeTrack(1), makeTrack(2)], from: "Focus Mix")
        first.addToQueue([makeTrack(5)])
        first.next()
        let engine = FakeEngine()
        engine.onProgress?(EngineProgress(position: 0))
        first.saveSession()
        store.session?.position = 95

        let player = PlayerController(engine: engine, sessionStore: store)
        player.resolveTrack = { $0 }
        player.restoreSession()
        XCTAssertEqual(player.currentTrack?.id, "audius:t5")
        XCTAssertEqual(player.queue.contextTitle, "Focus Mix")
        XCTAssertEqual(player.phase, .paused)
        XCTAssertEqual(player.clock.position, 95)
        XCTAssertTrue(engine.loaded.isEmpty)  // nothing streams until the listener presses play
        player.togglePlayPause()
        XCTAssertEqual(player.phase, .resolving)
        try await waitUntil { !engine.loaded.isEmpty }
        XCTAssertEqual(engine.calls.last, "load@95")
        player.stop()
        XCTAssertNil(store.session)
    }

    func testRadioIsLiveAndCantBeSkipped() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        let station = RadioStation(
            id: "s1", name: "Test FM", streamUrl: "https://radio.test/live", homepage: nil,
            favicon: nil, tags: ["pop"], countryCode: "IN", language: nil, codec: "MP3",
            bitrate: 128, popularity: 1)
        player.play(station: station)
        XCTAssertEqual(engine.calls.last, "load-live")
        XCTAssertTrue(player.item?.isLive == true)
        XCTAssertFalse(player.canSkip)
        player.seek(to: 10)
        XCTAssertFalse(engine.calls.contains("seek 10"))
        engine.onFailed?(EngineFailure(.unknown))
        XCTAssertEqual(player.phase, .failed(.stationDown))
        player.addToQueue([makeTrack(1)])  // a song replaces the live stream
        XCTAssertEqual(player.currentTrack?.id, "audius:t1")
    }

    func testPlayNextAddToQueueAndRoute() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        player.playNext(makeTrack(1))  // nothing playing: starts it
        XCTAssertEqual(player.currentTrack?.id, "audius:t1")
        player.addToQueue([makeTrack(2), makeTrack(3)])
        player.playNext(makeTrack(4))
        XCTAssertEqual(player.queue.upNext.map(\.track.id), ["audius:t4", "audius:t2", "audius:t3"])
        player.cycleRepeat()
        XCTAssertEqual(player.queue.repeatMode, .all)
        engine.onRouteChange?(OutputRoute(name: "AirPods", kind: .bluetooth))
        XCTAssertEqual(player.outputRoute?.name, "AirPods")
        XCTAssertTrue(player.outputRoute?.isExternal == true)
        player.setDetailedProgress(true)
        XCTAssertEqual(engine.progressInterval, 0.25)
    }

    func testHaloFlowRefillsLowQueuesAndContinuesAtTheEnd() async throws {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        var seeds: [String] = []
        player.flowProvider = { seed in
            seeds.append(seed.id)
            let n = 100 + seeds.count * 10
            return [FlowSuggestion(track: makeTrack(n), reason: "Fans also play"),
                    FlowSuggestion(track: makeTrack(1), reason: nil),  // already queued: dropped
                    FlowSuggestion(track: makeTrack(n + 1, playable: false), reason: nil)]
        }
        player.play([makeTrack(1), makeTrack(2)])  // one song left after this: refill
        try await waitUntil { !player.queue.upNext(.flow).isEmpty }
        XCTAssertEqual(seeds, ["audius:t1"])
        XCTAssertEqual(player.queue.upNext.map(\.track.id), ["audius:t2", "audius:t110"])
        XCTAssertEqual(player.queue.upNext(.flow).first?.reason, "Fans also play")
        player.addToQueue([makeTrack(7)])  // the listener's song still goes before Flow
        XCTAssertEqual(player.queue.upNext.map(\.track.id), ["audius:t7", "audius:t2", "audius:t110"])

        player.autoplayEnabled = false
        XCTAssertTrue(player.queue.upNext(.flow).isEmpty)
        player.next()
        player.next()  // t2, the last song
        engine.startPlaying()
        engine.onFinished?()
        XCTAssertEqual(player.phase, .ended)  // autoplay off: the music stops

        player.autoplayEnabled = true
        player.play([makeTrack(3)], from: "Single")
        try await waitUntil { !player.isLoadingFlow }
        let flow = player.queue.upNext(.flow).map(\.track.id)
        XCTAssertFalse(flow.isEmpty)
        for _ in flow { engine.onFinished?() }  // play through Flow
        engine.onFinished?()  // out of songs again: Flow fetches more and keeps going
        XCTAssertEqual(player.phase, .resolving)
        try await waitUntil { player.phase == .loading }
        XCTAssertTrue(player.currentTrack.map { $0.id.hasPrefix("audius:t1") } == true)
    }

    func testFlowResultsForAnOldSongAreDropped() async throws {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        var release: CheckedContinuation<Void, Never>?
        player.flowProvider = { _ in
            await withCheckedContinuation { release = $0 }
            return [FlowSuggestion(track: makeTrack(50), reason: nil)]
        }
        player.play([makeTrack(1)])
        try await waitUntil { release != nil }
        player.play([makeTrack(2), makeTrack(3), makeTrack(4)])  // something new started
        release?.resume()
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(player.queue.items.contains { $0.track.id == "audius:t50" })
    }

    func testFlowReasonsAreShortAndPlain() {
        func rec(_ source: String?, explore: Bool = false) -> RecommendedTrack {
            RecommendedTrack(track: makeTrack(1), score: 1, reasons: ["long server text"],
                             matchedQuery: "q", source: source, explore: explore)
        }
        XCTAssertEqual(FlowSuggestion(rec("co_listen")).reason, "Fans also play")
        XCTAssertEqual(FlowSuggestion(rec("similar_artist")).reason, "Similar artist")
        XCTAssertEqual(FlowSuggestion(rec("listenbrainz")).reason, "Popular with listeners")
        XCTAssertEqual(FlowSuggestion(rec("search", explore: true)).reason, "Something new")
        XCTAssertEqual(FlowSuggestion(rec(nil)).reason, "Similar sound")
    }

    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        for _ in 0..<100 where !condition() {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition())
    }
}

final class PaletteTests: XCTestCase {
    private func image(_ colors: [(UInt8, UInt8, UInt8, Int)]) -> [UInt8] {
        colors.flatMap { r, g, b, count in Array(repeating: [r, g, b, 255], count: count).flatMap { $0 } }
    }

    func testPicksTheDominantHueAndKeepsTextReadable() throws {
        // Mostly bright orange with some blue: a light cover that would wash out white text.
        let pixels = image([(250, 150, 60, 400), (40, 90, 220, 176)])
        let palette = try XCTUnwrap(PaletteExtractor.palette(rgba: pixels, width: 24, height: 24))
        let hue = palette.base.hsl.hue * 360
        XCTAssertTrue((15...45).contains(hue), "base hue \(hue) should stay orange")
        XCTAssertGreaterThanOrEqual(palette.base.contrast(with: .white), PaletteExtractor.textContrast)
        XCTAssertGreaterThanOrEqual(palette.accent.contrast(with: palette.base), PaletteExtractor.accentContrast)
        XCTAssertGreaterThan(palette.glow.luminance, palette.base.luminance)
    }

    func testWhiteAndGreyCoversStillWork() throws {
        let white = image([(255, 255, 255, 576)])
        let palette = try XCTUnwrap(PaletteExtractor.palette(rgba: white, width: 24, height: 24))
        XCTAssertGreaterThanOrEqual(palette.base.contrast(with: .white), PaletteExtractor.textContrast)
        let transparent = [UInt8](repeating: 0, count: 24 * 24 * 4)
        XCTAssertNil(PaletteExtractor.palette(rgba: transparent, width: 24, height: 24))
        XCTAssertNil(PaletteExtractor.palette(rgba: [1, 2, 3], width: 24, height: 24))
    }

    func testFallbackIsStablePerArtistAndReadable() {
        let a = ArtworkPalette.fallback(seed: "Radio Juicy")
        XCTAssertEqual(a, ArtworkPalette.fallback(seed: "Radio Juicy"))
        XCTAssertNotEqual(a, ArtworkPalette.fallback(seed: "Stony100"))
        XCTAssertGreaterThanOrEqual(a.base.contrast(with: .white), PaletteExtractor.textContrast)
        XCTAssertGreaterThanOrEqual(ArtworkPalette.halo.base.contrast(with: .white), PaletteExtractor.textContrast)
    }
}
