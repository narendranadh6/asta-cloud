import SwiftUI

struct DraftEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffController.self) private var handoff
    @Environment(\.dismiss) private var dismiss
    @Binding var draft: EditableDraft
    var onRegenerate: (() async -> Void)?
    var onSaved: ((PlaylistEntity) -> Void)?

    @State private var isRegenerating = false
    @State private var savedPlaylist: PlaylistEntity?
    @State private var feedback: [String: FeedbackRating] = [:]

    var body: some View {
        List {
            Section {
                TextField("Playlist name", text: $draft.title)
                    .font(MUSEFont.title)
                    .foregroundStyle(MUSEColor.text)
                    .accessibilityLabel("Playlist name")
                if !draft.explanation.isEmpty {
                    Text(draft.explanation).font(.subheadline).foregroundStyle(MUSEColor.mutedText)
                }
                Text(summary).font(.caption).foregroundStyle(MUSEColor.mutedText)
                ForEach(draft.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(MUSEColor.mutedText)
                }
            }
            .listRowBackground(Color.clear)

            Section {
                if draft.queue.isEmpty {
                    ContentUnavailableView("No songs left", systemImage: "music.note",
                                           description: Text("Regenerate to get new picks."))
                }
                ForEach(draft.queue.items) { item in
                    row(item)
                }
                .onMove { draft.queue.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { draft.queue.remove(atOffsets: $0) }
            } header: {
                Text("Queue · \(draft.queue.count) songs")
            } footer: {
                Text("Every song is a verified YouTube result. Searched for: "
                     + draft.queries.joined(separator: " · "))
                    .font(.caption2)
            }
            .listRowBackground(Color.clear)

            Section {
                PlaybackBoundaryNote().listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .museScreen()
        .navigationTitle("Review playlist")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItemGroup(placement: .bottomBar) {
                if let onRegenerate {
                    Button {
                        Task {
                            isRegenerating = true
                            await onRegenerate()
                            isRegenerating = false
                        }
                    } label: {
                        if isRegenerating { ProgressView() } else { Label("Regenerate", systemImage: "arrow.clockwise") }
                    }
                    .disabled(isRegenerating)
                }
                Spacer()
                Button(savedPlaylist == nil ? "Save playlist" : "Saved ✓") { save() }
                    .buttonStyle(NeonButtonStyle())
                    .disabled(draft.queue.isEmpty || savedPlaylist != nil)
            }
        }
    }

    private var summary: String {
        let planner = draft.planner == "llm" ? "Planned by AI" : "Planned by MUSE's built-in planner"
        return "\(DurationFormatter.approximate(draft.totalSeconds)) of "
            + "\(DurationFormatter.approximate(draft.targetSeconds)) target · \(planner)"
    }

    private func row(_ item: RecommendedTrack) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink(value: item.track) { TrackRow(track: item.track) }
            if let reason = item.reasons.first {
                Text(reason).font(.caption).foregroundStyle(MUSEColor.secondary)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                Task {
                    await handoff.open(item.track, upNext: upNext(after: item.track.videoId),
                                       using: app.handoff, haptics: settings.hapticsEnabled)
                }
            } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                .tint(MUSEColor.accent)
            if settings.personalizationEnabled {
                Button { rate(item, .like) } label: { Label("Like", systemImage: "hand.thumbsup") }
                    .tint(MUSEColor.success)
            }
        }
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                draft.queue.remove(id: item.id)
                if settings.personalizationEnabled { rate(item, .skip) }
            } label: { Label("Remove", systemImage: "trash") }
            if settings.personalizationEnabled {
                Button {
                    rate(item, .dislike)
                    draft.queue.remove(id: item.id)
                } label: { Label("Not for me", systemImage: "hand.thumbsdown") }
                    .tint(MUSEColor.danger)
            }
        }
    }

    private func upNext(after videoID: String) -> [any TrackDisplayable] {
        let tracks = draft.queue.items.map(\.track)
        guard let index = tracks.firstIndex(where: { $0.videoId == videoID }) else { return tracks }
        return Array(tracks[(index + 1)...])
    }

    private func rate(_ item: RecommendedTrack, _ rating: FeedbackRating) {
        feedback[item.id] = rating
        let request = FeedbackRequest(
            videoId: item.track.videoId, rating: rating, sessionId: draft.sessionID,
            channelTitle: item.track.channelTitle)
        Task { _ = try? await app.api.sendFeedback(request) }
    }

    private func save() {
        let playlist = app.library.createPlaylist(
            name: draft.title, details: draft.explanation,
            tracks: draft.queue.items.map(\.track), isAIGenerated: true,
            recommendationSessionID: draft.sessionID)
        app.playlistChanged(playlist)
        savedPlaylist = playlist
        Haptics.success(enabled: settings.hapticsEnabled)
        onSaved?(playlist)
    }
}
