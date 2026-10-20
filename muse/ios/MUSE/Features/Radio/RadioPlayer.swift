import AVFoundation
import MediaPlayer
import Observation

/// Plays live internet radio streams natively. Unlike YouTube (handed off to Brave),
/// radio stations publish open streams, so MUSE can play, stop and show them on the
/// lock screen. State reflects the real AVPlayer, never an estimate.
@MainActor
@Observable
final class RadioPlayer {
    enum Status: Equatable {
        case idle
        case connecting
        case playing
        case failed(String)
    }

    private(set) var station: RadioStation?
    private(set) var status: Status = .idle
    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?

    var isActive: Bool { station != nil && status != .idle }

    func toggle(_ station: RadioStation) {
        if self.station?.id == station.id, status == .playing || status == .connecting {
            stop()
        } else {
            play(station)
        }
    }

    func play(_ station: RadioStation) {
        guard let url = station.streamURL else {
            status = .failed("This station doesn't have a playable stream.")
            return
        }
        stop()
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            status = .failed("Audio is unavailable right now.")
            return
        }
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player
        self.station = station
        status = .connecting
        statusObservation = item.observe(\.status) { [weak self] item, _ in
            let failed = item.status == .failed
            Task { @MainActor in
                if failed { self?.status = .failed("The station isn't responding. Try another one.") }
            }
        }
        timeControlObservation = player.observe(\.timeControlStatus) { [weak self] player, _ in
            let playing = player.timeControlStatus == .playing
            Task { @MainActor in
                guard let self, self.status != .idle else { return }
                if playing { self.status = .playing }
            }
        }
        player.play()
        updateNowPlaying()
        configureRemoteCommands()
    }

    func stop() {
        player?.pause()
        player = nil
        statusObservation = nil
        timeControlObservation = nil
        status = .idle
        station = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func updateNowPlaying() {
        guard let station else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: station.name,
            MPMediaItemPropertyArtist: "Live radio",
            MPNowPlayingInfoPropertyIsLiveStream: true,
        ]
    }

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.pauseCommand.removeTarget(nil)
        center.playCommand.removeTarget(nil)
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.stop() }
            return .success
        }
        center.playCommand.isEnabled = false  // live streams restart from "now" via the app
    }
}
