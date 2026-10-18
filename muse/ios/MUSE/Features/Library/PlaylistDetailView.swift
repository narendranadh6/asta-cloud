import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffController.self) private var handoff
    @Environment(\.dismiss) private var dismiss
    @Bindable var playlist: PlaylistEntity

    @State private var renaming = false
    @State private var draftName = ""
    @State private var draftDetails = ""
    @State private var linkingYouTube = false
    @State private var youtubeLinkText = ""
    @State private var linkError = false
    @State private var addingSongs = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            header.listRowBackground(Color.clear)
            Section {
                PlaybackBoundaryNote().listRowBackground(Color.clear)
            }
            Section("Songs") {
                if playlist.items.isEmpty {
                    ContentUnavailableView("Empty playlist", systemImage: "music.note",
                                           description: Text("Add songs from search or the AI DJ."))
                }
                ForEach(playlist.orderedItems) { item in
                    NavigationLink(value: Track(item: item)) {
                        HStack(spacing: Spacing.sm) {
                            Text("\(item.position + 1)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(MUSEColor.mutedText)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            TrackRow(track: item)
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if !item.isDemo {
                            Button {
                                Task { await handoff.open(item, upNext: upNext(after: item), using: app.handoff, haptics: settings.hapticsEnabled) }
                            } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                                .tint(MUSEColor.accent)
                        }
                    }
                    .contextMenu {
                        if !item.isDemo {
                            Button("Open in \(settings.browserPreference.label)", systemImage: "arrow.up.forward.app") {
                                Task { await handoff.open(item, upNext: upNext(after: item), using: app.handoff, haptics: settings.hapticsEnabled) }
                            }
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
        .museScreen()
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
                    Button("Link YouTube playlist", systemImage: "link") {
                        youtubeLinkText = playlist.youtubePlaylistID ?? ""
                        linkingYouTube = true
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
        .alert("Link a YouTube playlist", isPresented: $linkingYouTube) {
            TextField("Playlist URL or ID", text: $youtubeLinkText)
            Button("Save") { saveYouTubeLink() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paste a public YouTube playlist link to open it in your browser in one tap.")
        }
        .alert("That isn't a valid YouTube playlist link.", isPresented: $linkError) {
            Button("OK", role: .cancel) {}
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
                ArtworkView(url: playlist.artworkURL, size: 120, cornerRadius: Spacing.corner)
                VStack(alignment: .leading, spacing: 4) {
                    if playlist.isAIGenerated {
                        Label("AI collection", systemImage: "sparkles")
                            .font(.caption.weight(.semibold)).foregroundStyle(MUSEColor.secondary)
                    }
                    Text(playlist.name).font(MUSEFont.title).foregroundStyle(MUSEColor.text)
                    Text("\(playlist.items.count) songs · about \(DurationFormatter.approximate(playlist.totalDurationSeconds))")
                        .font(.subheadline).foregroundStyle(MUSEColor.mutedText)
                }
            }
            if let details = playlist.details, !details.isEmpty {
                Text(details).font(.subheadline).foregroundStyle(MUSEColor.mutedText)
            }
            HStack(spacing: Spacing.sm) {
                if let first = playlist.orderedItems.first(where: { !$0.isDemo }) {
                    Button {
                        Task { await handoff.open(first, upNext: upNext(after: first), using: app.handoff, haptics: settings.hapticsEnabled) }
                    } label: {
                        Label("Open first song", systemImage: "arrow.up.forward.app")
                    }
                    .buttonStyle(NeonButtonStyle())
                }
                if let youtubeID = playlist.youtubePlaylistID {
                    Button {
                        Task { await handoff.openPlaylist(id: youtubeID, using: app.handoff, haptics: settings.hapticsEnabled) }
                    } label: {
                        Label("YouTube playlist", systemImage: "list.and.film")
                    }
                    .buttonStyle(NeonButtonStyle(prominent: false))
                }
            }
            Text(app.handoff.destinationDescription())
                .font(.caption).foregroundStyle(MUSEColor.mutedText)
        }
    }

    private func upNext(after item: PlaylistItemEntity) -> [any TrackDisplayable] {
        playlist.orderedItems.filter { $0.position > item.position }
    }

    private func saveYouTubeLink() {
        let text = youtubeLinkText.trimmingCharacters(in: .whitespacesAndNewlines)
        var id = text
        if let components = URLComponents(string: text),
           let list = components.queryItems?.first(where: { $0.name == "list" })?.value {
            id = list
        }
        if app.library.setYouTubePlaylistID(id.isEmpty ? nil : id, on: playlist) {
            app.playlistChanged(playlist)
        } else {
            linkError = true
        }
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
                            added.insert(track.videoId)
                        } label: {
                            HStack {
                                TrackRow(track: track)
                                Image(systemName: added.contains(track.videoId) ? "checkmark.circle.fill" : "plus.circle")
                                    .foregroundStyle(MUSEColor.primary)
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                        .task { if model.shouldLoadMore(after: track) { await model.loadMore(api: app.api) } }
                    }
                }
            }
            .listStyle(.plain)
            .museScreen()
            .navigationTitle("Add to \(playlist.name)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always))
            .onSubmit(of: .search) { Task { await model.submit(api: app.api) } }
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
