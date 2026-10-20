import SwiftData
import SwiftUI

@MainActor
@Observable
final class SongDetailViewModel {
    private(set) var track: Track
    private(set) var related: [Track] = []
    private(set) var isLoadingRelated = false
    private(set) var unavailable = false
    private(set) var feedback: FeedbackRating?
    /// MusicBrainz facts; nil until loaded or when the server has MusicBrainz switched off.
    private(set) var canonical: TrackMetadataResponse?
    private(set) var isLoadingCanonical = true

    init(track: Track) {
        self.track = track
    }

    /// Refreshes metadata (verifies the video is still available) and loads related music.
    func load(api: MusicAPI) async {
        async let canonicalLoad: Void = loadCanonical(api: api)
        do {
            track = try await api.video(id: track.videoId)
        } catch let error as APIError where error.code == "video_unavailable" {
            unavailable = true
        } catch {}
        isLoadingRelated = true
        defer { isLoadingRelated = false }
        // YouTube removed relatedToVideoId search in 2023; related music is the channel's
        // other songs, which is real data rather than a guess.
        if let response = try? await api.search(
            query: track.channelTitle, kind: .artist, pageToken: nil, limit: 10) {
            related = response.items.filter { $0.videoId != track.videoId }
        }
        await canonicalLoad
    }

    private func loadCanonical(api: MusicAPI) async {
        defer { isLoadingCanonical = false }
        canonical = try? await api.trackMetadata(videoID: track.videoId)
    }

    func send(_ rating: FeedbackRating, api: MusicAPI) async {
        feedback = rating
        _ = try? await api.sendFeedback(FeedbackRequest(
            videoId: track.videoId, rating: rating, channelTitle: track.channelTitle))
    }
}

struct SongDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(HandoffController.self) private var handoff
    @Query(sort: \PlaylistEntity.updatedAt, order: .reverse) private var playlists: [PlaylistEntity]
    @State private var model: SongDetailViewModel
    @State private var isSaved = false
    @State private var showingNewPlaylist = false
    @State private var newPlaylistName = ""
    @State private var addedConfirmation: String?

    init(track: Track) {
        _model = State(initialValue: SongDetailViewModel(track: track))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ArtworkView(url: model.track.artworkURL, size: nil, cornerRadius: Spacing.cornerLarge)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .shadow(color: HaloColor.primary.opacity(0.35), radius: 24, y: 12)
                header
                if model.unavailable {
                    NoticeBanner(text: "YouTube reports this video is unavailable, private, or "
                                 + "blocked in your region.", systemImage: "exclamationmark.triangle")
                }
                HandoffButton(track: model.track)
                actions
                PlaybackBoundaryNote()
                RecordingFactsCard(isLoading: model.isLoadingCanonical, metadata: model.canonical)
                relatedSection
            }
            .padding(Spacing.md)
        }
        .haloScreen()
        .navigationTitle("Song")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isSaved = app.library.isSaved(videoId: model.track.videoId)
            app.library.recordDiscovered(model.track)
            await model.load(api: app.api)
        }
        .alert("New playlist", isPresented: $showingNewPlaylist) {
            TextField("Name", text: $newPlaylistName)
            Button("Create") { createPlaylistWithTrack() }
            Button("Cancel", role: .cancel) {}
        }
        .overlay(alignment: .bottom) {
            if let addedConfirmation {
                Text(addedConfirmation)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Spacing.md).padding(.vertical, Spacing.sm)
                    .background(Capsule().fill(HaloColor.surface))
                    .padding(.bottom, Spacing.lg)
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        self.addedConfirmation = nil
                    }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(model.track.title)
                .font(HaloFont.title)
                .foregroundStyle(HaloColor.text)
            Text(model.track.channelTitle)
                .font(.headline)
                .foregroundStyle(HaloColor.mutedText)
            HStack(spacing: Spacing.xs) {
                AttributionBadge()
                if let seconds = model.track.durationSeconds {
                    Text(DurationFormatter.clock(seconds)).monospacedDigit()
                }
                if let views = model.track.viewCount {
                    Text("\(views.formatted(.number.notation(.compactName))) views")
                }
                if let date = model.track.publishedAt {
                    Text(date.formatted(.dateTime.year()))
                }
            }
            .font(.caption)
            .foregroundStyle(HaloColor.mutedText)
            Text("Source: YouTube. Title, channel and artwork are YouTube metadata.")
                .font(.caption2)
                .foregroundStyle(HaloColor.mutedText)
        }
    }

    private var actions: some View {
        HStack(spacing: Spacing.sm) {
            Button {
                isSaved.toggle()
                app.library.setSaved(isSaved, track: model.track)
                Haptics.tap(enabled: settings.hapticsEnabled)
                if isSaved { Task { await model.send(.save, api: app.api) } }
            } label: {
                Label(isSaved ? "Saved" : "Save", systemImage: isSaved ? "heart.fill" : "heart")
            }
            .buttonStyle(NeonButtonStyle(prominent: false))
            .accessibilityValue(isSaved ? "Saved" : "Not saved")

            Menu {
                ForEach(playlists) { playlist in
                    Button(playlist.name) { add(to: playlist) }
                }
                Divider()
                Button("New playlist…", systemImage: "plus") {
                    newPlaylistName = ""
                    showingNewPlaylist = true
                }
            } label: {
                Label("Add to playlist", systemImage: "text.badge.plus")
            }
            .buttonStyle(NeonButtonStyle(prominent: false))

            if settings.personalizationEnabled {
                Spacer(minLength: 0)
                Button { Task { await model.send(.dislike, api: app.api) } } label: {
                    Image(systemName: model.feedback == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                }
                .accessibilityLabel("Less like this")
            }
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "More from \(model.track.channelTitle)")
            if model.isLoadingRelated {
                LoadingStateView(message: "Finding related music…")
            } else if model.related.isEmpty {
                Text("No related music found.").font(.subheadline).foregroundStyle(HaloColor.mutedText)
            } else {
                ForEach(model.related) { track in
                    NavigationLink(value: track) { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func add(to playlist: PlaylistEntity) {
        app.library.add(model.track, to: playlist)
        app.playlistChanged(playlist)
        Haptics.success(enabled: settings.hapticsEnabled)
        addedConfirmation = "Added to \(playlist.name)"
    }

    private func createPlaylistWithTrack() {
        let playlist = app.library.createPlaylist(name: newPlaylistName, tracks: [model.track])
        app.playlistChanged(playlist)
        Haptics.success(enabled: settings.hapticsEnabled)
        addedConfirmation = "Created \(playlist.name)"
    }
}

/// "About this recording": canonical facts from MusicBrainz (CC0 open data).
/// Only shown when MusicBrainz is confident it identified the upload.
struct RecordingFactsCard: View {
    var isLoading: Bool
    var metadata: TrackMetadataResponse?

    var body: some View {
        if isLoading {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "About this recording")
                LoadingStateView(message: "Looking it up on MusicBrainz…")
            }
        } else if let metadata, let recording = metadata.recording, metadata.matched {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: "About this recording")
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    if let album = recording.album {
                        HStack(spacing: Spacing.md) {
                            ArtworkView(url: album.coverArtURL, size: 64, cornerRadius: Spacing.cornerSmall)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title).font(.headline).foregroundStyle(HaloColor.text)
                                Text([album.releaseGroupType, album.date].compactMap { $0 }
                                    .joined(separator: " · "))
                                    .font(.caption).foregroundStyle(HaloColor.mutedText)
                            }
                        }
                    }
                    fact("Artist", recording.artistName)
                    fact("Title", recording.title)
                    fact("First released", recording.firstReleaseDate)
                    if let seconds = recording.lengthMs.map({ $0 / 1000 }) {
                        fact("Length", DurationFormatter.clock(seconds))
                    }
                    if let label = recording.album?.labels.first {
                        fact("Label", [label.name, label.catalogNumber].compactMap { $0 }
                            .joined(separator: " · "))
                    }
                    if !recording.isrcs.isEmpty {
                        fact("ISRC", recording.isrcs.joined(separator: ", "))
                    }
                    if let area = metadata.artist?.area ?? metadata.artist?.country {
                        fact("Artist from", area)
                    }
                    let genres = recording.genres.isEmpty ? (metadata.artist?.genres ?? []) : recording.genres
                    if !genres.isEmpty {
                        fact("Genres", genres.prefix(5).joined(separator: ", "))
                    }
                    if let url = recording.musicBrainzURL {
                        Link(destination: url) {
                            Label("View on MusicBrainz", systemImage: "arrow.up.right.square")
                                .font(.subheadline.weight(.semibold))
                        }
                        .tint(HaloColor.accent)
                    }
                }
                .padding(Spacing.md)
                .haloCard()
                Text("Data: MusicBrainz (CC0). Cover art: Cover Art Archive. Matched from the "
                     + "YouTube title, so it can occasionally be a different version.")
                    .font(.caption2).foregroundStyle(HaloColor.mutedText)
            }
        } else if metadata != nil {
            Text("MusicBrainz couldn't confidently identify this upload, so no album facts are shown.")
                .font(.caption).foregroundStyle(HaloColor.mutedText)
        }
    }

    @ViewBuilder
    private func fact(_ label: String, _ value: String?) -> some View {
        if let value, !value.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.caption).foregroundStyle(HaloColor.mutedText)
                    .frame(width: 104, alignment: .leading)
                Text(value).font(.subheadline).foregroundStyle(HaloColor.text)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
        }
    }
}
