import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerController.self) private var player
    @Environment(\.dismiss) private var dismiss
    @Bindable var playlist: PlaylistEntity

    @State private var renaming = false
    @State private var draftName = ""
    @State private var draftDetails = ""
    @State private var addingSongs = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            header.listRowBackground(Color.clear)
            Section("Songs") {
                if playlist.items.isEmpty {
                    ContentUnavailableView("Empty playlist", systemImage: "music.note",
                                           description: Text("Add songs from Search or ask Halo."))
                }
                ForEach(Array(playlist.orderedItems.enumerated()), id: \.element.id) { index, item in
                    NavigationLink(value: Track(item: item)) {
                        HStack(spacing: Spacing.sm) {
                            Text("\(item.position + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(HaloColor.mutedText)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            TrackRow(track: item) { play(startAt: index) }
                        }
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            player.playNext(Track(item: item))
                        } label: { Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") }
                            .tint(HaloColor.accent)
                    }
                    .contextMenu {
                        Button("Play", systemImage: "play.fill") { play(startAt: index) }
                        Button("Play next", systemImage: "text.line.first.and.arrowtriangle.forward") {
                            player.playNext(Track(item: item))
                        }
                        Button("Add to queue", systemImage: "text.append") {
                            player.addToQueue([Track(item: item)])
                        }
                    }
                }
                .onMove { source, destination in
                    app.library.moveItems(fromOffsets: source, toOffset: destination, in: playlist)
                    app.playlistChanged(playlist)
                }
                .onDelete { offsets in
                    app.library.removeItems(atOffsets: offsets, from: playlist)
                    app.playlistChanged(playlist)
                }
                Button { addingSongs = true } label: { Label("Add songs", systemImage: "plus") }
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .haloScreen()
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Rename", systemImage: "pencil") {
                        draftName = playlist.name
                        draftDetails = playlist.details ?? ""
                        renaming = true
                    }
                    Button("Delete playlist", systemImage: "trash", role: .destructive) {
                        confirmDelete = true
                    }
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Playlist options")
            }
        }
        .alert("Rename playlist", isPresented: $renaming) {
            TextField("Name", text: $draftName)
            TextField("Description", text: $draftDetails)
            Button("Save") {
                app.library.rename(playlist, to: draftName, details: draftDetails)
                app.playlistChanged(playlist)
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete \(playlist.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { await app.sync.deleteRemote(of: playlist) }
                app.library.delete(playlist)
                dismiss()
            }
        }
        .sheet(isPresented: $addingSongs) {
            AddSongsSheet(playlist: playlist)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(alignment: .bottom, spacing: Spacing.md) {
                HaloArtwork(url: playlist.artworkURL, size: 120, cornerRadius: Spacing.corner)
                VStack(alignment: .leading, spacing: 4) {
                    if playlist.isAIGenerated {
                        Label("AI collection", systemImage: "sparkles")
                            .font(.caption.weight(.semibold)).foregroundStyle(HaloColor.secondary)
                    }
                    Text(playlist.name).font(HaloFont.title).foregroundStyle(HaloColor.text)
                    Text("\(playlist.items.count) songs · about \(DurationFormatter.approximate(playlist.totalDurationSeconds))")
                        .font(.subheadline).foregroundStyle(HaloColor.mutedText)
                }
            }
            if let details = playlist.details, !details.isEmpty {
                Text(details).font(.subheadline).foregroundStyle(HaloColor.mutedText)
            }
            if !playlist.items.isEmpty {
                HStack(spacing: Spacing.sm) {
                    PlayButton(tracks: tracks, context: playlist.name)
                    Button {
                        player.play(tracks.shuffled(), from: playlist.name)
                    } label: {
                        Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(NeonButtonStyle(prominent: false))
                }
            }
        }
    }

    private var tracks: [Track] { playlist.orderedItems.map(Track.init(item:)) }

    private func play(startAt index: Int) {
        player.play(tracks, startAt: index, from: playlist.name)
    }
}

/// Search-and-add sheet used from Playlist Details.
struct AddSongsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    var playlist: PlaylistEntity
    @State private var model = SearchViewModel()
    @State private var added: Set<String> = []

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                switch model.phase {
                case .idle:
                    ContentUnavailableView("Search to add songs", systemImage: "magnifyingglass")
                        .listRowBackground(Color.clear)
                case .loading:
                    LoadingStateView().listRowBackground(Color.clear)
                case .empty:
                    ContentUnavailableView.search(text: model.query).listRowBackground(Color.clear)
                case let .failed(error):
                    ErrorStateView(error: error) { Task { await model.retry(api: app.api) } }
                        .listRowBackground(Color.clear)
                case .loaded:
                    ForEach(model.results) { track in
                        Button {
                            app.library.add(track, to: playlist)
                            app.playlistChanged(playlist)
                            added.insert(track.id)
                        } label: {
                            HStack {
                                TrackRow(track: track)
                                Image(systemName: added.contains(track.id) ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(HaloColor.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .task { if model.shouldLoadMore(after: track) { await model.loadMore(api: app.api) } }
                    }
                }
            }
            .listStyle(.plain)
            .haloScreen()
            .navigationTitle("Add to \(playlist.name)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always))
            .onSubmit(of: .search) { Task { await model.submit(api: app.api) } }
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
