import SwiftData
import SwiftUI

struct LibraryView: View {
    enum Segment: String, CaseIterable, Identifiable {
        case songs = "Songs", playlists = "Playlists", ai = "AI", artists = "Artists", recent = "Recent"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var app
    @Environment(PlayerController.self) private var player
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
            ChipBar(options: Segment.allCases, selection: $segment) { $0.rawValue }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            switch segment {
            case .songs: songs
            case .playlists:
                likedCard
                if !aiPlaylists.isEmpty && filter.isEmpty {
                    Section {
                        ForEach(aiPlaylists.prefix(5)) { playlist in
                            NavigationLink(value: playlist) { PlaylistRow(playlist: playlist) }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                    } header: {
                        Text("AI playlists").font(HaloFont.section).foregroundStyle(HaloColor.text)
                            .textCase(nil)
                    }
                }
                Section {
                    playlistList(playlists.filter { !$0.isAIGenerated && matches($0.name) })
                } header: {
                    Text("Your playlists").font(HaloFont.section).foregroundStyle(HaloColor.text)
                        .textCase(nil)
                }
            case .ai: playlistList(playlists.filter { $0.isAIGenerated && matches($0.name) })
            case .artists: artistList
            case .recent: recentList
            }
        }
        .listStyle(.plain)
        .haloScreen()
        .navigationTitle("Your Library")
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
        .haloDestinations()
    }

    private var aiPlaylists: [PlaylistEntity] { playlists.filter(\.isAIGenerated) }

    private var likedCard: some View {
        Button { segment = .songs } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "heart.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(HaloColor.neon))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Liked songs").font(HaloFont.headline).foregroundStyle(HaloColor.text)
                    Text("\(savedTracks.count) songs saved in Halo")
                        .font(.subheadline).foregroundStyle(HaloColor.mutedText)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(HaloColor.mutedText)
            }
            .padding(Spacing.sm)
            .background(RoundedRectangle(cornerRadius: Spacing.corner, style: .continuous)
                .fill(LinearGradient(colors: [HaloColor.primary.opacity(0.55), HaloColor.surface],
                                     startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private func matches(_ text: String) -> Bool {
        filter.isEmpty || text.localizedCaseInsensitiveContains(filter)
    }

    @ViewBuilder
    private var songs: some View {
        let items = savedTracks.filter { matches($0.title) || matches($0.artist) }
        let playable = items.filter(\.isAvailable).map(Track.init(entity:))
        if items.isEmpty {
            ContentUnavailableView("No saved songs", systemImage: "heart",
                                   description: Text("Tap the heart on any song to save it here."))
                .listRowBackground(Color.clear)
        }
        if !playable.isEmpty {
            PlayButton(tracks: playable, title: "Play saved songs", context: "Saved songs")
                .listRowBackground(Color.clear)
        }
        ForEach(items) { entity in
            NavigationLink(value: Track(entity: entity)) {
                TrackRow(track: entity, subtitle: entity.isAvailable ? nil : "No longer available") {
                    let index = playable.firstIndex { $0.id == entity.trackID } ?? 0
                    player.play(playable, startAt: index, from: "Saved songs")
                }
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
                                  ? "Save a queue from Halo or Playlist Studio."
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
                    Text(entry.query).foregroundStyle(HaloColor.text)
                    Text(entry.searchedAt.formatted(.relative(presentation: .named)))
                        .font(.caption).foregroundStyle(HaloColor.mutedText)
                }
            }
            .listRowBackground(Color.clear)
        }
    }
}
