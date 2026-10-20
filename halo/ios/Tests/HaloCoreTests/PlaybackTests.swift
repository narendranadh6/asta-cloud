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

    func testPlayNextAppendRemoveAndMove() {
        var queue = PlaybackQueue()
        queue.replace(with: [makeTrack(1), makeTrack(2), makeTrack(3)])
        queue.playNext(makeTrack(9))
        XCTAssertEqual(queue.upNext.map(\.track.id), ["audius:t9", "audius:t2", "audius:t3"])
        queue.append([makeTrack(1)])  // the same track can be queued twice
        XCTAssertEqual(queue.items.filter { $0.track.id == "audius:t1" }.count, 2)
        queue.remove(id: queue.current!.id)  // the current item can't be removed
        XCTAssertEqual(queue.current?.track.id, "audius:t1")
        queue.remove(id: queue.upNext[0].id)
        XCTAssertEqual(queue.upNext.map(\.track.id), ["audius:t2", "audius:t3", "audius:t1"])
        queue.moveUpNext(from: IndexSet(integer: 2), to: 0)
        XCTAssertEqual(queue.upNext.map(\.track.id), ["audius:t1", "audius:t2", "audius:t3"])
        XCTAssertEqual(queue.current?.track.id, "audius:t1")
    }

    func testShuffleKeepsCurrentAndRestoresOrder() {
        var rng = SeededRNG(state: 7)
        var queue = PlaybackQueue()
        let tracks = (1...8).map { makeTrack($0) }
        queue.replace(with: tracks, startAt: 2, using: &rng)
        queue.setShuffle(true, using: &rng)
        XCTAssertEqual(queue.current?.track.id, "audius:t3")
        XCTAssertEqual(Set(queue.upNext.map(\.track.id)), Set(tracks[3...].map(\.id)))
        XCTAssertNotEqual(queue.upNext.map(\.track.id), tracks[3...].map(\.id))
        queue.advance(automatic: false)
        let playing = queue.current?.track.id
        queue.setShuffle(false, using: &rng)
        XCTAssertEqual(queue.items.map(\.track.id), tracks.map(\.id))
        XCTAssertEqual(queue.current?.track.id, playing)
    }
}

@MainActor
final class FakeEngine: AudioEngine {
    var onProgress: ((Double, Double?) -> Void)?
    var onStartedPlaying: (() -> Void)?
    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?
    private(set) var loaded: [URL] = []
    private(set) var calls: [String] = []

    func load(_ url: URL, isLive: Bool) {
        loaded.append(url)
        calls.append(isLive ? "load-live" : "load")
    }
    func play() { calls.append("play") }
    func pause() { calls.append("pause") }
    func seek(to seconds: Double) { calls.append("seek \(Int(seconds))") }
    func stop() { calls.append("stop") }
}

@MainActor
final class PlayerControllerTests: XCTestCase {
    func testPlaysQueueAndAdvancesWhenATrackEnds() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        var started: [String] = []
        player.onTrackStarted = { started.append($0.id) }
        player.play([makeTrack(1), makeTrack(2, playable: false), makeTrack(3)], startAt: 0)
        XCTAssertEqual(player.state, .loading)
        XCTAssertEqual(player.queue.items.count, 2)  // unplayable track dropped
        engine.onStartedPlaying?()
        XCTAssertEqual(player.state, .playing)
        engine.onProgress?(42, 200)
        XCTAssertEqual(player.position, 42)
        XCTAssertEqual(player.duration, 200)
        engine.onFinished?()
        XCTAssertEqual(player.currentTrack?.id, "audius:t3")
        engine.onStartedPlaying?()
        engine.onStartedPlaying?()  // repeated "playing" signals count once
        XCTAssertEqual(started, ["audius:t1", "audius:t3"])
        engine.onFinished?()  // end of queue
        XCTAssertEqual(player.state, .paused)
        XCTAssertEqual(engine.loaded.map(\.lastPathComponent), ["t1.mp3", "t3.mp3"])
    }

    func testTransportPreviousRestartsThenGoesBack() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        player.play([makeTrack(1), makeTrack(2)], startAt: 1)
        engine.onStartedPlaying?()
        engine.onProgress?(30, 200)
        player.previous()
        XCTAssertEqual(engine.calls.last, "seek 0")
        XCTAssertEqual(player.currentTrack?.id, "audius:t2")
        player.previous()  // now within the first 3 seconds
        XCTAssertEqual(player.currentTrack?.id, "audius:t1")
        player.togglePlayPause()
        XCTAssertEqual(player.state, .paused)
        player.togglePlayPause()
        XCTAssertEqual(player.state, .playing)
        player.next()
        XCTAssertEqual(player.currentTrack?.id, "audius:t2")
        player.stop()
        XCTAssertNil(player.item)
        XCTAssertEqual(player.state, .idle)
    }

    func testFailedTracksAreSkippedButNotForever() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        player.play((1...6).map { makeTrack($0) })
        engine.onFailed?("nope")
        XCTAssertEqual(player.currentTrack?.id, "audius:t2")
        engine.onFailed?("nope")
        engine.onFailed?("nope")  // third failure in a row stops skipping
        XCTAssertEqual(player.state, .failed("nope"))
        XCTAssertEqual(player.currentTrack?.id, "audius:t3")
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
        player.addToQueue([makeTrack(1)])  // a song replaces the live stream
        XCTAssertEqual(player.currentTrack?.id, "audius:t1")
    }

    func testPlayNextAndAddToQueue() async {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        player.playNext(makeTrack(1))  // nothing playing: starts it
        XCTAssertEqual(player.currentTrack?.id, "audius:t1")
        player.addToQueue([makeTrack(2), makeTrack(3)])
        player.playNext(makeTrack(4))
        XCTAssertEqual(player.queue.upNext.map(\.track.id), ["audius:t4", "audius:t2", "audius:t3"])
        player.cycleRepeat()
        XCTAssertEqual(player.queue.repeatMode, .all)
    }
}
