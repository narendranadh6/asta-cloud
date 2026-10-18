import SwiftUI

struct AIDJView: View {
    @Environment(AppModel.self) private var app
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
        .navigationTitle("AI DJ")
        .toolbar {
            if !model.messages.isEmpty {
                Button("New chat", systemImage: "square.and.pencil") { model.reset() }
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
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Image(systemName: "sparkles")
                    .font(.largeTitle)
                    .foregroundStyle(MUSEColor.neon)
                    .accessibilityHidden(true)
                Text("Tell me what you want to hear")
                    .font(MUSEFont.title).foregroundStyle(MUSEColor.text)
                Text("I'll plan searches, check real YouTube results, rank them and explain why. "
                     + "You can edit the queue before saving.")
                    .font(.subheadline).foregroundStyle(MUSEColor.mutedText)
                DemoModeBanner()
                ForEach(AIDJViewModel.examples, id: \.self) { example in
                    Button {
                        model.input = example
                        Task { await model.send(api: app.api) }
                    } label: {
                        Text(example)
                            .font(.subheadline)
                            .foregroundStyle(MUSEColor.text)
                            .multilineTextAlignment(.leading)
                            .padding(Spacing.sm)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .museCard(cornerRadius: Spacing.cornerSmall)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

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
