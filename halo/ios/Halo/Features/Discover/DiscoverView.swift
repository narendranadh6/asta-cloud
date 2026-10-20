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
                ForEach(model.visibleShelves) { shelf in
                    shelfView(shelf)
                }
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
                LoadingStateView(message: "Loading \(shelf.rawValue.lowercased())…")
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
    var width: CGFloat = 150

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
