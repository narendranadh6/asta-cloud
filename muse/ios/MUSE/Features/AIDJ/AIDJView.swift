import SwiftUI

struct AIDJView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var model = AIDJViewModel()
    @State private var openDraft: Int?
    @FocusState private var inputFocused: Bool

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.md) {
                        intro
                        ForEach(model.messages) { message in
                            bubble(message).id(message.id)
                        }
                        if model.isThinking {
                            HStack(spacing: Spacing.xs) {
                                ProgressView().tint(MUSEColor.secondary)
                                Text("Searching verified results…")
                                    .font(.subheadline).foregroundStyle(MUSEColor.mutedText)
                            }
                            .id("thinking")
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(Spacing.md)
                }
                .onChange(of: model.messages.count) { _, _ in
                    withAnimation { proxy.scrollTo(model.messages.last?.id, anchor: .bottom) }
                }
            }
            inputBar
        }
        .museScreen()
        .navigationTitle(model.messages.isEmpty ? "" : "AI DJ")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: app.pendingDJPrompt) {
            guard let prompt = app.pendingDJPrompt else { return }
            app.pendingDJPrompt = nil
            model.input = prompt
            await model.send(api: app.api)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink(value: StudioRoute(mood: nil, description: "")) {
                    Label("Playlist Studio", systemImage: "wand.and.stars")
                }
            }
            if !model.messages.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New chat", systemImage: "square.and.pencil") { model.reset() }
                }
            }
        }
        .navigationDestination(item: $openDraft) { index in
            if model.drafts.indices.contains(index) {
                DraftEditorView(draft: $model.drafts[index])
            }
        }
        .museDestinations()
    }

    @ViewBuilder
    private var intro: some View {
        if model.messages.isEmpty {
            VStack(spacing: Spacing.md) {
                VStack(spacing: Spacing.xxs) {
                    Text("MUSE AI DJ").font(MUSEFont.title).foregroundStyle(MUSEColor.text)
                    Text("Your personal music companion")
                        .font(.subheadline).foregroundStyle(MUSEColor.mutedText)
                }
                AIOrb(size: 150, isActive: true)
                    .padding(.vertical, Spacing.sm)
                Text(greeting)
                    .foregroundStyle(MUSEColor.text)
                    .padding(Spacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .museCard()
                DemoModeBanner()
                VStack(alignment: .leading, spacing: Spacing.xs) {
                    ForEach(Self.quickPrompts, id: \.label) { prompt in
                        Button {
                            model.input = prompt.text
                            Task { await model.send(api: app.api) }
                        } label: {
                            Label(prompt.label, systemImage: prompt.symbol)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(MUSEColor.text)
                                .padding(.horizontal, Spacing.sm)
                                .frame(minHeight: 40)
                                .background(Capsule().fill(MUSEColor.surface))
                                .overlay(Capsule().strokeBorder(MUSEColor.primary.opacity(0.35)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(prompt.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("I plan searches, check real YouTube results, rank them and explain why. "
                     + "You edit the queue before saving.")
                    .font(.caption).foregroundStyle(MUSEColor.mutedText)
            }
        }
    }

    private var greeting: String {
        let name = settings.displayName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Hi! What would you like to listen to?"
                            : "Hi \(name)! What would you like to listen to?"
    }

    static let quickPrompts: [(label: String, symbol: String, text: String)] = [
        ("Surprise me", "dice", "Surprise me with something I haven't heard, any language"),
        ("Music for coding", "chevron.left.forwardslash.chevron.right",
         "Create a late-night coding playlist with minimal vocals."),
        ("Chill vibes tonight", "moon.stars", "Chill relaxing songs for tonight"),
        ("Workout mix", "figure.run", "High energy workout mix for 45 minutes"),
        ("Similar to my favorites, but different", "wand.and.stars",
         "Recommend songs similar to my favorites but less popular."),
        ("Create a playlist for my trip", "car", "Build a playlist for a two-hour road trip."),
        ("Telugu melodies from the 2000s", "music.note", "Find relaxing Telugu melodies from the 2000s."),
    ]

    @ViewBuilder
    private func bubble(_ message: AIDJViewModel.Message) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .padding(Spacing.sm)
                    .foregroundStyle(.white)
                    .background(RoundedRectangle(cornerRadius: Spacing.corner).fill(MUSEColor.neon))
            }
            .accessibilityLabel("You said: \(message.text)")
        case .assistant:
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text(message.text).foregroundStyle(MUSEColor.text)
                if let index = message.draftIndex, model.drafts.indices.contains(index) {
                    draftCard(model.drafts[index], index: index)
                }
            }
            .padding(Spacing.sm)
            .museCard()
        case .error:
            Label(message.text, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(MUSEColor.danger)
        }
    }

    private func draftCard(_ draft: EditableDraft, index: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(draft.title).font(MUSEFont.headline).foregroundStyle(MUSEColor.text)
            Text("\(draft.queue.count) songs · \(DurationFormatter.approximate(draft.totalSeconds))")
                .font(.caption).foregroundStyle(MUSEColor.mutedText)
            ForEach(draft.queue.items.prefix(3)) { item in
                TrackRow(track: item.track, showsAttribution: false)
            }
            Button("Review & save queue") { openDraft = index }
                .buttonStyle(NeonButtonStyle())
        }
    }

    private var inputBar: some View {
        HStack(spacing: Spacing.xs) {
            TextField("Describe a vibe, activity or artist…", text: $model.input, axis: .vertical)
                .lineLimit(1...4)
                .focused($inputFocused)
                .padding(Spacing.sm)
                .museCard(cornerRadius: Spacing.corner)
                .submitLabel(.send)
                .onSubmit { send() }
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                    .foregroundStyle(model.canSend ? AnyShapeStyle(MUSEColor.neon)
                                                   : AnyShapeStyle(MUSEColor.mutedText))
            }
            .disabled(!model.canSend)
            .accessibilityLabel("Send")
        }
        .padding(Spacing.sm)
        .background(MUSEColor.background.opacity(0.9))
    }

    private func send() {
        inputFocused = false
        Task { await model.send(api: app.api) }
    }
}
