import SwiftUI

/// An album: the cover on its own colors, Play and Shuffle, then the tracks in album order.
struct AlbumView: View {
    var route: AlbumRoute

    @Environment(AppModel.self) private var app
    @Environment(PlayerController.self) private var player
    @State private var loader: PageLoader<AlbumPage>?
    @State private var palette: ArtworkPalette = .halo

    var body: some View {
        Group {
            switch loader?.phase {
            case .none, .loading:
                ScrollView {
                    VStack(spacing: Spacing.lg) {
                        SkeletonBlock(height: 220, cornerRadius: Radius.large).frame(width: 220)
                        SkeletonRail(style: .rows, count: 6)
                    }
                    .padding(Spacing.md)
                }
            case let .failed(error):
                ErrorStateView(error: error) { Task { await loader?.load() } }
            case let .loaded(page):
                content(page)
            }
        }
        .background {
            AmbientBackground(palette: palette, artworkURL: loader?.page?.largeArtworkURL)
                .ignoresSafeArea()
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(loader?.page?.title ?? route.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.id) {
            if loader == nil { loader = .album(route.id, api: app.api) }
            await loader?.load()
            if let page = loader?.page {
                var found: ArtworkPalette?
                if let url = page.largeArtworkURL {
                    found = await ArtworkPipeline.shared.palette(for: url)
                }
                palette = found ?? .fallback(seed: page.artist)
            }
        }
    }

    private func content(_ page: AlbumPage) -> some View {
        ScrollView {
            VStack(spacing: Spacing.lg) {
                header(page)
                actions(page)
                tracks(page)
                footer(page)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.bottom, Spacing.xl)
        }
        .refreshable { await loader?.load() }
    }

    private func header(_ page: AlbumPage) -> some View {
        VStack(spacing: Spacing.sm) {
            HaloArtwork(url: page.largeArtworkURL, size: 230, cornerRadius: Radius.large)
                .shadow(color: .black.opacity(0.4), radius: 24, y: 12)
                .padding(.top, Spacing.md)
            Text(page.title).font(HaloFont.title).foregroundStyle(HaloColor.text)
                .multilineTextAlignment(.center)
            if let artistID = page.artistId {
                NavigationLink(value: ArtistRoute(id: artistID, name: page.artist)) {
                    Text(page.artist).font(.headline).foregroundStyle(palette.color(\.accent))
                }
                .accessibilityHint("Opens the artist")
            } else {
                Text(page.artist).font(.headline).foregroundStyle(HaloColor.text.opacity(0.75))
            }
            Text(details(page)).font(HaloFont.meta).foregroundStyle(HaloColor.text.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }

    private func details(_ page: AlbumPage) -> String {
        var parts: [String] = []
        if let year = page.year { parts.append(year) }
        parts.append(page.tracks.count == 1 ? "1 song" : "\(page.tracks.count) songs")
        if page.totalSeconds > 0 { parts.append(DurationFormatter.approximate(page.totalSeconds)) }
        return parts.joined(separator: " · ")
    }

    private func actions(_ page: AlbumPage) -> some View {
        HStack(spacing: Spacing.sm) {
            PlayButton(tracks: page.tracks, context: page.title)
            Button {
                player.play(page.tracks.shuffled(), from: page.title)
            } label: {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonButtonStyle(prominent: false))
            .disabled(page.tracks.isEmpty)
        }
    }

    private func tracks(_ page: AlbumPage) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(page.tracks.enumerated()), id: \.element.id) { index, track in
                Button {
                    player.play(page.tracks, startAt: index, from: page.title)
                } label: {
                    row(track, number: index + 1)
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { player.playNext(track) } label: {
                        Label("Play next", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    Button { player.addToQueue([track]) } label: {
                        Label("Add to queue", systemImage: "text.append")
                    }
                }
                if index < page.tracks.count - 1 { Divider().overlay(HaloColor.separator) }
            }
        }
        .padding(.vertical, Spacing.xs)
        .haloGlass(cornerRadius: Radius.medium, tint: palette.color(\.glow))
    }

    private func row(_ track: Track, number: Int) -> some View {
        let isCurrent = player.currentTrack?.id == track.id
        return HStack(spacing: Spacing.sm) {
            ZStack {
                if isCurrent && player.isPlaying {
                    Image(systemName: "waveform")
                        .symbolEffect(.variableColor.iterative, isActive: player.phase == .playing)
                        .foregroundStyle(palette.color(\.accent))
                } else {
                    Text("\(number)").font(.subheadline.monospacedDigit())
                        .foregroundStyle(HaloColor.text.opacity(0.55))
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(track.title).font(.body.weight(isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? palette.color(\.accent) : HaloColor.text)
                    .lineLimit(1)
                if track.artist != loader?.page?.artist {
                    Text(track.artist).font(.caption).foregroundStyle(HaloColor.mutedText).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Text(DurationFormatter.clock(track.durationSeconds))
                .font(.caption.monospacedDigit()).foregroundStyle(HaloColor.text.opacity(0.55))
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Plays from this song")
    }

    @ViewBuilder
    private func footer(_ page: AlbumPage) -> some View {
        VStack(spacing: Spacing.xs) {
            if let license = page.tracks.first?.license {
                if let url = license.url.flatMap(Track.webURL) {
                    Link("\(license.name) · \(page.artist)", destination: url)
                } else {
                    Text("\(license.name) · \(page.artist)")
                }
            }
            if let url = page.externalURL {
                Link("View on \(page.attribution.label)", destination: url)
            }
        }
        .font(.caption)
        .tint(HaloColor.text.opacity(0.7))
        .foregroundStyle(HaloColor.text.opacity(0.6))
    }
}
