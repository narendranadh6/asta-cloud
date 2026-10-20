import SwiftData
import SwiftUI

@MainActor
@Observable
final class TasteViewModel {
    private(set) var profile: TasteProfile?
    var preferences = Preferences()
    private(set) var isLoading = false
    private(set) var error: Error?
    private(set) var isSaving = false

    static let commonLanguages = ["Telugu", "Hindi", "Tamil", "Malayalam", "Kannada", "Punjabi",
                                  "Bengali", "Marathi", "English", "Spanish", "Korean",
                                  "Japanese", "French", "Arabic"]

    func load(api: MusicAPI) async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            async let prefs = api.preferences()
            async let taste = api.taste()
            preferences = try await prefs
            profile = try await taste
        } catch {
            self.error = error
        }
    }

    func save(api: MusicAPI) async {
        isSaving = true
        defer { isSaving = false }
        do {
            preferences = try await api.updatePreferences(preferences)
            profile = try await api.taste()
        } catch {
            self.error = error
        }
    }

    func toggleLanguage(_ language: String) {
        if let index = preferences.languages.firstIndex(of: language) {
            preferences.languages.remove(at: index)
        } else {
            preferences.languages.append(language)
        }
    }

    func exclude(_ name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty,
              !preferences.excludedArtists.contains(where: { $0.id == cleaned.lowercased() }) else { return }
        preferences.excludedArtists.append(ArtistPreference(name: cleaned))
        preferences.favoriteArtists.removeAll { $0.id == cleaned.lowercased() }
    }

    func reset(api: MusicAPI) async {
        do {
            try await api.resetTaste()
            profile = try await api.taste()
        } catch {
            self.error = error
        }
    }
}

struct TasteView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var model = TasteViewModel()
    @State private var excludeText = ""
    @State private var confirmReset = false

    var body: some View {
        @Bindable var model = model
        List {
            Section {
                Text(model.profile?.basis
                     ?? "Halo learns only from what you do in Halo. It cannot see what you play in Brave.")
                    .font(.footnote).foregroundStyle(HaloColor.mutedText)
                Toggle("Personalize with my Halo activity", isOn: Binding(
                    get: { model.preferences.personalizationEnabled },
                    set: { value in
                        model.preferences.personalizationEnabled = value
                        if !value { model.preferences.storeAiConversations = false }
                        settings.personalizationEnabled = value
                        Task { await model.save(api: app.api) }
                    }))
            }
            .listRowBackground(Color.clear)

            if model.isLoading && model.profile == nil {
                LoadingStateView().listRowBackground(Color.clear)
            } else if let error = model.error, model.profile == nil {
                ErrorStateView(error: error) { Task { await model.load(api: app.api) } }
                    .listRowBackground(Color.clear)
            } else if let profile = model.profile {
                inferred(profile)
            }

            Section("Preferred languages") {
                FlowLayout {
                    ForEach(TasteViewModel.commonLanguages, id: \.self) { language in
                        Chip(title: language, isSelected: model.preferences.languages.contains(language)) {
                            model.toggleLanguage(language)
                            Task { await model.save(api: app.api) }
                        }
                    }
                }
                .padding(.vertical, Spacing.xs)
            }
            .listRowBackground(Color.clear)

            Section {
                HStack {
                    TextField("Artist to exclude", text: $excludeText)
                    Button("Exclude") {
                        model.exclude(excludeText)
                        app.library.setArtist(excludeText, excluded: true)
                        excludeText = ""
                        Task { await model.save(api: app.api) }
                    }
                    .disabled(excludeText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                ForEach(model.preferences.excludedArtists) { artist in
                    Text(artist.name)
                }
                .onDelete { offsets in
                    model.preferences.excludedArtists.remove(atOffsets: offsets)
                    Task { await model.save(api: app.api) }
                }
            } header: {
                Text("Excluded artists")
            } footer: {
                Text("Excluded artists never appear in AI playlists, even with personalization off.")
            }
            .listRowBackground(Color.clear)

            Section {
                Button("Reset taste memory", role: .destructive) { confirmReset = true }
            } footer: {
                Text("Forgets searches, feedback and AI history used for inference. Saved songs, "
                     + "playlists and your explicit settings stay.")
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.insetGrouped)
        .haloScreen()
        .navigationTitle("Taste Intelligence")
        .task { await model.load(api: app.api) }
        .refreshable { await model.load(api: app.api) }
        .confirmationDialog("Reset taste memory?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) {
                app.library.clearRecentSearches()
                Task { await model.reset(api: app.api) }
            }
        }
    }

    @ViewBuilder
    private func inferred(_ profile: TasteProfile) -> some View {
        Section {
            if profile.topArtists.isEmpty && profile.topTerms.isEmpty {
                Text("Not enough Halo activity yet. Save songs or build playlists to see patterns.")
                    .font(.subheadline).foregroundStyle(HaloColor.mutedText)
            }
            ForEach(profile.topArtists) { signal in
                HStack {
                    Label(signal.label, systemImage: "music.mic")
                    Spacer()
                    Text(signal.evidence).font(.caption).foregroundStyle(HaloColor.mutedText)
                }
                .swipeActions {
                    Button("Not me") {
                        model.exclude(signal.label)
                        app.library.setArtist(signal.label, excluded: true)
                        Task { await model.save(api: app.api) }
                    }
                    .tint(HaloColor.danger)
                }
            }
            if !profile.topTerms.isEmpty {
                FlowLayout {
                    ForEach(profile.topTerms) { term in
                        Text(term.label)
                            .font(.caption)
                            .padding(.horizontal, Spacing.xs).padding(.vertical, 4)
                            .background(Capsule().fill(HaloColor.surface))
                    }
                }
            }
        } header: {
            Text("Inferred from Halo activity")
        } footer: {
            Text("Activity: \(profile.activityCounts["playlists"] ?? 0) playlists, "
                 + "\(profile.activityCounts["searches"] ?? 0) searches, "
                 + "\(profile.activityCounts["feedback"] ?? 0) ratings. Swipe an artist to correct it.")
        }
        .listRowBackground(Color.clear)
    }
}
