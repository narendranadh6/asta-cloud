#if canImport(AVFoundation) && os(iOS)
import AVFoundation

/// AVPlayer-backed engine. Streams audio from the track's source; nothing is downloaded or
/// cached beyond AVPlayer's own playback buffer.
@MainActor
final class StreamingAudioEngine: DuckableAudioEngine {
    var onProgress: ((EngineProgress) -> Void)?
    var onStatus: ((EngineStatus) -> Void)?
    var onFinished: (() -> Void)?
    var onFailed: ((EngineFailure) -> Void)?
    var onRouteChange: ((OutputRoute?) -> Void)? {
        didSet { onRouteChange?(Self.currentRoute()) }
    }
    var progressInterval: Double = 1 {
        didSet {
            guard progressInterval != oldValue else { return }
            installTimeObserver()
        }
    }

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var itemObservers: [NSObjectProtocol] = []
    private var sessionObservers: [NSObjectProtocol] = []
    private var isLive = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        installTimeObserver()
        controlObservation = Self.observeControlStatus(player) { [weak self] status in
            self?.onStatus?(status)
        }
        let center = NotificationCenter.default
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let options = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            MainActor.assumeIsolated {
                // Resume after a call or Siri only when iOS says we should.
                if raw == AVAudioSession.InterruptionType.ended.rawValue,
                   AVAudioSession.InterruptionOptions(rawValue: options).contains(.shouldResume) {
                    self?.player.play()
                }
            }
        })
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onRouteChange?(Self.currentRoute()) }
        })
    }

    func setDucked(_ ducked: Bool) {
        player.volume = ducked ? 0.25 : 1
    }

    func load(_ url: URL, isLive: Bool, startAt: Double) {
        self.isLive = isLive
        activateSession()
        let item = AVPlayerItem(url: url)
        item.preferredForwardBufferDuration = isLive ? 0 : 30
        statusObservation = Self.observeItemStatus(item) { [weak self] error in
            self?.onFailed?(Self.classify(error, isLive: isLive))
        }
        itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        itemObservers = [
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.onFinished?() }
            },
            NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
            ) { [weak self] note in
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                MainActor.assumeIsolated {
                    self?.onFailed?(Self.classify(error, isLive: isLive))
                }
            },
        ]
        player.replaceCurrentItem(with: item)
        if startAt > 1, !isLive {
            player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600))
        }
        player.play()
    }

    func play() {
        activateSession()
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double, completion: @escaping @MainActor (Bool) -> Void) {
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.25, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance) { finished in
            Task { @MainActor in completion(finished) }
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        itemObservers.forEach { NotificationCenter.default.removeObserver($0) }
        itemObservers = []
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Helpers

    private func installTimeObserver() {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: progressInterval, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, let item = self.player.currentItem else { return }
                let buffered = item.loadedTimeRanges.map(\.timeRangeValue)
                    .first { $0.containsTime(time) || $0.start > time }
                    .map { CMTimeGetSeconds(CMTimeRangeGetEnd($0)) }
                self.onProgress?(EngineProgress(
                    position: time.seconds,
                    duration: self.isLive ? nil : item.duration.seconds,
                    bufferedUntil: self.isLive ? nil : buffered))
            }
        }
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // AVFoundation delivers KVO changes on its own queues. These closures are built outside
    // the main actor so Swift doesn't assert they run on main; they hop there explicitly.

    private nonisolated static func observeControlStatus(
        _ player: AVPlayer, _ handler: @escaping @MainActor (EngineStatus) -> Void
    ) -> NSKeyValueObservation {
        player.observe(\.timeControlStatus, options: [.initial, .new]) { player, _ in
            let status: EngineStatus = switch player.timeControlStatus {
            case .playing: .playing
            case .waitingToPlayAtSpecifiedRate: .waiting
            default: .paused
            }
            Task { @MainActor in handler(status) }
        }
    }

    private nonisolated static func observeItemStatus(
        _ item: AVPlayerItem, _ handler: @escaping @MainActor ((any Error)?) -> Void
    ) -> NSKeyValueObservation {
        item.observe(\.status) { item, _ in
            guard item.status == .failed else { return }
            let error = item.error
            Task { @MainActor in handler(error) }
        }
    }

    /// Network trouble is "offline"; anything the source refused is "unavailable".
    private static func classify(_ error: (any Error)?, isLive: Bool) -> EngineFailure {
        let nsError = error as NSError?
        let underlying = nsError?.userInfo[NSUnderlyingErrorKey] as? NSError
        let detail = [nsError, underlying].compactMap { $0 }
            .map { "\($0.domain) \($0.code)" }.joined(separator: " / ")
        let offlineCodes: Set<Int> = [
            NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
            NSURLErrorTimedOut, NSURLErrorCannotConnectToHost, NSURLErrorDataNotAllowed,
            NSURLErrorInternationalRoamingOff,
        ]
        for candidate in [nsError, underlying].compactMap({ $0 })
        where candidate.domain == NSURLErrorDomain && offlineCodes.contains(candidate.code) {
            return EngineFailure(.offline, detail: detail)
        }
        return EngineFailure(isLive ? .unknown : .unavailable, detail: detail)
    }

    private static func currentRoute() -> OutputRoute? {
        guard let output = AVAudioSession.sharedInstance().currentRoute.outputs.first else {
            return nil
        }
        let kind: OutputRoute.Kind = switch output.portType {
        case .builtInSpeaker, .builtInReceiver: .speaker
        case .headphones, .usbAudio, .lineOut: .headphones
        case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP: .bluetooth
        case .airPlay: .airPlay
        case .carAudio: .car
        default: .other
        }
        return OutputRoute(name: output.portName, kind: kind)
    }
}
#endif
