import Foundation
import Observation

/// The audio engine behind the player: AVPlayer on iOS, a fake in tests.
@MainActor
public protocol AudioEngine: AnyObject {
    var onProgress: ((EngineProgress) -> Void)? { get set }
    var onStatus: ((EngineStatus) -> Void)? { get set }
    var onFinished: (() -> Void)? { get set }
    var onFailed: ((EngineFailure) -> Void)? { get set }
    var onRouteChange: ((OutputRoute?) -> Void)? { get set }
    /// Seconds between progress reports (shorter while Now Playing is on screen).
    var progressInterval: Double { get set }

    /// Loads a stream and starts playing it from `startAt` seconds.
    func load(_ url: URL, isLive: Bool, startAt: Double)
    func play()
    func pause()
    /// Calls `completion(true)` once the engine has landed on the new position.
    func seek(to seconds: Double, completion: @escaping @MainActor (Bool) -> Void)
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

    /// The sharpest artwork available, for Now Playing.
    public var largeArtworkURL: URL? {
        switch self {
        case let .track(track): track.largeArtworkURL ?? track.artworkURL
        case .station: artworkURL
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

/// The one player in the app. Every screen plays through it, so the mini player, Now Playing
/// and the lock screen always agree. Audio streams straight from each track's source.
@MainActor
@Observable
public final class PlayerController {
    public private(set) var queue = PlaybackQueue()
    public private(set) var item: NowPlayingItem?
    public private(set) var phase: PlaybackPhase = .idle
    /// Position, length and buffer; observed separately so time ticks stay cheap.
    public let clock = PlaybackClock()
    public private(set) var outputRoute: OutputRoute?
    /// Songs skipped because they couldn't play since the listener last looked (for a notice).
    public private(set) var skippedCount = 0

    /// Called when a track starts playing for real (for listening history and feedback).
    @ObservationIgnored public var onTrackStarted: ((Track) -> Void)?
    /// Fetches a fresh copy of a track (new stream link) before retrying it.
    @ObservationIgnored public var resolveTrack: ((Track) async throws -> Track)?

    @ObservationIgnored private let engine: AudioEngine
    @ObservationIgnored private let sessionStore: PlaybackSessionStoring?
    /// False after a restore: the engine has nothing loaded until the listener presses play.
    @ObservationIgnored private var engineLoaded = false
    @ObservationIgnored private var startReported = false
    /// Tracks to refresh before playing (restored ones, and ones that failed once).
    @ObservationIgnored private var needsFreshLink: Set<UUID> = []
    @ObservationIgnored private var retried: Set<UUID> = []
    @ObservationIgnored private var failuresInARow = 0
    @ObservationIgnored private let maxFailuresInARow = 3
    @ObservationIgnored private var resolveTask: Task<Void, Never>?

    public init(engine: AudioEngine, sessionStore: PlaybackSessionStoring? = nil) {
        self.engine = engine
        self.sessionStore = sessionStore
        engine.onProgress = { [weak self] progress in self?.engineProgressed(progress) }
        engine.onStatus = { [weak self] status in self?.engineStatusChanged(status) }
        engine.onFinished = { [weak self] in self?.trackFinished() }
        engine.onFailed = { [weak self] failure in self?.trackFailed(failure) }
        engine.onRouteChange = { [weak self] route in self?.outputRoute = route }
    }

    public var isPlaying: Bool { phase.wantsToPlay }
    public var currentTrack: Track? { item?.track }
    public var canSkip: Bool { item?.isLive == false }
    public var hasNext: Bool { !queue.upNext.isEmpty || queue.repeatMode != .off }
    public var position: Double { clock.position }
    public var duration: Double? { clock.duration }

    // MARK: Starting playback

    /// Plays `tracks` from `startAt`, replacing the queue. Unplayable tracks are dropped.
    public func play(_ tracks: [Track], startAt: Int = 0, from title: String? = nil) {
        let start = tracks.indices.contains(startAt) ? tracks[startAt] : nil
        let playable = tracks.filter { $0.streamURL != nil }
        guard !playable.isEmpty else {
            transition(.failed(.nothingPlayable))
            return
        }
        let index = start.flatMap { s in playable.firstIndex { $0.id == s.id } } ?? 0
        queue.replace(with: playable, startAt: index, title: title)
        resetFailures()
        loadCurrent()
    }

    public func play(_ track: Track) {
        play([track])
    }

    public func play(station: RadioStation) {
        guard let url = station.streamURL else {
            transition(.failed(.stationDown))
            return
        }
        resolveTask?.cancel()
        queue.clear()
        item = .station(station)
        sessionStore?.save(nil)
        start(url, isLive: true, duration: nil)
    }

    public func playNext(_ track: Track) {
        guard track.streamURL != nil else { return }
        if item == nil || item?.isLive == true {
            play(track)
        } else {
            queue.playNext(track)
            saveSession()
        }
    }

    public func addToQueue(_ tracks: [Track]) {
        let playable = tracks.filter { $0.streamURL != nil }
        guard !playable.isEmpty else { return }
        if item == nil || item?.isLive == true {
            play(playable)
        } else {
            queue.enqueue(playable)
            saveSession()
        }
    }

    // MARK: Transport

    public func togglePlayPause() {
        phase.wantsToPlay ? pause() : resume()
    }

    public func pause() {
        guard phase.wantsToPlay else { return }
        resolveTask?.cancel()
        engine.pause()
        transition(.userPause)
        saveSession()
    }

    public func resume() {
        if case let .station(station) = item {
            play(station: station)  // live streams resume from "now"
            return
        }
        guard queue.current != nil else { return }
        switch phase {
        case .failed, .idle:
            resetFailures()
            loadCurrent(startAt: clock.position)
        case .ended:
            _ = queue.jump(to: queue.items[0].id)
            loadCurrent()
        case .paused where !engineLoaded:
            loadCurrent(startAt: clock.position)
        default:
            engine.play()
            transition(.userPlay)
        }
    }

    public func next() {
        guard canSkip, queue.advance(automatic: false) != nil else { return }
        resetFailures()
        loadCurrent()
    }

    /// Restarts the current track if more than 3 seconds in; otherwise goes back one.
    public func previous() {
        guard canSkip else { return }
        if clock.position > 3 || queue.history.isEmpty && queue.repeatMode != .all {
            seek(to: 0)
            return
        }
        if queue.goBack() != nil {
            resetFailures()
            loadCurrent()
        }
    }

    public func seek(to seconds: Double) {
        guard canSkip, item != nil else { return }
        let target = max(0, min(seconds, clock.duration ?? seconds))
        clock.position = target
        guard engineLoaded else { return }  // restored: applied when playback starts
        transition(.seekStarted(target))
        engine.seek(to: target) { [weak self] _ in
            guard let self, case let .seeking(pending, _) = self.phase, pending == target else { return }
            self.transition(.seekFinished)
            if self.phase == .playing { self.engine.play() }
        }
    }

    public func jump(to id: UUID) {
        guard queue.jump(to: id) != nil else { return }
        resetFailures()
        loadCurrent()
    }

    public func cycleRepeat() {
        queue.repeatMode = queue.repeatMode.next
        saveSession()
    }

    public func toggleShuffle() {
        queue.setShuffle(!queue.isShuffled)
        saveSession()
    }

    public func removeFromQueue(_ id: UUID) {
        queue.remove(id: id)
        saveSession()
    }

    public func move(in origin: PlaybackQueue.Origin, from source: IndexSet, to destination: Int) {
        queue.move(in: origin, from: source, to: destination)
        saveSession()
    }

    public func moveToNext(_ id: UUID) {
        queue.moveToNext(id: id)
        saveSession()
    }

    public func clearUserQueue() {
        queue.clearUserQueue()
        saveSession()
    }

    /// The listener saw the "skipped songs" notice.
    public func acknowledgeSkips() {
        skippedCount = 0
    }

    public func stop() {
        resolveTask?.cancel()
        engine.stop()
        engineLoaded = false
        queue.clear()
        item = nil
        transition(.stop)
        clock.reset(duration: nil)
        sessionStore?.save(nil)
    }

    /// Higher-frequency progress while Now Playing is visible.
    public func setDetailedProgress(_ detailed: Bool) {
        engine.progressInterval = detailed ? 0.25 : 1
    }

    // MARK: Session

    /// Restores the last queue and position, paused. Nothing loads until the listener plays.
    public func restoreSession() {
        guard item == nil, let session = sessionStore?.load(), let current = session.queue.current
        else { return }
        queue = session.queue
        item = .track(current.track)
        clock.reset(duration: current.track.durationSeconds.map(Double.init),
                    position: session.position)
        needsFreshLink.insert(current.id)
        engineLoaded = false
        phase = .paused
    }

    /// Saves the queue and position (called on track changes, pause, and backgrounding).
    public func saveSession() {
        guard case .track = item, !queue.isEmpty else { return }
        sessionStore?.save(PlaybackSession(queue: queue, position: clock.position))
    }

    // MARK: Loading

    private func loadCurrent(startAt: Double = 0) {
        resolveTask?.cancel()
        guard let entry = queue.current else {
            stop()
            return
        }
        item = .track(entry.track)
        if needsFreshLink.contains(entry.id), let resolveTrack {
            transition(.resolve)
            clock.reset(duration: entry.track.durationSeconds.map(Double.init), position: startAt)
            resolveTask = Task { [weak self] in
                let fresh = try? await resolveTrack(entry.track)
                guard let self, !Task.isCancelled, self.queue.current?.id == entry.id else { return }
                self.needsFreshLink.remove(entry.id)
                if let fresh, fresh.streamURL != nil {
                    self.queue.updateTrack(id: entry.id, to: fresh)
                    self.item = .track(fresh)
                }
                self.startCurrent(startAt: startAt)
            }
        } else {
            startCurrent(startAt: startAt)
        }
    }

    private func startCurrent(startAt: Double) {
        guard let track = queue.current?.track, let url = track.streamURL else {
            trackFailed(EngineFailure(.unavailable, detail: "no stream URL"))
            return
        }
        start(url, isLive: false, duration: track.durationSeconds.map(Double.init), startAt: startAt)
        saveSession()
    }

    private func start(_ url: URL, isLive: Bool, duration: Double?, startAt: Double = 0) {
        clock.reset(duration: duration, position: startAt)
        startReported = false
        transition(.load)
        engine.load(url, isLive: isLive, startAt: startAt)
        engineLoaded = true
    }

    // MARK: Engine events

    private func engineProgressed(_ progress: EngineProgress) {
        if case .seeking = phase {} else { clock.position = progress.position }
        if let duration = progress.duration, duration.isFinite, duration > 0 {
            clock.duration = duration
        }
        clock.bufferedUntil = progress.bufferedUntil
    }

    private func engineStatusChanged(_ status: EngineStatus) {
        transition(.engine(status))
        guard status == .playing, phase == .playing, !startReported else { return }
        startReported = true
        failuresInARow = 0
        if let entry = queue.current { retried.remove(entry.id) }
        if let track = item?.track { onTrackStarted?(track) }
    }

    private func trackFinished() {
        guard item?.isLive == false else { return }
        if queue.advance(automatic: true) != nil {
            loadCurrent()
        } else {
            engine.pause()
            transition(.reachedEnd)
            clock.position = clock.duration ?? clock.position
            saveSession()
        }
    }

    private func trackFailed(_ failure: EngineFailure) {
        PlaybackLog.problem("\(item?.title ?? "?") failed: \(failure.kind) \(failure.detail)")
        if item?.isLive == true {
            transition(.failed(failure.kind == .offline ? .offline : .stationDown))
            return
        }
        if failure.kind == .offline {
            transition(.failed(.offline))  // skipping won't help without a connection
            return
        }
        // First failure of a track: fetch a fresh link and try it once more.
        if let entry = queue.current, resolveTrack != nil, !retried.contains(entry.id) {
            retried.insert(entry.id)
            needsFreshLink.insert(entry.id)
            loadCurrent(startAt: clock.position)
            return
        }
        failuresInARow += 1
        if failuresInARow < maxFailuresInARow, queue.advance(automatic: false) != nil {
            skippedCount += 1
            loadCurrent()  // skip a song that won't load
        } else {
            transition(.failed(failure.kind == .unavailable ? .unavailable : .sourceDown))
        }
    }

    private func resetFailures() {
        failuresInARow = 0
        retried.removeAll()
    }

    private func transition(_ event: PlaybackEvent) {
        let next = phase.applying(event)
        if next != phase { phase = next }
    }
}
