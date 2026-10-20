import SwiftData
import SwiftUI

/// Navigation values shared by every tab's NavigationStack.
struct MoodRoute: Hashable {
    var mood: Mood
}

struct SearchRoute: Hashable {
    var query: String
    var kind: SearchKind
    var title: String
}

struct StudioRoute: Hashable {
    var mood: Mood?
    var description: String
}

extension View {
    func haloDestinations() -> some View {
        navigationDestination(for: Track.self) { SongDetailView(track: $0) }
            .navigationDestination(for: PlaylistEntity.self) { PlaylistDetailView(playlist: $0) }
            .navigationDestination(for: MoodRoute.self) { MoodDetailView(mood: $0.mood) }
            .navigationDestination(for: SearchRoute.self) {
                SearchResultsScreen(query: $0.query, kind: $0.kind, title: $0.title)
            }
            .navigationDestination(for: StudioRoute.self) {
                PlaylistStudioView(initialMood: $0.mood, initialDescription: $0.description)
            }
    }
}

/// Plays a song (or a whole list starting at it) in Halo's player.
struct PlayButton: View {
    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    var tracks: [Track]
    var startAt = 0
    var title = "Play"

    private var target: Track? { tracks.indices.contains(startAt) ? tracks[startAt] : nil }
    private var isCurrent: Bool { target != nil && player.currentTrack?.id == target?.id }
    private var playable: Bool { tracks.contains { $0.streamURL != nil } }

    var body: some View {
        Button {
            Haptics.tap(enabled: settings.hapticsEnabled)
            if isCurrent {
                player.togglePlayPause()
            } else {
                player.play(tracks, startAt: startAt)
            }
        } label: {
            Label(isCurrent && player.isPlaying ? "Pause" : title,
                  systemImage: isCurrent && player.isPlaying ? "pause.fill" : "play.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(NeonButtonStyle())
        .disabled(!playable)
        .accessibilityHint(playable ? "" : "This song can't be played right now")
    }
}

/// Shown only when the server has no music source enabled: a setup problem, not data.
struct SearchSetupBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if !app.catalogConfigured {
            NoticeBanner(
                text: "Music isn't set up on the server yet. Saved songs and playlists still work.",
                systemImage: "exclamationmark.triangle")
        }
    }
}
