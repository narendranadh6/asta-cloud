import SwiftUI

@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable {
        case welcome, languages, artists, genres, moods, consent
    }

    var step: Step = .welcome
    var languages: Set<String> = []
    var artists: [String] = []
    var genres: Set<String> = []
    var moods: Set<Mood> = []
    var personalization = false
    var artistInput = ""
    private(set) var isSaving = false

    static let genreOptions = ["Melody", "Pop", "Indie", "Hip hop", "Lofi", "Classical",
                               "Carnatic", "Rock", "EDM", "Jazz", "Devotional", "Folk", "R&B", "K-pop"]

    func next() {
        if let next = Step(rawValue: step.rawValue + 1) { step = next }
    }

    func back() {
        if let previous = Step(rawValue: step.rawValue - 1) { step = previous }
    }

    func addArtist() {
        let name = artistInput.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, !artists.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            artists.append(name)
        }
        artistInput = ""
    }

    var preferences: Preferences {
        var prefs = Preferences()
        prefs.personalizationEnabled = personalization
        prefs.languages = languages.sorted()
        prefs.genres = genres.sorted()
        prefs.moods = Mood.allCases.filter(moods.contains)
        prefs.favoriteArtists = artists.map { ArtistPreference(name: $0) }
        prefs.onboardingCompleted = true
        return prefs
    }

    /// Saves choices. Failures don't block entering the app.
    func finish(app: AppModel, settings: AppSettings, skipped: Bool) async {
        isSaving = true
        defer { isSaving = false }
        var prefs = skipped ? Preferences() : preferences
        prefs.onboardingCompleted = true
        if !skipped {
            for artist in artists { app.library.setArtist(artist, excluded: false) }
            settings.preferredLanguage = languages.sorted().first
            settings.activeMood = Mood.allCases.first(where: moods.contains)
        }
        settings.personalizationEnabled = prefs.personalizationEnabled
        _ = try? await app.api.updatePreferences(prefs)
        settings.hasCompletedOnboarding = true
    }
}

struct OnboardingView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model = OnboardingViewModel()

    var body: some View {
        @Bindable var model = model
        VStack(spacing: Spacing.lg) {
            HStack {
                if model.step != .welcome {
                    Button("Back") { withAnimation(animation) { model.back() } }
                }
                Spacer()
                Button("Skip personalization") {
                    Task { await model.finish(app: app, settings: settings, skipped: true) }
                }
                .font(.subheadline)
            }
            .foregroundStyle(HaloColor.mutedText)

            ProgressView(value: Double(model.step.rawValue + 1),
                         total: Double(OnboardingViewModel.Step.allCases.count))
                .tint(HaloColor.primary)
                .accessibilityLabel("Step \(model.step.rawValue + 1) of \(OnboardingViewModel.Step.allCases.count)")

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    content
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                if model.step == .consent {
                    Task { await model.finish(app: app, settings: settings, skipped: false) }
                } else {
                    withAnimation(animation) { model.next() }
                }
            } label: {
                Text(model.step == .consent ? "Start listening" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(NeonButtonStyle())
            .disabled(model.isSaving)
        }
        .padding(Spacing.lg)
        .background(BackgroundGlow().ignoresSafeArea())
    }

    private var animation: Animation? { reduceMotion ? nil : .easeInOut }

    @ViewBuilder
    private var content: some View {
        @Bindable var model = model
        switch model.step {
        case .welcome:
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(HaloColor.neon)
                .accessibilityHidden(true)
            Text("Welcome to Halo").font(HaloFont.hero).foregroundStyle(HaloColor.text)
            Text("Find music with AI, build playlists, and play songs right here in Halo. "
                 + "Halo has no ads and only learns from what you do inside Halo.")
                .foregroundStyle(HaloColor.mutedText)
            NoticeBanner(text: "Every song plays in full, free and legally, from independent "
                         + "artists on Audius and Jamendo.")
        case .languages:
            title("Which languages do you listen to?")
            FlowLayout {
                ForEach(TasteViewModel.commonLanguages, id: \.self) { language in
                    Chip(title: language, isSelected: model.languages.contains(language)) {
                        model.languages.formSymmetricDifference([language])
                    }
                }
            }
        case .artists:
            title("Any favorite artists?")
            HStack {
                TextField("Artist name", text: $model.artistInput)
                    .padding(Spacing.sm)
                    .haloCard(cornerRadius: Spacing.cornerSmall)
                    .submitLabel(.done)
                    .onSubmit { model.addArtist() }
                Button("Add") { model.addArtist() }
            }
            FlowLayout {
                ForEach(model.artists, id: \.self) { artist in
                    Chip(title: artist, systemImage: "xmark", isSelected: true) {
                        model.artists.removeAll { $0 == artist }
                    }
                    .accessibilityHint("Removes \(artist)")
                }
            }
        case .genres:
            title("Pick some genres")
            FlowLayout {
                ForEach(OnboardingViewModel.genreOptions, id: \.self) { genre in
                    Chip(title: genre, isSelected: model.genres.contains(genre)) {
                        model.genres.formSymmetricDifference([genre])
                    }
                }
            }
        case .moods:
            title("How do you like to listen?")
            FlowLayout {
                ForEach(Mood.allCases) { mood in
                    Chip(title: mood.label, systemImage: mood.symbol, isSelected: model.moods.contains(mood)) {
                        model.moods.formSymmetricDifference([mood])
                    }
                }
            }
        case .consent:
            title("Personalize Halo?")
            Text("If you agree, Halo uses your choices here plus your saves, playlists, searches "
                 + "and ratings inside Halo to tune AI suggestions. It never leaves your account or "
                 + "goes to advertisers. You can turn this off or reset it anytime in Settings.")
                .foregroundStyle(HaloColor.mutedText)
            Toggle("Personalize with my Halo activity", isOn: $model.personalization)
                .padding(Spacing.md)
                .haloCard()
        }
    }

    private func title(_ text: String) -> some View {
        Text(text).font(HaloFont.title).foregroundStyle(HaloColor.text)
            .accessibilityAddTraits(.isHeader)
    }
}
