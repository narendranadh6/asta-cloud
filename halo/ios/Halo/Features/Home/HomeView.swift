import SwiftData
import SwiftUI

struct HomeView: View {
    var selectTab: (AppTab) -> Void

    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerController.self) private var player
    @Query(filter: #Predicate<TrackEntity> { $0.isAvailable },
           sort: \TrackEntity.lastViewedAt, order: .reverse)
    private var discovered: [TrackEntity]
    @Query(sort: \PlaylistEntity.updatedAt, order: .reverse) private var playlists: [PlaylistEntity]
    @Query(sort: \RecentSearchEntity.searchedAt, order: .reverse) private var recentSearches: [RecentSearchEntity]

    @State private var model = HomeViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                quickChips
                SearchSetupBanner()
                hero
                if let error = model.lastError, !model.hasLoadedFromServer {
                    feedErrorBanner(error)
                }
                ForEach(model.sections) { section in
                    sectionView(section)
                }
                if discovered.isEmpty && playlists.isEmpty { firstRun }
            }
            .padding(Spacing.md)
        }
        .haloScreen()
        .toolbar(.hidden, for: .navigationBar)
        .haloDestinations()
        .task { await model.loadWithRetry(api: app.api) }
        .refreshable { await model.load(api: app.api) }
    }

    private var header: some View {
        HStack {
            Text("HALO")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(HaloColor.neon)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { selectTab(.settings) } label: {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(HaloColor.mutedText)
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
            .foregroundStyle(HaloColor.text)
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: 36)
            .background(Capsule().fill(HaloColor.surface))
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
                        colors: [HaloColor.secondary.opacity(0.9), HaloColor.primary.opacity(0.85),
                                 HaloColor.gold.opacity(0.75)],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                AIOrb(size: 120)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(Spacing.md)
                    .opacity(0.9)
                VStack(alignment: .leading, spacing: Spacing.xxs) {
                    Text(greetingText)
                        .font(HaloFont.title)
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
            .shadow(color: HaloColor.primary.opacity(0.4), radius: 20, y: 10)
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

    private func recentlyDiscovered(_ section: HomeSection) -> some View {
        Rail(title: section.title, eyebrow: section.eyebrow) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.sm) {
                    let recent = discovered.prefix(12).map(Track.init(entity:))
                    ForEach(Array(recent.enumerated()), id: \.element.id) { index, track in
                        NavigationLink(value: track) {
                            TrackCard(track: track) { player.play(recent, startAt: index, from: section.title) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func savedPlaylists(_ section: HomeSection) -> some View {
        Rail(title: section.title, eyebrow: section.eyebrow) {
            ForEach(playlists.prefix(4)) { playlist in
                NavigationLink(value: playlist) {
                    PlaylistRow(playlist: playlist)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func continueExploring(_ section: HomeSection) -> some View {
        Rail(title: section.title, eyebrow: section.eyebrow) {
            FlowLayout {
                ForEach(recentSearches.prefix(8)) { entry in
                    NavigationLink(value: SearchRoute(
                        query: entry.query, kind: SearchKind(rawValue: entry.kindRaw) ?? .song,
                        title: entry.query)) {
                        Label(entry.query, systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                            .foregroundStyle(HaloColor.text)
                            .padding(.horizontal, Spacing.sm)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(HaloColor.surface))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Shown when the server feed couldn't load; Home falls back to on-device sections.
    private func feedErrorBanner(_ error: Error) -> some View {
        HStack(alignment: .top, spacing: Spacing.sm) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(HaloColor.gold)
            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text("Couldn't load your Home feed").font(HaloFont.headline).foregroundStyle(HaloColor.text)
                Text(error.localizedDescription).font(.caption).foregroundStyle(HaloColor.mutedText)
                Button("Retry") { Task { await model.load(api: app.api) } }
                    .font(.subheadline.weight(.semibold)).tint(HaloColor.accent)
            }
            Spacer(minLength: 0)
        }
        .padding(Spacing.sm)
        .haloCard(cornerRadius: Radius.medium)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func sectionView(_ section: HomeSection) -> some View {
        switch section.layout {
        case .local:
            switch section.type {
            case "recently_discovered" where !discovered.isEmpty: recentlyDiscovered(section)
            case "your_playlists" where !playlists.isEmpty: savedPlaylists(section)
            case "continue_exploring" where !recentSearches.isEmpty: continueExploring(section)
            default: EmptyView()
            }
        default:
            HomeSectionView(section: section)
        }
    }

    private var firstRun: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Start exploring")
                .font(HaloFont.section).foregroundStyle(HaloColor.text)
            Text("Search for a song or ask the AI DJ. Songs you open and save shape this page — "
                 + "Halo only learns from what you do here.")
                .font(.subheadline).foregroundStyle(HaloColor.mutedText)
            Button("Search music") { selectTab(.search) }
                .buttonStyle(NeonButtonStyle(prominent: false))
        }
        .padding(Spacing.md)
        .haloCard()
    }
}

struct PlaylistRow: View {
    var playlist: PlaylistEntity

    var body: some View {
        HStack(spacing: Spacing.sm) {
            HaloArtwork(url: playlist.artworkURL, size: 56)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(playlist.name).font(HaloFont.headline).foregroundStyle(HaloColor.text)
                        .lineLimit(1)
                    if playlist.isAIGenerated {
                        Image(systemName: "sparkles").font(.caption).foregroundStyle(HaloColor.secondary)
                            .accessibilityLabel("AI generated")
                    }
                }
                Text("\(playlist.items.count) songs · \(DurationFormatter.approximate(playlist.totalDurationSeconds))")
                    .font(.subheadline).foregroundStyle(HaloColor.mutedText)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(HaloColor.mutedText)
        }
        .padding(Spacing.sm)
        .haloCard()
        .accessibilityElement(children: .combine)
    }
}
