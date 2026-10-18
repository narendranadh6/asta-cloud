import SwiftUI

struct MoodHubView: View {
    @Environment(AppSettings.self) private var settings
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.sm)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("Pick a mood to steer discovery and new playlists.")
                    .font(.subheadline).foregroundStyle(MUSEColor.mutedText)
                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    ForEach(Mood.allCases) { mood in
                        NavigationLink(value: MoodRoute(mood: mood)) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Image(systemName: mood.symbol).font(.title)
                                Spacer(minLength: 0)
                                Text(mood.label).font(MUSEFont.title)
                                if settings.activeMood == mood {
                                    Text("Active").font(.caption.weight(.bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Spacing.corner)
                                .fill(MUSEColor.moodGradient(mood)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(mood.label) mood\(settings.activeMood == mood ? ", active" : "")")
                    }
                }
                if settings.activeMood != nil {
                    Button("Clear active mood") { settings.activeMood = nil }
                        .buttonStyle(NeonButtonStyle(prominent: false))
                }
            }
            .padding(Spacing.md)
        }
        .museScreen()
        .navigationTitle("Mood Hub")
    }
}

struct MoodDetailView: View {
    @Environment(AppSettings.self) private var settings
    var mood: Mood

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Label(mood.label, systemImage: mood.symbol)
                        .font(MUSEFont.hero).foregroundStyle(.white)
                    Text("Your active mood influences AI DJ and Playlist Studio suggestions.")
                        .font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    HStack {
                        NavigationLink(value: StudioRoute(mood: mood, description: mood.discoveryPrompt)) {
                            Label("Generate playlist", systemImage: "sparkles")
                        }
                        .buttonStyle(NeonButtonStyle())
                    }
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Spacing.cornerLarge).fill(MUSEColor.moodGradient(mood)))
                .listRowBackground(Color.clear)
            }
            Section("Discover") {
                NavigationLink(value: SearchRoute(query: searchQuery, kind: .song, title: mood.label)) {
                    Label("Browse \(mood.label.lowercased()) music", systemImage: "magnifyingglass")
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .museScreen()
        .navigationTitle(mood.label)
        .onAppear { settings.activeMood = mood }
    }

    private var searchQuery: String {
        [settings.preferredLanguage, mood.discoveryPrompt].compactMap { $0 }.joined(separator: " ")
    }
}
