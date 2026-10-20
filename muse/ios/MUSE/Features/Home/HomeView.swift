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

    @State private var trending: [Track] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                quickChips
                SearchSetupBanner()
                hero
                playSomethingFor
                if !discovered.isEmpty { recentlyDiscovered }
                if !trending.isEmpty { trendingShelf }
                if !playlists.isEmpty { savedPlaylists }
                if !recommendedArtists.isEmpty { artists }
                if !recentSearches.isEmpty { continueExploring }
                if discovered.isEmpty && playlists.isEmpty { firstRun }
            }
            .padding(Spacing.md)
        }
        .museScreen()
        .toolbar(.hidden, for: .navigationBar)
        .museDestinations()
        .task {
            if trending.isEmpty, let response = try? await app.api.trending(pageToken: nil, limit: 10) {
                trending = response.items
            }
        }
    }

    private var header: some View {
        HStack {
            Text("MUSE")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(MUSEColor.neon)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { selectTab(.settings) } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(MUSEColor.mutedText)
            }
            .accessibilityLabel("Profile and settings")
        }
    }

    private var quickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                Chip(title: "For You", isSelected: true) {}
                Chip(title: "AI DJ", systemImage: "sparkles", isSelected: false) { selectTab(.dj) }
                NavigationLink(value: MoodRoute(mood: .calm)) { chipLabel("Chill") }
                NavigationLink(value: MoodRoute(mood: .workout)) { chipLabel("Workout") }
                NavigationLink(value: MoodRoute(mood: .focused)) { chipLabel("Focus") }
                NavigationLink { DiscoverView() } label: { chipLabel("Discover") }
                NavigationLink { RadioView() } label: { chipLabel("Live Radio") }
            }
        }
        .buttonStyle(.plain)
    }

    private func chipLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(MUSEColor.text)
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: 36)
            .background(Capsule().fill(MUSEColor.surface))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }

    private var hero: some View {
        Button {
            app.pendingDJPrompt = heroPrompt
            selectTab(.dj)
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: Spacing.cornerLarge, style: .continuous)
                    .fill(LinearGradient(
                        colors: [MUSEColor.secondary.opacity(0.9), MUSEColor.primary.opacity(0.85),
                                 MUSEColor.gold.opacity(0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                AIOrb(size: 120)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(Spacing.md)
                    .opacity(0.9)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(greetingText)
                        .font(MUSEFont.title)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.leading)
                    Text(settings.activeMood.map { "Let's keep the \($0.label.lowercased()) vibe going" }
                         ?? "Let's get you in the right vibe")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(Spacing.md)
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(Spacing.md)
            }
            .frame(height: 190)
            .shadow(color: MUSEColor.primary.opacity(0.4), radius: 20, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(greetingText). Ask the AI DJ for a mix")
    }

    private var heroPrompt: String {
        let mood = settings.activeMood?.discoveryPrompt ?? {
            let hour = Calendar.current.component(.hour, from: .now)
            return hour >= 22 || hour < 5 ? "mellow late night songs" : "songs for right now"
        }()
        return [settings.preferredLanguage, mood].compactMap { $0 }.joined(separator: " ")
    }

    private var playSomethingFor: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Play something for…")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.sm), count: 3),
                      spacing: Spacing.md) {
                ForEach(Self.tiles, id: \.title) { tile in
                    NavigationLink(value: MoodRoute(mood: tile.mood)) {
                        ArtTile(gradient: MUSEColor.moodGradient(tile.mood), symbol: tile.mood.symbol,
                                title: tile.title, subtitle: tile.subtitle, height: 96)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private static let tiles: [(title: String, subtitle: String, mood: Mood)] = [
        ("Focus", "Deep work", .focused), ("Chill", "Relax & unwind", .calm),
        ("Workout", "High energy", .workout), ("Late Night", "Mellow beats", .sleep),
        ("Feel Good", "Positive vibes", .happy), ("Travel", "Explore the world", .travel),
    ]

    private var trendingShelf: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Trending on YouTube").font(MUSEFont.section).foregroundStyle(MUSEColor.text)
                Spacer()
                NavigationLink("See all") { DiscoverView() }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(MUSEColor.accent)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(trending) { track in
                        NavigationLink(value: track) { TrackCard(track: track, width: 130) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
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
        return name.isEmpty ? base : "\(base),\n\(name)"
    }

    private var recentlyDiscovered: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            SectionHeader(title: "Recently discovered")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    ForEach(discovered.prefix(12)) { entity in
                        NavigationLink(value: Track(entity: entity)) { TrackCard(track: entity, width: 140) }
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
