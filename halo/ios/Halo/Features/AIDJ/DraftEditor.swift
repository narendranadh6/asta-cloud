import SwiftUI

struct DraftEditorView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerController.self) private var player
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
                PlayButton(tracks: draft.queue.items.map(\.track), title: "Play all")
                    .listRowBackground(Color.clear)
                TextField("Playlist name", text: $draft.title)
                    .font(HaloFont.title)
                    .foregroundStyle(HaloColor.text)
                    .accessibilityLabel("Playlist name")
                if !draft.explanation.isEmpty {
                    Text(draft.explanation).font(.subheadline).foregroundStyle(HaloColor.mutedText)
                }
                Text(summary).font(.caption).foregroundStyle(HaloColor.mutedText)
                ForEach(draft.warnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(HaloColor.mutedText)
                }
            }
            .listRowBackground(Color.clear)

            Section {
                if draft.queue.isEmpty {
                    ContentUnavailableView("No songs left", systemImage: "music.note",
                                           description: Text("Regenerate to get new picks."))
                }
                ForEach(Array(draft.queue.items.enumerated()), id: \.element.id) { index, item in
                    row(item, index: index)
                }
                .onMove { draft.queue.move(fromOffsets: $0, toOffset: $1) }
                .onDelete { draft.queue.remove(atOffsets: $0) }
            } header: {
                Text("Queue · \(draft.queue.count) songs")
            } footer: {
                Text("Every song comes from Halo's catalog (" + draft.sources.joined(separator: ", ")
                     + "). Searched for: " + draft.queries.joined(separator: " · "))
                    .font(.caption2)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .haloScreen()
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
        let planner = draft.planner == "llm" ? "Planned by AI" : "Planned by Halo's built-in planner"
        return "\(DurationFormatter.approximate(draft.totalSeconds)) of "
            + "\(DurationFormatter.approximate(draft.targetSeconds)) target · \(planner)"
    }

    private func row(_ item: RecommendedTrack, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            NavigationLink(value: item.track) {
                TrackRow(track: item.track) {
                    player.play(draft.queue.items.map(\.track), startAt: index)
                }
            }
            if let reason = item.reasons.first {
                Text(reason).font(.caption).foregroundStyle(HaloColor.secondary)
            }
        }
        .swipeActions(edge: .leading) {
            Button {
                player.playNext(item.track)
            } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                .tint(HaloColor.accent)
            if settings.personalizationEnabled {
                Button { rate(item, .like) } label: { Label("Like", systemImage: "hand.thumbsup") }
                    .tint(HaloColor.success)
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
                    .tint(HaloColor.danger)
            }
        }
    }

    private func rate(_ item: RecommendedTrack, _ rating: FeedbackRating) {
        feedback[item.id] = rating
        let request = FeedbackRequest(
            trackId: item.track.id, rating: rating, sessionId: draft.sessionID,
            artist: item.track.artist)
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
