import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var model = DiscoverViewModel()

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                ChipBar(options: DiscoverViewModel.Filter.allCases, selection: $model.filter) { $0.rawValue }
                SearchSetupBanner()
                if model.filter == .all {
                    featured
                    NavigationLink { RadioView() } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.title2).foregroundStyle(.white)
                                .frame(width: 52, height: 52)
                                .background(RoundedRectangle(cornerRadius: 12).fill(HaloColor.cool))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live Radio").font(HaloFont.headline).foregroundStyle(HaloColor.text)
                                Text("Thousands of stations, playing right now")
                                    .font(.caption).foregroundStyle(HaloColor.mutedText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(HaloColor.mutedText)
                        }
                        .padding(Spacing.sm)
                        .haloCard()
                    }
                    .buttonStyle(.plain)
                }
                if model.filter.showsOpenData { freshReleasesShelf }
                ForEach(model.visibleShelves) { shelf in
                    shelfView(shelf)
                }
                if model.filter.showsOpenData { mostListenedShelf }
                if model.filter == .all { genres }
            }
            .padding(Spacing.md)
        }
        .haloScreen()
        .navigationTitle("Discover")
        .task { await model.load(api: app.api, language: settings.preferredLanguage) }
        .refreshable { await model.load(api: app.api, language: settings.preferredLanguage) }
    }

    private var featured: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Featured this week")
            HStack(spacing: Spacing.sm) {
                Button { model.filter = .trending } label: {
                    ArtTile(gradient: HaloColor.neon, symbol: "chart.line.uptrend.xyaxis",
                            title: "Top on YouTube", subtitle: "Most popular music")
                }
                Button { model.filter = .live } label: {
                    ArtTile(gradient: HaloColor.moodGradient(.energetic), symbol: "music.mic",
                            title: "Live", subtitle: "Concerts & sessions")
                }
                Button { model.filter = .remixes } label: {
                    ArtTile(gradient: HaloColor.cool, symbol: "dial.high",
                            title: "Remixes", subtitle: "Fresh edits")
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func shelfView(_ shelf: DiscoverViewModel.Shelf) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: shelf.rawValue)
            switch model.shelves[shelf] {
            case .none, .loading:
                SkeletonRail(style: .card)
            case let .failed(error):
                ErrorStateView(error: error) {
                    Task { await model.load(api: app.api, language: settings.preferredLanguage) }
                }
            case let .loaded(tracks) where tracks.isEmpty:
                Text("Nothing here right now.").font(.subheadline).foregroundStyle(HaloColor.mutedText)
            case let .loaded(tracks):
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: Spacing.sm) {
                        ForEach(tracks) { track in
                            NavigationLink(value: track) { TrackCard(track: track) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if shelf == .trending {
                    Text("Source: YouTube most popular music chart.")
                        .font(.caption2).foregroundStyle(HaloColor.mutedText)
                }
            }
        }
    }

    // MARK: ListenBrainz shelves

    @ViewBuilder
    private var freshReleasesShelf: some View {
        openDataShelf(title: "Fresh releases", eyebrow: "From ListenBrainz",
                      state: model.freshReleases, skeleton: .feature) { releases in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(releases) { release in
                        NavigationLink(value: SearchRoute(
                            query: release.searchQuery, kind: .song, title: release.releaseName)) {
                            FreshReleaseCard(release: release)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Text("Source: ListenBrainz fresh releases. Cover art: Cover Art Archive. "
                 + "Tap to find it on YouTube.")
                .font(.caption2).foregroundStyle(HaloColor.mutedText)
        }
    }

    @ViewBuilder
    private var mostListenedShelf: some View {
        openDataShelf(title: "Most listened this week", eyebrow: "Open listening data",
                      state: model.mostListened, skeleton: .rows) { recordings in
            VStack(spacing: Spacing.xs) {
                ForEach(Array(recordings.enumerated()), id: \.element.id) { index, recording in
                    NavigationLink(value: SearchRoute(
                        query: recording.searchQuery, kind: .song, title: recording.title)) {
                        ChartRow(rank: index + 1, recording: recording)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text("Source: ListenBrainz listening statistics (open data).")
                .font(.caption2).foregroundStyle(HaloColor.mutedText)
        }
    }

    /// A ListenBrainz shelf. Hidden entirely when the server has ListenBrainz switched off.
    @ViewBuilder
    private func openDataShelf<Value: Collection, Content: View>(
        title: String, eyebrow: String? = nil, state: DiscoverViewModel.OpenDataState<Value>,
        skeleton: SkeletonRail.Style,
        @ViewBuilder content: @escaping (Value) -> Content
    ) -> some View {
        switch state {
        case .disabled:
            EmptyView()
        case .loading:
            Rail(title: title, eyebrow: eyebrow) { SkeletonRail(style: skeleton) }
        case let .failed(error):
            VStack(alignment: .leading, spacing: Spacing.sm) {
                SectionHeader(title: title)
                ErrorStateView(error: error) {
                    Task { await model.load(api: app.api, language: settings.preferredLanguage) }
                }
            }
        case let .loaded(value) where value.isEmpty:
            EmptyView()
        case let .loaded(value):
            Rail(title: title, eyebrow: eyebrow) { content(value) }
        }
    }

    private var genres: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Explore by genre")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: Spacing.sm)], spacing: Spacing.sm) {
                ForEach(GenreArt.all, id: \.name) { genre in
                    NavigationLink(value: SearchRoute(
                        query: [settings.preferredLanguage, genre.name, "songs"].compactMap { $0 }
                            .joined(separator: " "),
                        kind: .song, title: genre.name)) {
                        ArtTile(gradient: GenreArt.gradient(genre.colors), symbol: genre.symbol,
                                title: genre.name, height: 72)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Large artwork card used in horizontal shelves.
struct TrackCard: View {
    var track: any TrackDisplayable
    var width: CGFloat = ArtSize.card

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ArtworkView(url: track.artworkURL, size: width, cornerRadius: Spacing.corner)
                .overlay(alignment: .topLeading) {
                    AttributionBadge().padding(6)
                }
            Text(track.title).font(.subheadline.weight(.semibold))
                .foregroundStyle(HaloColor.text).lineLimit(2)
            Text(track.channelTitle).font(.caption).foregroundStyle(HaloColor.mutedText).lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A new release from ListenBrainz, with Cover Art Archive artwork when there is some.
struct FreshReleaseCard: View {
    var release: FreshRelease

    var body: some View {
        ArtworkCard(
            title: release.releaseName, subtitle: "\(release.artistName) · \(release.releaseDate)",
            artworkURL: release.coverArtURL, size: ArtSize.feature, badge: release.releaseType)
            .accessibilityHint("Finds this release on YouTube")
    }
}

/// A row in the ListenBrainz most-listened chart.
struct ChartRow: View {
    var rank: Int
    var recording: PopularRecording

    var body: some View {
        HStack(spacing: Spacing.md) {
            Text("\(rank)").font(.headline.monospacedDigit())
                .foregroundStyle(rank <= 3 ? HaloColor.primary : HaloColor.mutedText)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(recording.title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(HaloColor.text).lineLimit(1)
                Text(recording.artistName).font(.caption).foregroundStyle(HaloColor.mutedText).lineLimit(1)
            }
            Spacer()
            Text("\(recording.listenCount.formatted(.number.notation(.compactName))) plays")
                .font(.caption2).foregroundStyle(HaloColor.mutedText)
            Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(HaloColor.mutedText)
        }
        .padding(Spacing.sm)
        .haloCard()
        .accessibilityElement(children: .combine)
    }
}
