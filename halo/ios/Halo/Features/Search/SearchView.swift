import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @Environment(PlayerController.self) private var player
    @State private var model = SearchViewModel()
    @State private var trending: [Track] = []
    @Query(sort: \RecentSearchEntity.searchedAt, order: .reverse) private var recent: [RecentSearchEntity]

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                ChipBar(options: SearchKind.allCases, selection: $model.kind) { $0.label }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if case .idle = model.phase {
                idleContent
            } else {
                SearchResultsSection(model: model)
            }
        }
        .listStyle(.plain)
        .haloScreen()
        .navigationTitle("Search")
        .searchable(text: $model.query, prompt: "Songs, artists, remixes, live sets") {
            ForEach(model.suggestions, id: \.self) { suggestion in
                Label(suggestion, systemImage: "magnifyingglass").searchCompletion(suggestion)
            }
        }
        .onSubmit(of: .search) { submit() }
        .onChange(of: model.kind) { _, _ in
            if model.lastSubmitted != nil { submit() }
        }
        .task(id: model.query) { await model.refreshSuggestions(api: app.api) }
        .task {
            if trending.isEmpty, let response = try? await app.api.trending(genre: nil, limit: 5) {
                trending = response.items
            }
        }
        .haloDestinations()
    }

    private func submit() {
        Task {
            await model.submit(api: app.api) { query, kind in
                app.library.recordSearch(query, kind: kind)
            }
        }
    }

    private func suggestion(_ title: String, _ subtitle: String, _ symbol: String,
                            _ route: SearchRoute) -> some View {
        NavigationLink(value: route) { suggestionLabel(title, subtitle, symbol) }
            .listRowBackground(Color.clear)
    }

    private func suggestionLabel(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(HaloColor.neon))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(HaloColor.text)
                Text(subtitle).font(.caption).foregroundStyle(HaloColor.mutedText)
            }
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        Section {
            SearchSetupBanner().listRowBackground(Color.clear)
        }
        if !trending.isEmpty {
            Section {
                ForEach(Array(trending.enumerated()), id: \.element.id) { index, track in
                    NavigationLink(value: track) {
                        TrackRow(track: track) { player.play(trending, startAt: index) }
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                HStack {
                    Text("Trending this week").font(HaloFont.section).foregroundStyle(HaloColor.text)
                        .textCase(nil)
                    Spacer()
                    NavigationLink("See all") { DiscoverView() }.font(.subheadline.weight(.semibold))
                        .textCase(nil)
                }
            }
        }
        Section {
            suggestion("Telugu hits", "Popular songs", "music.note.list",
                       SearchRoute(query: "Telugu hit songs", kind: .song, title: "Telugu hits"))
            NavigationLink(value: StudioRoute(mood: nil, description: "Underrated songs similar to my favorites")) {
                suggestionLabel("Underrated gems", "Based on your taste", "diamond")
            }
            .listRowBackground(Color.clear)
            NavigationLink(value: StudioRoute(mood: nil, description: "Songs similar to my favorite artists")) {
                suggestionLabel("Similar to your favorites", "AI-powered discovery", "heart.circle")
            }
            .listRowBackground(Color.clear)
        } header: {
            Text("AI suggestions for you").font(HaloFont.section).foregroundStyle(HaloColor.text)
                .textCase(nil)
        }
        if !recent.isEmpty {
            Section {
                ForEach(recent.prefix(10)) { entry in
                    Button {
                        model.query = entry.query
                        model.kind = SearchKind(rawValue: entry.kindRaw) ?? .song
                        submit()
                    } label: {
                        Label(entry.query, systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(HaloColor.text)
                    }
                    .listRowBackground(Color.clear)
                }
            } header: {
                HStack {
                    Text("Recent searches")
                    Spacer()
                    Button("Clear") { app.library.clearRecentSearches() }
                        .font(.caption.weight(.semibold))
                }
            }
        } else {
            Section {
                ContentUnavailableView(
                    "Find your next favorite",
                    systemImage: "music.magnifyingglass",
                    description: Text("Search free full songs from Audius and Jamendo, plus "
                                      + "30-second previews. Every result shows its source."))
                .listRowBackground(Color.clear)
            }
        }
    }
}

/// Results list with loading, empty, error and pagination states.
struct SearchResultsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerController.self) private var player
    var model: SearchViewModel

    /// Results honouring the "include previews" setting.
    private var visible: [Track] {
        settings.includePreviews ? model.results : model.results.filter { !$0.isPreview }
    }

    var body: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .loading:
            LoadingStateView(message: "Searching…").listRowBackground(Color.clear)
        case .empty:
            ContentUnavailableView.search(text: model.lastSubmitted?.query ?? model.query)
                .listRowBackground(Color.clear)
        case let .failed(error):
            ErrorStateView(error: error) { Task { await model.retry(api: app.api) } }
                .listRowBackground(Color.clear)
        case .loaded:
            Section {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, track in
                    NavigationLink(value: track) {
                        TrackRow(track: track) { player.play(visible, startAt: index) }
                    }
                    .listRowBackground(Color.clear)
                    .task {
                        if model.shouldLoadMore(after: track) { await model.loadMore(api: app.api) }
                    }
                }
                footer.listRowBackground(Color.clear)
            } footer: {
                attribution
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            ProgressView().frame(maxWidth: .infinity)
        } else if model.loadMoreError != nil {
            Button("Couldn't load more. Tap to retry.") {
                Task { await model.loadMore(api: app.api) }
            }
            .frame(maxWidth: .infinity)
        } else if model.canLoadMore {
            Button("Load more") { Task { await model.loadMore(api: app.api) } }
                .frame(maxWidth: .infinity)
        }
    }

    private var attributionText: String {
        let full = model.sources.filter { $0 != "itunes" }.map(\.capitalized)
        let fullText = full.isEmpty ? "" : "Full songs from \(full.joined(separator: " and ")). "
        let previews = model.sources.contains("itunes") ? "Previews courtesy of Apple Music." : ""
        return fullText + previews
    }

    private var attribution: some View {
        Text(attributionText)
            .font(.caption2)
            .foregroundStyle(HaloColor.mutedText)
    }
}

/// Standalone results page (artists, recent searches, moods).
struct SearchResultsScreen: View {
    @Environment(AppModel.self) private var app
    var query: String
    var kind: SearchKind
    var title: String
    @State private var model = SearchViewModel()

    var body: some View {
        List { SearchResultsSection(model: model) }
            .listStyle(.plain)
            .haloScreen()
            .navigationTitle(title)
            .task {
                guard model.lastSubmitted == nil else { return }
                model.query = query
                model.kind = kind
                await model.submit(api: app.api)
            }
            .refreshable { await model.submit(api: app.api) }
    }
}
