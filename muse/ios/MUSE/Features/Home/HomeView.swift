import SwiftData
import SwiftUI

struct HomeView: View {
    var selectTab: (AppTab) -> Void

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Query(filter: #Predicate<TrackEntity> { $0.isAvailable },
           sort: \TrackEntity.lastViewedAt, order: .reverse)
    private var discovered: [TrackEntity]
    @Query(sort: \PlaylistEntity.updatedAt, order: .reverse) private var playlists: [PlaylistEntity]
    @Query(sort: \RecentSearchEntity.searchedAt, order: .reverse) private var recentSearches: [RecentSearchEntity]
    @Query(filter: #Predicate<ArtistEntity> { !$0.isExcluded }, sort: \ArtistEntity.addedAt)
    private var favoriteArtists: [ArtistEntity]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                greeting
                DemoModeBanner()
                aiDJCard
                moodShortcuts
                if !discovered.isEmpty { recentlyDiscovered }
                if !playlists.isEmpty { savedPlaylists }
                if !recommendedArtists.isEmpty { artists }
                if !recentSearches.isEmpty { continueExploring }
                if discovered.isEmpty && playlists.isEmpty { firstRun }
            }
            .padding(Spacing.md)
        }
        .museScreen()
        .navigationTitle("MUSE")
        .navigationBarTitleDisplayMode(.inline)
        .museDestinations()
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(greetingText)
                .font(MUSEFont.hero)
                .foregroundStyle(MUSEColor.text)
            Text(settings.activeMood.map { "In a \($0.label.lowercased()) mood" }
                 ?? "What do you want to hear?")
                .font(.subheadline)
                .foregroundStyle(MUSEColor.mutedText)
        }
        .accessibilityElement(children: .combine)
    }

    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let base = switch hour {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<22: "Good evening"
        default: "Late night"
        }
        let name = settings.displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? base : "\(base), \(name)"
    }

    private var aiDJCard: some View {
        Button { selectTab(.dj) } label: {
            HStack(spacing: Spacing.md) {
                Image(systemName: "sparkles")
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(MUSEColor.neon))
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI DJ").font(MUSEFont.title).foregroundStyle(MUSEColor.text)
                    Text("Describe a vibe and get a playlist of real, verified songs.")
                        .font(.subheadline)
                        .foregroundStyle(MUSEColor.mutedText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(MUSEColor.mutedText)
            }
            .padding(Spacing.md)
            .museCard(cornerRadius: Spacing.cornerLarge)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the AI DJ tab")
    }

    private var moodShortcuts: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Moods")
                    .font(MUSEFont.section)
                    .foregroundStyle(MUSEColor.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                NavigationLink("Mood Hub") { MoodHubView() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MUSEColor.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(Mood.allCases) { mood in
                        NavigationLink(value: MoodRoute(mood: mood)) {
                            Label(mood.label, systemImage: mood.symbol)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, Spacing.md)
                                .frame(minHeight: 44)
                                .background(Capsule().fill(MUSEColor.moodGradient(mood)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var recentlyDiscovered: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Recently discovered")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(discovered.prefix(12)) { entity in
                        NavigationLink(value: Track(entity: entity)) {
                            VStack(alignment: .leading, spacing: 6) {
                                ArtworkView(url: entity.artworkURL, size: 140, cornerRadius: Spacing.corner)
                                Text(entity.title).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(MUSEColor.text).lineLimit(2)
                                Text(entity.channelTitle).font(.caption)
                                    .foregroundStyle(MUSEColor.mutedText).lineLimit(1)
                            }
                            .frame(width: 140, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var savedPlaylists: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Your playlists")
            ForEach(playlists.prefix(4)) { playlist in
                NavigationLink(value: playlist) {
                    PlaylistRow(playlist: playlist)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Explicit favorites first, then channels the user saved most — MUSE activity only.
    private var recommendedArtists: [String] {
        var names = favoriteArtists.map(\.name)
        let counts = Dictionary(grouping: discovered.filter(\.isSaved), by: \.channelTitle)
            .mapValues(\.count)
            .sorted { $0.value > $1.value }
        for (name, _) in counts where !names.contains(name) && !name.isEmpty {
            names.append(name)
        }
        return Array(names.prefix(10))
    }

    private var artists: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Artists for you")
            Text("Based on favorites and saves in MUSE")
                .font(.caption).foregroundStyle(MUSEColor.mutedText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.xs) {
                    ForEach(recommendedArtists, id: \.self) { name in
                        NavigationLink(value: SearchRoute(query: name, kind: .artist, title: name)) {
                            Label(name, systemImage: "music.mic")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(MUSEColor.text)
                                .padding(.horizontal, Spacing.md)
                                .frame(minHeight: 44)
                                .museCard(cornerRadius: 22)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var continueExploring: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Continue exploring")
            FlowLayout {
                ForEach(recentSearches.prefix(8)) { entry in
                    NavigationLink(value: SearchRoute(
                        query: entry.query, kind: SearchKind(rawValue: entry.kindRaw) ?? .song,
                        title: entry.query)) {
                        Label(entry.query, systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(MUSEColor.text)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(MUSEColor.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var firstRun: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Start exploring")
                .font(MUSEFont.section).foregroundStyle(MUSEColor.text)
            Text("Search for a song or ask the AI DJ. Songs you open and save shape this page — "
                 + "MUSE only learns from what you do here.")
                .font(.subheadline).foregroundStyle(MUSEColor.mutedText)
            Button("Search music") { selectTab(.search) }
                .buttonStyle(NeonButtonStyle(prominent: false))
        }
        .padding(Spacing.md)
        .museCard()
    }
}

struct PlaylistRow: View {
    var playlist: PlaylistEntity

    var body: some View {
        HStack(spacing: Spacing.sm) {
            ArtworkView(url: playlist.artworkURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(playlist.name).font(MUSEFont.headline).foregroundStyle(MUSEColor.text)
                        .lineLimit(1)
                    if playlist.isAIGenerated {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(MUSEColor.secondary)
                            .accessibilityLabel("AI generated")
                    }
                }
                Text("\(playlist.items.count) songs · \(DurationFormatter.approximate(playlist.totalDurationSeconds))")
                    .font(.subheadline).foregroundStyle(MUSEColor.mutedText)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(MUSEColor.mutedText)
        }
        .padding(Spacing.sm)
        .museCard()
        .accessibilityElement(children: .combine)
    }
}
