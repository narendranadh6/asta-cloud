import SwiftData
import SwiftUI

/// Everything on Now Playing except the artwork and background, which belong to
/// `PlayerLayer` so they can travel between the mini player and this screen.
struct NowPlayingView: View {
    var item: NowPlayingItem
    var geometry: PlayerGeometry
    var palette: ArtworkPalette
    var collapse: () -> Void
    var openQueue: () -> Void
    var askDJ: (String) -> Void
    var open: (PlayerRoute) -> Void

    @Environment(AppModel.self) private var app
    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @Query(sort: \PlaylistEntity.updatedAt, order: .reverse) private var playlists: [PlaylistEntity]

    @State private var isSaved = false
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: PlayerGeometry.headerHeight)
                .padding(.top, geometry.insets.top)
            // The layer draws the artwork in this space.
            Color.clear.frame(height: geometry.artSide + Spacing.lg)
            if geometry.accessibilitySize {
                ScrollView { controls.padding(.bottom, Spacing.md) }
                    .scrollIndicators(.hidden)
            } else {
                controls
                Spacer(minLength: Spacing.sm)
            }
            HaloDock(item: item, accent: palette.color(\.accent), openQueue: openQueue)
                .padding(.bottom, max(geometry.insets.bottom, Spacing.md) + Spacing.xs)
        }
        .padding(.horizontal, Spacing.lg)
        .foregroundStyle(HaloColor.text)
        .haloToast($toast, edge: .top, padding: geometry.insets.top + Spacing.xxl)
        .onAppear(perform: refreshSaved)
        .onChange(of: player.currentTrack?.id) { _, _ in refreshSaved() }
        .accessibilityIdentifier("nowPlaying")
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: Spacing.xs) {
            Capsule().fill(.white.opacity(0.35)).frame(width: 36, height: 5)
                .accessibilityHidden(true)
            HStack {
                Button(action: collapse) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close Now Playing")
                Spacer()
                VStack(spacing: 2) {
                    Text(item.isLive ? "LISTENING TO" : "PLAYING FROM")
                        .font(HaloFont.eyebrow).tracking(1.2)
                        .foregroundStyle(HaloColor.text.opacity(0.6))
                    Text(contextLine).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                moreMenu
            }
        }
        .padding(.top, Spacing.xs)
    }

    private var artistRoute: ArtistRoute? {
        guard let track = item.track, let id = track.artistPageID else { return nil }
        return ArtistRoute(id: id, name: track.artist)
    }

    private var contextLine: String {
        if item.isLive { return "Live radio" }
        return player.queue.contextTitle ?? item.track?.source.label ?? "Halo"
    }

    private var moreMenu: some View {
        Menu {
            if let track = item.track {
                if let route = artistRoute {
                    Button { open(.artist(route)) } label: {
                        Label("Go to artist", systemImage: "person.crop.circle")
                    }
                }
                if let id = track.albumPageID, let album = track.album {
                    Button { open(.album(AlbumRoute(id: id, title: album))) } label: {
                        Label("Go to album", systemImage: "square.stack")
                    }
                }
                addToPlaylistItems(track)
                Button {
                    askDJ("Songs like \(track.title) by \(track.artist)")
                } label: {
                    Label("More like this", systemImage: "sparkles")
                }
                if let url = track.externalURL {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                    Link(destination: url) {
                        Label("View on \(track.attribution.label)", systemImage: "arrow.up.right.square")
                    }
                }
                if let license = track.license {
                    Section("Licence") {
                        if let url = license.url.flatMap(Track.webURL) {
                            Link(destination: url) { Text("\(license.name) · \(track.artist)") }
                        } else {
                            Text("\(license.name) · \(track.artist)")
                        }
                    }
                }
            }
            Button(role: .destructive) {
                collapse()
                player.stop()
            } label: {
                Label("Stop playing", systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("More")
    }

    // MARK: Controls

    private var controls: some View {
        VStack(spacing: Spacing.md) {
            titleRow
            if item.isLive {
                liveMarker
            } else {
                ScrubBar()
            }
            TransportControls(item: item, ink: palette.color(\.base))
            if let issue = player.phase.issue {
                PlaybackIssueCard(issue: issue) {
                    if let track = item.track { askDJ("Songs like \(track.title) by \(track.artist)") }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(HaloMotion.standard, value: player.phase.issue)
    }

    private var titleRow: some View {
        HStack(alignment: .center, spacing: Spacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(HaloFont.title)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                if let route = artistRoute {
                    Button { open(.artist(route)) } label: {
                        Text(item.subtitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(HaloColor.text.opacity(0.7))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the artist")
                } else {
                    Text(item.subtitle)
                        .font(.body.weight(.medium))
                        .foregroundStyle(HaloColor.text.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            if let track = item.track {
                Button { toggleSave(track) } label: {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(isSaved ? palette.color(\.accent) : HaloColor.text)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel(isSaved ? "Remove from saved songs" : "Save song")
                Menu {
                    playlistButtons(track)
                } label: {
                    Image(systemName: "plus.circle")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Add to playlist")
            }
        }
    }

    private var liveMarker: some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(HaloColor.secondary).frame(width: 8, height: 8)
            Text("LIVE").font(HaloFont.eyebrow).tracking(1.2)
            Spacer()
        }
        .frame(height: 32)
        .accessibilityLabel("Live stream")
    }

    private func addToPlaylistItems(_ track: Track) -> some View {
        Menu {
            playlistButtons(track)
        } label: {
            Label("Add to playlist", systemImage: "text.badge.plus")
        }
    }

    @ViewBuilder
    private func playlistButtons(_ track: Track) -> some View {
        ForEach(playlists) { playlist in
            Button(playlist.name) { add(track, to: playlist) }
        }
        if playlists.isEmpty { Text("No playlists yet") }
    }

    // MARK: Actions

    private func refreshSaved() {
        isSaved = player.currentTrack.map { app.library.isSaved(trackID: $0.id) } ?? false
    }

    private func toggleSave(_ track: Track) {
        isSaved.toggle()
        app.library.setSaved(isSaved, track: track)
        Haptics.success(enabled: settings.hapticsEnabled)
        toast = isSaved ? "Saved to your library" : "Removed from saved songs"
        guard isSaved, settings.personalizationEnabled else { return }
        Task {
            _ = try? await app.api.sendFeedback(
                FeedbackRequest(trackId: track.id, rating: .save, artist: track.artist))
        }
    }

    private func add(_ track: Track, to playlist: PlaylistEntity) {
        app.library.add(track, to: playlist)
        app.playlistChanged(playlist)
        Haptics.success(enabled: settings.hapticsEnabled)
        toast = "Added to \(playlist.name)"
    }
}
