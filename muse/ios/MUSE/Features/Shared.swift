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
    func museDestinations() -> some View {
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

/// "Listen in Brave" with an explicit destination label. Disabled for demo items.
struct HandoffButton: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffController.self) private var handoff
    var track: any TrackDisplayable
    var compact = false

    var body: some View {
        VStack(spacing: Spacing.xxs) {
            Button {
                Task { await handoff.open(track, using: app.handoff, haptics: settings.hapticsEnabled) }
            } label: {
                Label(title, systemImage: "arrow.up.forward.app")
                    .frame(maxWidth: compact ? nil : .infinity)
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(track.isDemo || handoff.isOpening)
            .accessibilityHint(destinationText)
            if !compact {
                Text(destinationText)
                    .font(.caption)
                    .foregroundStyle(MUSEColor.mutedText)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var title: String {
        settings.browserPreference == .brave ? "Listen in Brave" : "Open in browser"
    }

    private var destinationText: String {
        track.isDemo
            ? "Demo item — not a real YouTube video, so it can't be opened."
            : app.handoff.destinationDescription() + ". Playback happens there, outside MUSE."
    }
}

/// Explains what MUSE cannot do once a link is handed off.
struct PlaybackBoundaryNote: View {
    var body: some View {
        NoticeBanner(
            text: "Playback happens in your browser. MUSE can't pause, skip, see progress or "
                + "advance to the next song for you — come back and pick the next track.",
            systemImage: "hand.raised")
    }
}

struct DemoModeBanner: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        if app.provider == .demo {
            NoticeBanner(
                text: "Demo catalog: YouTube search isn't configured on the server, so results "
                    + "are fictional and can't be opened.",
                systemImage: "flask")
        }
    }
}
