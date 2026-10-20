#if canImport(MediaPlayer) && os(iOS)
import MediaPlayer
import UIKit

/// Lock screen, Control Center, AirPods and CarPlay-style remote controls for the player.
@MainActor
final class SystemMediaControls {
    private let player: PlayerController
    private var artworkTask: Task<Void, Never>?
    private var artworkFor: URL?
    private var artwork: MPMediaItemArtwork?

    init(player: PlayerController) {
        self.player = player
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.resume() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.next() }
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            MainActor.assumeIsolated { self?.player.previous() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            MainActor.assumeIsolated { self?.player.seek(to: event.positionTime) }
            return .success
        }
        observe()
    }

    private func resume() {
        if player.state == .paused || isFailed { player.togglePlayPause() }
    }

    private var isFailed: Bool {
        if case .failed = player.state { return true }
        return false
    }

    /// Re-publishes Now Playing info whenever the player's observable state changes.
    private func observe() {
        withObservationTracking {
            update()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func update() {
        let center = MPRemoteCommandCenter.shared()
        guard let item = player.item else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            return
        }
        let live = item.isLive
        center.nextTrackCommand.isEnabled = !live && player.hasNext
        center.previousTrackCommand.isEnabled = !live
        center.changePlaybackPositionCommand.isEnabled = !live
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: live,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: player.position,
            MPNowPlayingInfoPropertyPlaybackRate: player.state == .playing ? 1.0 : 0.0,
        ]
        if let album = item.track?.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let duration = player.duration { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork, artworkFor == item.artworkURL { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState =
            player.state == .playing ? .playing : .paused
        loadArtwork(item.artworkURL)
    }

    /// iOS asks for artwork on a background thread, so the closure must not be main-actor bound.
    private nonisolated static func artwork(for image: UIImage) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func loadArtwork(_ url: URL?) {
        guard url != artworkFor else { return }
        artworkFor = url
        artwork = nil
        artworkTask?.cancel()
        guard let url else { return }
        artworkTask = Task { [weak self] in
            guard let (data, _) = try? await URLSession.shared.data(from: url),
                  let image = UIImage(data: data), !Task.isCancelled else { return }
            let artwork = Self.artwork(for: image)
            await MainActor.run {
                guard let self, self.artworkFor == url else { return }
                self.artwork = artwork
                self.update()
            }
        }
    }
}
#endif
