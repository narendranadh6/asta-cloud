import SwiftUI

struct PlaylistStudioView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var model = PlaylistStudioViewModel()
    @State private var showDraft = false
    @State private var shownIDs: [String] = []

    var initialMood: Mood?
    var initialDescription: String = ""

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Describe it") {
                TextField("e.g. Sunday morning chai, soft vocals", text: $model.description,
                          axis: .vertical)
                    .lineLimit(2...5)
            }
            Section("Shape it") {
                Picker("Mood", selection: $model.mood) {
                    Text("Any").tag(Mood?.none)
                    ForEach(Mood.allCases) { Label($0.label, systemImage: $0.symbol).tag(Mood?.some($0)) }
                }
                TextField("Genres (comma separated)", text: $model.genresText)
                Picker("Language", selection: $model.language) {
                    ForEach(PlaylistStudioViewModel.languages, id: \.self) {
                        Text($0.isEmpty ? "Any" : $0).tag($0)
                    }
                }
                Toggle("Set energy level", isOn: $model.useEnergy)
                if model.useEnergy {
                    VStack(alignment: .leading) {
                        Slider(value: $model.energy, in: 0...100, step: 5) {
                            Text("Energy")
                        } minimumValueLabel: {
                            Image(systemName: "tortoise")
                        } maximumValueLabel: {
                            Image(systemName: "hare")
                        }
                        .accessibilityValue("\(Int(model.energy)) percent")
                    }
                }
                Stepper(value: $model.durationMinutes, in: 10...300, step: 10) {
                    LabeledContent("Duration", value: DurationFormatter.approximate(model.durationMinutes * 60))
                }
                Picker("Familiar vs. discovery", selection: $model.discovery) {
                    ForEach(DiscoveryPreference.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                Button {
                    Task {
                        await model.generate(api: app.api)
                        if let draft = model.draft {
                            shownIDs = draft.queue.items.map(\.track.videoId)
                            showDraft = true
                        }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if model.isGenerating { ProgressView().tint(.white) }
                        Text(model.isGenerating ? "Finding verified songs…" : "Generate playlist")
                        Spacer()
                    }
                }
                .buttonStyle(NeonButtonStyle())
                .disabled(!model.canGenerate)
                .listRowBackground(Color.clear)
                if let error = model.error {
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(MUSEColor.danger)
                }
            } footer: {
                Text("MUSE turns this into YouTube searches, keeps only verified results, and ranks "
                     + "them. Nothing is played or downloaded inside MUSE.")
            }
        }
        .museScreen()
        .navigationTitle("Playlist Studio")
        .onAppear {
            if model.description.isEmpty {
                model.description = initialDescription
                model.mood = initialMood ?? settings.activeMood
                if model.language.isEmpty, let preferred = settings.preferredLanguage {
                    model.language = preferred
                }
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
}
