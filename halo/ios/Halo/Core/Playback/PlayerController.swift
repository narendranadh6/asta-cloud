import Foundation
import Observation

/// The audio engine behind the player: AVPlayer on iOS, a fake in tests.
@MainActor
public protocol AudioEngine: AnyObject {
    /// Progress in seconds, and the duration once known (nil for live streams).
    var onProgress: ((Double, Double?) -> Void)? { get set }
    var onStartedPlaying: (() -> Void)? { get set }
    var onFinished: (() -> Void)? { get set }
    var onFailed: ((String) -> Void)? { get set }

    /// Loads a stream and starts playing it.
    func load(_ url: URL, isLive: Bool)
    func play()
    func pause()
    func seek(to seconds: Double)
    func stop()
}

/// What is playing: a song from the catalog or a live radio station.
public enum NowPlayingItem: Equatable, Sendable {
    case track(Track)
    case station(RadioStation)

    public var title: String {
        switch self {
        case let .track(track): track.title
        case let .station(station): station.name
        }
    }

    public var subtitle: String {
        switch self {
        case let .track(track): track.artist
        case let .station(station):
            ["Live radio", station.countryCode, station.tags.first].compactMap { $0 }
                .joined(separator: " · ")
        }
    }

    public var artworkURL: URL? {
        switch self {
        case let .track(track): track.artworkURL
        case let .station(station): station.favicon.flatMap(Track.webURL)
        }
    }

    public var isLive: Bool {
        if case .station = self { return true }
        return false
    }

    public var track: Track? {
        if case let .track(track) = self { return track }
        return nil
    }
}

/// The one player in the app. Every screen plays through it, so the mini-player, Now Playing
/// and the lock screen always agree. Audio streams straight from each track's source.
@MainActor
@Observable
public final class PlayerController {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)
    }

    public private(set) var queue = PlaybackQueue()
    public private(set) var item: NowPlayingItem?
    public private(set) var state: State = .idle
    public private(set) var position: Double = 0
    public private(set) var duration: Double?
    /// Called when a track starts playing for real (for listening history and feedback).
    public var onTrackStarted: ((Track) -> Void)?

    private let engine: AudioEngine
    /// Consecutive tracks that failed to load; stops runaway skipping through a dead queue.
    private var failuresInARow = 0
    private let maxFailuresInARow = 3

    public init(engine: AudioEngine) {
        self.engine = engine
        engine.onProgress = { [weak self] position, duration in
            self?.position = position
            if let duration, duration.isFinite, duration > 0 { self?.duration = duration }
        }
        engine.onStartedPlaying = { [weak self] in self?.didStartPlaying() }
        engine.onFinished = { [weak self] in self?.trackFinished() }
        engine.onFailed = { [weak self] message in self?.trackFailed(message) }
    }

    public var isPlaying: Bool { state == .playing || state == .loading }
    public var currentTrack: Track? { item?.track }
    public var canSkip: Bool { item?.isLive == false }
    public var hasNext: Bool { !queue.upNext.isEmpty || queue.repeatMode != .off }

    // MARK: Starting playback

    /// Plays `tracks` from `startAt`, replacing the queue. Unplayable tracks are dropped.
    public func play(_ tracks: [Track], startAt: Int = 0) {
        let start = tracks.indices.contains(startAt) ? tracks[startAt] : nil
        let playable = tracks.filter { $0.streamURL != nil }
        guard !playable.isEmpty else {
            state = .failed("These songs can't be played right now.")
            return
        }
        let index = start.flatMap { s in playable.firstIndex { $0.id == s.id } } ?? 0
        queue.replace(with: playable, startAt: index)
        failuresInARow = 0
        loadCurrent()
    }

    public func play(_ track: Track) {
        play([track])
    }

    public func play(station: RadioStation) {
        guard let url = station.streamURL else {
            state = .failed("This station doesn't have a playable stream.")
            return
        }
        queue.clear()
        item = .station(station)
        start(url, isLive: true)
    }

    public func playNext(_ track: Track) {
        guard track.streamURL != nil else { return }
        if item == nil || item?.isLive == true {
            play(track)
        } else {
            queue.playNext(track)
        }
    }

    public func addToQueue(_ tracks: [Track]) {
        let playable = tracks.filter { $0.streamURL != nil }
        guard !playable.isEmpty else { return }
        if item == nil || item?.isLive == true {
            play(playable)
        } else {
            queue.append(playable)
        }
    }

    // MARK: Transport

    public func togglePlayPause() {
        switch state {
        case .playing, .loading:
            engine.pause()
            state = .paused
        case .paused:
            if item?.isLive == true, case let .station(station) = item {
                play(station: station)  // live streams resume from "now"
            } else {
                engine.play()
                state = .playing
            }
        case .failed:
            if item?.isLive == true, case let .station(station) = item {
                play(station: station)
            } else {
                loadCurrent()
            }
        case .idle:
            break
        }
    }

    public func pause() {
        guard state == .playing || state == .loading else { return }
        engine.pause()
        state = .paused
    }

    public func next() {
        guard canSkip, queue.advance(automatic: false) != nil else { return }
        failuresInARow = 0
        loadCurrent()
    }

    /// Restarts the current track if more than 3 seconds in; otherwise goes back one.
    public func previous() {
        guard canSkip else { return }
        if position > 3 || queue.history.isEmpty && queue.repeatMode != .all {
            seek(to: 0)
            return
        }
        if queue.goBack() != nil {
            failuresInARow = 0
            loadCurrent()
        }
    }

    public func seek(to seconds: Double) {
        guard canSkip else { return }
        let target = max(0, min(seconds, duration ?? seconds))
        engine.seek(to: target)
        position = target
    }

    public func jump(to id: UUID) {
        guard queue.jump(to: id) != nil else { return }
        failuresInARow = 0
        loadCurrent()
    }

    public func cycleRepeat() {
        queue.repeatMode = queue.repeatMode.next
    }

    public func toggleShuffle() {
        queue.setShuffle(!queue.isShuffled)
    }

    public func removeFromQueue(_ id: UUID) {
        queue.remove(id: id)
    }

    public func moveUpNext(from source: IndexSet, to destination: Int) {
        queue.moveUpNext(from: source, to: destination)
    }

    public func stop() {
        engine.stop()
        queue.clear()
        item = nil
        state = .idle
        position = 0
        duration = nil
    }

    // MARK: Engine events

    private func loadCurrent() {
        guard let track = queue.current?.track, let url = track.streamURL else {
            stop()
            return
        }
        item = .track(track)
        start(url, isLive: false)
    }

    private func start(_ url: URL, isLive: Bool) {
        position = 0
        duration = isLive ? nil : item?.track?.durationSeconds.map(Double.init)
        state = .loading
        engine.load(url, isLive: isLive)
    }

    private func didStartPlaying() {
        guard state == .loading || state == .playing else { return }
        let wasLoading = state == .loading
        state = .playing
        failuresInARow = 0
        if wasLoading, let track = item?.track { onTrackStarted?(track) }
    }

    private func trackFinished() {
        guard item?.isLive == false else { return }
        if queue.advance(automatic: true) != nil {
            loadCurrent()
        } else {
            engine.pause()
            state = .paused
            position = duration ?? position
        }
    }

    private func trackFailed(_ message: String) {
        failuresInARow += 1
        if item?.isLive == false, failuresInARow < maxFailuresInARow,
           queue.advance(automatic: false) != nil {
            loadCurrent()  // skip a song that won't load
        } else {
            state = .failed(message)
        }
    }
}
