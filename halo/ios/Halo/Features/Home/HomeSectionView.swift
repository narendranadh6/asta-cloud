import SwiftUI

/// Draws one server-provided Home section. The server picks the section and its layout;
/// this view only decides how each layout looks. Local sections are drawn by HomeView.
struct HomeSectionView: View {
    var section: HomeSection

    var body: some View {
        Rail(title: section.title, eyebrow: section.eyebrow) {
            content
            if let source = section.source {
                Text("Source: \(source)")
                    .font(.caption2).foregroundStyle(HaloColor.mutedText)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch section.layout {
        case .tiles where section.type == "moods": moodGrid
        case .tiles: tileRail
        case .rail: cardRail(size: ArtSize.card)
        case .featureRail: cardRail(size: ArtSize.feature)
        case .artistRail: artistRail
        case .rows: rows
        case .local, .unknown: EmptyView()
        }
    }

    private var moodGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 3),
                  spacing: Spacing.md) {
            ForEach(section.items) { item in
                HomeItemLink(item: item) {
                    let mood = Mood(rawValue: item.id) ?? .happy
                    ArtTile(gradient: HaloColor.moodGradient(mood), symbol: mood.symbol,
                            title: item.title, subtitle: item.subtitle, height: 96)
                }
            }
        }
    }

    private var tileRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    HomeItemLink(item: item) {
                        ArtTile(gradient: GenreArt.gradient(GenreArt.all[index % GenreArt.all.count].colors),
                                symbol: tileSymbol, title: item.title, subtitle: item.subtitle, height: 84)
                            .frame(width: 150)
                    }
                }
            }
        }
    }

    private var tileSymbol: String {
        switch section.type {
        case "soundtracks": "film"
        case "languages": "character.bubble"
        default: "music.note"
        }
    }

    private func cardRail(size: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.sm) {
                ForEach(section.items) { item in
                    HomeItemLink(item: item) {
                        if let track = item.track {
                            TrackCard(track: track, width: size)
                        } else {
                            ArtworkCard(title: item.title, subtitle: item.subtitle,
                                        artworkURL: item.artworkURL, size: size, badge: item.badge)
                        }
                    }
                }
            }
        }
    }

    private var artistRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ForEach(section.items) { item in
                    HomeItemLink(item: item) {
                        ArtistBubble(name: item.title, artworkURL: item.artworkURL)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var rows: some View {
        VStack(spacing: Spacing.xs) {
            ForEach(section.items) { item in
                HomeItemLink(item: item) {
                    HStack(spacing: Spacing.md) {
                        if let badge = item.badge {
                            Text(badge).font(.headline.monospacedDigit())
                                .foregroundStyle(HaloColor.primary)
                                .frame(minWidth: 32)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(.subheadline.weight(.semibold))
                                .foregroundStyle(HaloColor.text).lineLimit(1)
                            if let subtitle = item.subtitle {
                                Text(subtitle).font(.caption).foregroundStyle(HaloColor.mutedText)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "magnifyingglass").font(.caption)
                            .foregroundStyle(HaloColor.mutedText)
                    }
                    .padding(Spacing.sm)
                    .haloCard(cornerRadius: Radius.medium)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Where a Home item goes when tapped: a verified YouTube track opens Song Details, a mood
/// opens its hub, anything else runs a search (playback stays a Brave hand-off).
struct HomeItemLink<Label: View>: View {
    var item: HomeItem
    @ViewBuilder var label: () -> Label

    var body: some View {
        Group {
            if let track = item.track {
                NavigationLink(value: track, label: label)
            } else if item.kind == .mood, let mood = Mood(rawValue: item.id) {
                NavigationLink(value: MoodRoute(mood: mood), label: label)
            } else if let query = item.query {
                NavigationLink(
                    value: SearchRoute(query: query, kind: item.kind == .artist ? .artist : .song,
                                       title: item.title),
                    label: label)
            } else {
                label()
            }
        }
        .buttonStyle(.plain)
    }
}
