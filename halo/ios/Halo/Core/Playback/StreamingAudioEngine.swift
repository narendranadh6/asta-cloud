#if canImport(AVFoundation) && os(iOS)
import AVFoundation

/// AVPlayer-backed engine. Streams audio from the track's source; nothing is downloaded or
/// cached beyond AVPlayer's own playback buffer.
@MainActor
final class StreamingAudioEngine: AudioEngine {
    var onProgress: ((Double, Double?) -> Void)?
    var onStartedPlaying: (() -> Void)?
    var onFinished: (() -> Void)?
    var onFailed: ((String) -> Void)?

    private let player = AVPlayer()
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var controlObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var isLive = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                let duration = self.player.currentItem?.duration.seconds
                self.onProgress?(time.seconds, self.isLive ? nil : duration)
            }
        }
        controlObservation = Self.observePlaying(player) { [weak self] in
            self?.onStartedPlaying?()
        }
        interruptionObserver = NotificationCenter.default.addObserver(
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
        }
    }

    func load(_ url: URL, isLive: Bool) {
        self.isLive = isLive
        activateSession()
        let item = AVPlayerItem(url: url)
        statusObservation = Self.observeFailure(item) { [weak self] in
            self?.onFailed?(Self.message(isLive: isLive))
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFinished?() }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onFailed?(Self.message(isLive: isLive)) }
        }
        player.replaceCurrentItem(with: item)
        player.play()
    }

    func play() {
        activateSession()
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to seconds: Double) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        statusObservation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func activateSession() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // AVFoundation delivers KVO changes on its own queues. These closures are built outside
    // the main actor so Swift doesn't assert they run on main; they hop there explicitly.

    private nonisolated static func observePlaying(
        _ player: AVPlayer, _ handler: @escaping @MainActor () -> Void
    ) -> NSKeyValueObservation {
        player.observe(\.timeControlStatus) { player, _ in
            guard player.timeControlStatus == .playing else { return }
            Task { @MainActor in handler() }
        }
    }

    private nonisolated static func observeFailure(
        _ item: AVPlayerItem, _ handler: @escaping @MainActor () -> Void
    ) -> NSKeyValueObservation {
        item.observe(\.status) { item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor in handler() }
        }
    }

    private static func message(isLive: Bool) -> String {
        isLive ? "The station isn't responding. Try another one."
            : "This song couldn't be played. Check your connection or try another song."
    }
}
#endif
