import SwiftData
import SwiftUI

struct LibraryView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case songs = "Songs", playlists = "Playlists", ai = "AI", artists = "Artists", recent = "Recent"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var app
    @State private var segment: Segment = .playlists
    @State private var filter = ""
    @State private var showingNewPlaylist = false
    @State private var newName = ""
    @State private var newArtist = ""

    @Query(filter: #Predicate<TrackEntity> { $0.isSaved }, sort: \TrackEntity.savedAt, order: .reverse)
    private var savedTracks: [TrackEntity]
    @Query(sort: \PlaylistEntity.updatedAt, order: .reverse) private var playlists: [PlaylistEntity]
    @Query(sort: \ArtistEntity.addedAt) private var artists: [ArtistEntity]
    @Query(sort: \RecentSearchEntity.searchedAt, order: .reverse) private var recent: [RecentSearchEntity]

    var body: some View {
        List {
            Picker("Section", selection: $segment) {
                ForEach(Segment.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)

            switch segment {
            case .songs: songs
            case .playlists: playlistList(playlists.filter { matches($0.name) })
            case .ai: playlistList(playlists.filter { $0.isAIGenerated && matches($0.name) })
            case .artists: artistList
            case .recent: recentList
            }
        }
        .listStyle(.plain)
        .museScreen()
        .navigationTitle("Library")
        .searchable(text: $filter, prompt: "Filter your library")
        .toolbar {
            Button("New playlist", systemImage: "plus") {
                newName = ""
                showingNewPlaylist = true
            }
        }
        .alert("New playlist", isPresented: $showingNewPlaylist) {
            TextField("Name", text: $newName)
            Button("Create") {
                let playlist = app.library.createPlaylist(name: newName)
                app.playlistChanged(playlist)
            }
            Button("Cancel", role: .cancel) {}
        }
        .museDestinations()
    }

    private func matches(_ text: String) -> Bool {
        filter.isEmpty || text.localizedCaseInsensitiveContains(filter)
    }

    @ViewBuilder
    private var songs: some View {
        let items = savedTracks.filter { matches($0.title) || matches($0.channelTitle) }
        if items.isEmpty {
            ContentUnavailableView("No saved songs", systemImage: "heart",
                                   description: Text("Tap the heart on any song to save it here."))
                .listRowBackground(Color.clear)
        }
        ForEach(items) { entity in
            NavigationLink(value: Track(entity: entity)) {
                TrackRow(track: entity, subtitle: entity.isAvailable ? nil : "Unavailable on YouTube")
            }
            .listRowBackground(Color.clear)
            .swipeActions {
                Button("Remove", role: .destructive) {
                    app.library.setSaved(false, track: Track(entity: entity))
                }
            }
        }
    }

    @ViewBuilder
    private func playlistList(_ items: [PlaylistEntity]) -> some View {
        if items.isEmpty {
            ContentUnavailableView(
                segment == .ai ? "No AI collections yet" : "No playlists yet",
                systemImage: segment == .ai ? "sparkles" : "music.note.list",
                description: Text(segment == .ai
                                  ? "Save a queue from the AI DJ or Playlist Studio."
                                  : "Create one with + or from any song."))
                .listRowBackground(Color.clear)
        }
        ForEach(items) { playlist in
            NavigationLink(value: playlist) { PlaylistRow(playlist: playlist) }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .onDelete { offsets in
            for index in offsets {
                let playlist = items[index]
                Task { await app.sync.deleteRemote(of: playlist) }
                app.library.delete(playlist)
            }
        }
        if segment == .playlists {
            NavigationLink(value: StudioRoute(mood: nil, description: "")) {
                Label("Create with Playlist Studio", systemImage: "wand.and.stars")
            }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var artistList: some View {
        Section("Favorite artists") {
            HStack {
                TextField("Add an artist", text: $newArtist)
                    .submitLabel(.done)
                    .onSubmit(addArtist)
                Button("Add", action: addArtist).disabled(newArtist.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(artists.filter { !$0.isExcluded && matches($0.name) }) { artist in
                NavigationLink(value: SearchRoute(query: artist.name, kind: .artist, title: artist.name)) {
                    Label(artist.name, systemImage: "music.mic")
                }
            }
            .onDelete { offsets in
                let visible = artists.filter { !$0.isExcluded && matches($0.name) }
                offsets.forEach { app.library.removeArtist(visible[$0]) }
            }
        }
        .listRowBackground(Color.clear)
    }

    private func addArtist() {
        app.library.setArtist(newArtist, excluded: false)
        newArtist = ""
    }

    @ViewBuilder
    private var recentList: some View {
        if recent.isEmpty {
            ContentUnavailableView("No recent searches", systemImage: "clock")
                .listRowBackground(Color.clear)
        }
        ForEach(recent.filter { matches($0.query) }) { entry in
            NavigationLink(value: SearchRoute(
                query: entry.query, kind: SearchKind(rawValue: entry.kindRaw) ?? .song, title: entry.query)) {
                VStack(alignment: .leading) {
                    Text(entry.query).foregroundStyle(MUSEColor.text)
                    Text(entry.searchedAt.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(MUSEColor.mutedText)
                }
            }
            .listRowBackground(Color.clear)
        }
    }
}
