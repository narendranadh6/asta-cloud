import SwiftUI

struct MoodHubView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var mood: Mood?
    @State private var energy: Double = 50
    @State private var discovery: DiscoveryPreference = .balanced
    @State private var saved = false
    private let columns = [GridItem(.adaptive(minimum: 150), spacing: Spacing.sm)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                todayCard
                SectionHeader(title: "Explore moods")
                LazyVGrid(columns: columns, spacing: Spacing.sm) {
                    ForEach(Mood.allCases) { mood in
                        NavigationLink(value: MoodRoute(mood: mood)) {
                            VStack(alignment: .leading, spacing: Spacing.sm) {
                                Image(systemName: mood.symbol).font(.title)
                                Spacer(minLength: 0)
                                Text(mood.label).font(HaloFont.title)
                                if settings.activeMood == mood {
                                    Text("Active").font(.caption.weight(.bold))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(Spacing.md)
                            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Spacing.corner)
                                .fill(HaloColor.moodGradient(mood)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(mood.label) mood\(settings.activeMood == mood ? ", active" : "")")
                    }
                }
            }
            .padding(Spacing.md)
        }
        .haloScreen()
        .navigationTitle("Mood Hub")
        .onAppear {
            mood = settings.activeMood
            energy = Double(settings.preferredEnergy ?? 50)
            discovery = settings.discovery
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                Text("Your mood today").font(HaloFont.section).foregroundStyle(HaloColor.text)
                Spacer()
                Button(saved ? "Saved ✓" : "Save", action: save)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, Spacing.sm).padding(.vertical, 6)
                    .background(Capsule().fill(HaloColor.neon))
                    .foregroundStyle(.white)
            }
            FlowLayout {
                ForEach(Mood.allCases) { option in
                    Chip(title: option.label, systemImage: option.symbol, isSelected: mood == option) {
                        mood = mood == option ? nil : option
                        saved = false
                    }
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    Text("Energy level").foregroundStyle(HaloColor.text)
                    Spacer()
                    Text("\(Int(energy))%").monospacedDigit().foregroundStyle(HaloColor.mutedText)
                }
                Slider(value: $energy, in: 0...100, step: 5) { _ in saved = false }
                    .tint(HaloColor.primary)
                    .accessibilityLabel("Energy level")
                    .accessibilityValue("\(Int(energy)) percent")
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("Music discovery").foregroundStyle(HaloColor.text)
                Picker("Music discovery", selection: $discovery) {
                    Text("Familiar").tag(DiscoveryPreference.familiar)
                    Text("Balanced").tag(DiscoveryPreference.balanced)
                    Text("Adventurous").tag(DiscoveryPreference.discovery)
                }
                .pickerStyle(.segmented)
                .onChange(of: discovery) { _, _ in saved = false }
            }
            Text("Used as defaults for Halo's mixes and Playlist Studio.")
                .font(.caption).foregroundStyle(HaloColor.mutedText)
        }
        .padding(Spacing.md)
        .haloCard()
    }

    private func save() {
        settings.activeMood = mood
        settings.preferredEnergy = Int(energy)
        settings.discovery = discovery
        saved = true
        Haptics.success(enabled: settings.hapticsEnabled)
        let choice = discovery
        Task {
            guard var prefs = try? await app.api.preferences() else { return }
            prefs.discoveryPreference = choice
            _ = try? await app.api.updatePreferences(prefs)
        }
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
                        .font(HaloFont.hero).foregroundStyle(.white)
                    Text("Your active mood shapes Halo and Playlist Studio suggestions.")
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
                .background(RoundedRectangle(cornerRadius: Spacing.cornerLarge).fill(HaloColor.moodGradient(mood)))
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
        .haloScreen()
        .navigationTitle(mood.label)
        .onAppear { settings.activeMood = mood }
    }

    private var searchQuery: String {
        [settings.preferredLanguage, mood.discoveryPrompt].compactMap { $0 }.joined(separator: " ")
    }
}
