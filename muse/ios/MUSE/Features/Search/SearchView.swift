import SwiftData
import SwiftUI

struct SearchView: View {
    @Environment(AppModel.self) private var app
    @State private var model = SearchViewModel()
    @Query(sort: \RecentSearchEntity.searchedAt, order: .reverse) private var recent: [RecentSearchEntity]

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Picker("Search for", selection: $model.kind) {
                    ForEach(SearchKind.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }
            if case .idle = model.phase {
                idleContent
            } else {
                SearchResultsSection(model: model)
            }
        }
        .listStyle(.plain)
        .museScreen()
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
        .museDestinations()
    }

    private func submit() {
        Task {
            await model.submit(api: app.api) { query, kind in
                app.library.recordSearch(query, kind: kind)
            }
        }
    }

    @ViewBuilder
    private var idleContent: some View {
        Section {
            DemoModeBanner().listRowBackground(Color.clear)
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
                            .foregroundStyle(MUSEColor.text)
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
                    description: Text("Search YouTube music metadata. Results show their source."))
                .listRowBackground(Color.clear)
            }
        }
    }
}

/// Results list with loading, empty, error and pagination states.
struct SearchResultsSection: View {
    @Environment(AppModel.self) private var app
    var model: SearchViewModel

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
                ForEach(model.results) { track in
                    NavigationLink(value: track) { TrackRow(track: track) }
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

    private var attribution: some View {
        Text(model.provider == .demo
             ? "Demo catalog — fictional results for development."
             : "Results and metadata provided by YouTube.")
            .font(.caption2)
            .foregroundStyle(MUSEColor.mutedText)
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
            .museScreen()
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
