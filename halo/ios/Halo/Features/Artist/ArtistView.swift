import SwiftUI

/// An artist at their source: header image, Play and Shuffle, most-played songs, albums,
/// and their own words. Every song plays in Halo.
struct ArtistView: View {
    var route: ArtistRoute

    @Environment(AppModel.self) private var app
    @Environment(PlayerController.self) private var player
    @State private var loader: PageLoader<ArtistPage>?
    @State private var showsAllSongs = false

    var body: some View {
        Group {
            switch loader?.phase {
            case .none, .loading:
                loading
            case let .failed(error):
                ErrorStateView(error: error) { Task { await loader?.load() } }
            case let .loaded(page):
                content(page)
            }
        }
        .haloScreen()
        .navigationTitle(loader?.page?.name ?? route.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: route.id) {
            if loader == nil { loader = .artist(route.id, api: app.api) }
            await loader?.load()
        }
    }

    private var loading: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SkeletonBlock(height: 220, cornerRadius: 0)
                SkeletonRail(style: .rows, count: 5).padding(.horizontal, Spacing.md)
            }
        }
    }

    private func content(_ page: ArtistPage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header(page)
                actions(page).padding(.horizontal, Spacing.md)
                if !page.topTracks.isEmpty { popular(page) }
                if !page.albums.isEmpty { albums(page) }
                about(page).padding(.horizontal, Spacing.md)
            }
            .padding(.bottom, Spacing.xl)
        }
        .refreshable { await loader?.load() }
    }

    private func header(_ page: ArtistPage) -> some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
                .frame(height: 240)
                .overlay {
                    HaloArtwork(url: page.coverURL ?? page.artworkURL, size: nil, cornerRadius: 0,
                                maxPointSize: 600)
                        .scaledToFill()
                }
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, HaloColor.background],
                                   startPoint: .center, endPoint: .bottom)
                }
            HStack(alignment: .bottom, spacing: Spacing.md) {
                if page.coverURL != nil, page.artworkURL != nil {
                    HaloArtwork(url: page.artworkURL, size: 72, cornerRadius: 36)
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(page.name).font(HaloFont.display).foregroundStyle(HaloColor.text)
                        .lineLimit(2).minimumScaleFactor(0.7)
                    Text(subtitle(page)).font(HaloFont.meta).foregroundStyle(HaloColor.mutedText)
                }
            }
            .padding(Spacing.md)
        }
        .accessibilityElement(children: .combine)
    }

    private func subtitle(_ page: ArtistPage) -> String {
        var parts = [page.source.label]
        if let followers = page.followerCount, followers > 0 {
            parts.append("\(followers.formatted(.number.notation(.compactName))) followers")
        }
        return parts.joined(separator: " · ")
    }

    private func actions(_ page: ArtistPage) -> some View {
        HStack(spacing: Spacing.sm) {
            PlayButton(tracks: page.topTracks, context: page.name)
            Button {
                player.play(page.topTracks.shuffled(), from: page.name)
            } label: {
                Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonButtonStyle(prominent: false))
            .disabled(page.topTracks.isEmpty)
        }
    }

    private func popular(_ page: ArtistPage) -> some View {
        let shown = showsAllSongs ? page.topTracks : Array(page.topTracks.prefix(5))
        return VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Popular",
                          actionTitle: page.topTracks.count > 5 ? (showsAllSongs ? "Less" : "See all") : nil) {
                withAnimation(HaloMotion.standard) { showsAllSongs.toggle() }
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, track in
                NavigationLink(value: track) {
                    TrackRow(track: track, showsAttribution: false) {
                        player.play(page.topTracks, startAt: index, from: page.name)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Spacing.md)
    }

    private func albums(_ page: ArtistPage) -> some View {
        Rail(title: "Albums") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(page.albums) { album in
                        NavigationLink(value: AlbumRoute(id: album.id, title: album.title)) {
                            ArtworkCard(title: album.title, subtitle: album.year,
                                        artworkURL: album.artworkURL)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.md)
            }
        }
    }

    @ViewBuilder
    private func about(_ page: ArtistPage) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            if let bio = page.bio {
                SectionHeader(title: "About")
                Text(bio).font(.body).foregroundStyle(HaloColor.mutedText)
            }
            if let url = page.externalURL {
                Link(destination: url) {
                    Label("\(page.name) on \(page.attribution.label)", systemImage: "arrow.up.right.square")
                        .font(.footnote.weight(.semibold))
                }
                .tint(HaloColor.accent)
            }
        }
    }
}
