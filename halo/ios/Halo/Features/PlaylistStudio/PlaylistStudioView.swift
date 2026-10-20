import SwiftUI

struct PlaylistStudioView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var model = PlaylistStudioViewModel()
    @State private var showDraft = false
    @State private var shownIDs: [String] = []
    @State private var showMore = false
    @FocusState private var promptFocused: Bool

    var initialMood: Mood?
    var initialDescription: String = ""

    static let examples: [(title: String, subtitle: String, mood: Mood, text: String)] = [
        ("Late night coding", "Chill electronic, minimal vocals", .focused,
         "Late night coding with chill electronic music and minimal vocals"),
        ("Gym motivation", "High energy tracks", .workout, "High energy gym motivation tracks"),
        ("Rainy day", "Calm and cozy", .calm, "Calm, cozy songs for a rainy day"),
        ("Feel good", "Positive and uplifting", .happy, "Positive, uplifting feel-good songs"),
        ("Travel vibes", "Songs for the road", .travel, "A road trip playlist for a sunset drive"),
    ]

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                Text("Create a playlist with AI")
                    .font(HaloFont.title).foregroundStyle(HaloColor.text)

                HStack(alignment: .bottom, spacing: Spacing.sm) {
                    TextField("Describe a vibe, mood or activity…", text: $model.description, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($promptFocused)
                        .foregroundStyle(HaloColor.text)
                    Button(action: generate) {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(model.canGenerate ? AnyShapeStyle(HaloColor.neon)
                                                               : AnyShapeStyle(HaloColor.mutedText))
                    }
                    .disabled(!model.canGenerate)
                    .accessibilityLabel("Generate playlist")
                }
                .padding(Spacing.md)
                .haloCard(cornerRadius: Spacing.corner)

                optionChips

                if showMore { moreOptions }

                VStack(alignment: .leading, spacing: Spacing.sm) {
                    SectionHeader(title: "Examples")
                    ForEach(Self.examples, id: \.title) { example in
                        Button {
                            model.description = example.text
                            model.mood = example.mood
                            Haptics.tap(enabled: settings.hapticsEnabled)
                        } label: {
                            HStack(spacing: Spacing.sm) {
                                Image(systemName: example.mood.symbol)
                                    .font(.title3)
                                    .foregroundStyle(.white)
                                    .frame(width: 48, height: 48)
                                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(HaloColor.moodGradient(example.mood)))
                                    .accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(example.title).font(.subheadline.weight(.semibold))
                                        .foregroundStyle(HaloColor.text)
                                    Text(example.subtitle).font(.caption).foregroundStyle(HaloColor.mutedText)
                                }
                                Spacer()
                                Image(systemName: "plus.circle").font(.title3).foregroundStyle(HaloColor.mutedText)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Use example: \(example.title)")
                    }
                }

                if let error = model.error {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(HaloColor.danger)
                }

                Button(action: generate) {
                    HStack {
                        if model.isGenerating { ProgressView().tint(.white) }
                        Text(model.isGenerating ? "Finding verified songs…" : "Generate playlist")
                        Image(systemName: "sparkles")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(!model.canGenerate)

                Text("Halo turns this into YouTube searches, keeps only verified results and ranks "
                     + "them. Nothing is played or downloaded inside Halo.")
                    .font(.caption).foregroundStyle(HaloColor.mutedText)
            }
            .padding(Spacing.md)
        }
        .haloScreen()
        .navigationTitle("Playlist Studio")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard model.description.isEmpty else { return }
            model.description = initialDescription
            model.mood = initialMood ?? settings.activeMood
            model.discovery = settings.discovery
            if let energy = settings.preferredEnergy {
                model.energy = Double(energy)
                model.useEnergy = true
            }
            if model.language.isEmpty, let preferred = settings.preferredLanguage {
                model.language = preferred
            }
        }
        .navigationDestination(isPresented: $showDraft) {
            if model.draft != nil {
                DraftEditorView(
                    draft: Binding(get: { model.draft! }, set: { model.draft = $0 }),
                    onRegenerate: {
                        await model.regenerate(api: app.api, shownIDs: shownIDs)
                        shownIDs += model.draft?.queue.items.map(\.track.videoId) ?? []
                    })
            }
        }
    }

    private var optionChips: some View {
        @Bindable var model = model
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.xs) {
                Menu {
                    Picker("Mood", selection: $model.mood) {
                        Text("Any mood").tag(Mood?.none)
                        ForEach(Mood.allCases) { Label($0.label, systemImage: $0.symbol).tag(Mood?.some($0)) }
                    }
                } label: { menuChip(model.mood?.label ?? "Mood", symbol: model.mood?.symbol ?? "face.smiling") }
                Menu {
                    Picker("Language", selection: $model.language) {
                        ForEach(PlaylistStudioViewModel.languages, id: \.self) {
                            Text($0.isEmpty ? "Any language" : $0).tag($0)
                        }
                    }
                } label: { menuChip(model.language.isEmpty ? "Language" : model.language, symbol: "globe") }
                Menu {
                    Picker("Duration", selection: $model.durationMinutes) {
                        ForEach([20, 30, 45, 60, 90, 120, 180], id: \.self) {
                            Text(DurationFormatter.approximate($0 * 60)).tag($0)
                        }
                    }
                } label: { menuChip(DurationFormatter.approximate(model.durationMinutes * 60), symbol: "clock") }
                Button { withAnimation { showMore.toggle() } } label: {
                    menuChip(showMore ? "Fewer options" : "More options", symbol: "slider.horizontal.3")
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func menuChip(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(HaloColor.text)
            .padding(.horizontal, Spacing.sm)
            .frame(minHeight: 36)
            .background(Capsule().fill(HaloColor.surface))
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
    }

    private var moreOptions: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Spacing.md) {
            TextField("Genres (comma separated)", text: $model.genresText)
                .padding(Spacing.sm)
                .haloCard(cornerRadius: Spacing.cornerSmall)
            Toggle("Set energy level", isOn: $model.useEnergy)
            if model.useEnergy {
                HStack {
                    Image(systemName: "tortoise")
                    Slider(value: $model.energy, in: 0...100, step: 5)
                        .accessibilityLabel("Energy")
                        .accessibilityValue("\(Int(model.energy)) percent")
                    Image(systemName: "hare")
                }
                .foregroundStyle(HaloColor.mutedText)
            }
            Picker("Familiar vs. discovery", selection: $model.discovery) {
                ForEach(DiscoveryPreference.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(Spacing.md)
        .haloCard()
    }

    private func generate() {
        promptFocused = false
        Task {
            await model.generate(api: app.api)
            if let draft = model.draft, model.error == nil {
                shownIDs = draft.queue.items.map(\.track.videoId)
                showDraft = true
            }
        }
    }
}
