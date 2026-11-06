import SwiftUI

/// Connects the microphone and voice to a `DriveSession`: one tap on the Halo orb (or the
/// wake word), one turn. Lives for the whole app, not only Halo Drive.
@MainActor
@Observable
final class DriveVoice {
    let session: DriveSession
    /// What Halo heard so far, shown while listening.
    private(set) var caption = ""
    /// A disclosure to show before audio could leave the iPhone (nil when none is pending).
    var consentRequest: ProcessingDisclosure?
    /// Why Halo suggests typing instead of talking right now (nil when talking works).
    private(set) var typingReason: TextInputReason?
    /// Whether the small Halo card (what Halo heard and said) is showing.
    private(set) var showsCard = false
    /// Called when a turn is over (the wake-word listener resumes then).
    @ObservationIgnored var onTurnFinished: (() -> Void)?
    @ObservationIgnored private var hideCard: Task<Void, Never>?
    @ObservationIgnored private let listener = SpeechListener()
    @ObservationIgnored private let player: PlayerController
    @ObservationIgnored private let consent: VoiceConsent
    @ObservationIgnored private let platform: SpeechPlatform
    @ObservationIgnored private var turn: Task<Void, Never>?
    @ObservationIgnored private var lastLocale = Locale(identifier: "en-IN")

    init(session: DriveSession, player: PlayerController, consent: VoiceConsent,
         platform: SpeechPlatform = SystemSpeechPlatform()) {
        self.session = session
        self.player = player
        self.consent = consent
        self.platform = platform
        listener.onPartial = { [weak self] text in self?.caption = text }
    }

    var isListening: Bool { session.voiceState == .listening }

    /// Press to talk; press again to finish early.
    func talk(locale: Locale) {
        if isListening {
            listener.stop()
            return
        }
        showCard()
        lastLocale = locale
        let report = SpeechCapabilityProbe(platform: platform).run(locales: [locale.identifier])
        let route = SpeechRoutePlanner.route(
            locale: locale.identifier, report: report,
            appleConsent: (consent.isGranted(.appleSpeech), consent.needsAnswer(.appleSpeech)))
        switch route {
        case .onDevice:
            typingReason = nil
            listen(locale: locale, requireOnDevice: true)
        case .appleServer:
            typingReason = nil
            listen(locale: locale, requireOnDevice: false)
        case .haloServer:
            typingReason = .unavailable  // no Halo speech server in this build
            finishTurn()
        case let .textInput(reason):
            typingReason = reason
            if case let .consentNeeded(processor) = reason {
                consentRequest = ProcessingDisclosure.of(processor)
            } else {
                finishTurn()
            }
        }
    }

    /// A command spoken right after the wake word ("Halo, play Telugu songs").
    func handleCommand(_ text: String) {
        showCard()
        caption = text
        Task {
            await session.handle(text)
            finishTurn()
        }
    }

    func dismissCard() {
        hideCard?.cancel()
        showsCard = false
    }

    private func showCard() {
        hideCard?.cancel()
        showsCard = true
    }

    private func finishTurn() {
        onTurnFinished?()
        hideCard?.cancel()
        hideCard = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.showsCard = false
        }
    }

    /// The listener answered the disclosure. Agreeing starts listening right away.
    func answerConsent(_ granted: Bool) {
        guard let request = consentRequest else { return }
        consentRequest = nil
        consent.record(granted ? .granted : .declined, for: request.processor)
        if granted { talk(locale: lastLocale) } else { typingReason = .consentDeclined; finishTurn() }
    }

    func submitTyped(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        caption = trimmed
        showCard()
        Task {
            await session.handleTyped(String(trimmed.prefix(200)))
            finishTurn()
        }
    }

    private func listen(locale: Locale, requireOnDevice: Bool) {
        turn?.cancel()
        caption = ""
        session.beginListening()
        player.duck("listening", true)
        turn = Task {
            do {
                let heard = try await listener.listen(locale: locale, requireOnDevice: requireOnDevice)
                player.duck("listening", false)
                caption = heard.text
                await session.handle(heard.text, confidence: heard.confidence)
            } catch is CancellationError {
                player.duck("listening", false)
                session.cancelListening()
            } catch SpeechListener.ListenError.nothingHeard {
                player.duck("listening", false)
                await session.recognitionFailed()
            } catch {
                player.duck("listening", false)
                session.failListening(error.localizedDescription)
            }
            finishTurn()
        }
    }

    func stop() {
        listener.cancel()
        turn?.cancel()
        player.duck("listening", false)
    }
}

/// Halo Drive: a calm, glanceable screen for listening while driving. Big targets, one
/// voice button, nothing to read for long.
struct DriveView: View {
    var voice: DriveVoice
    var close: () -> Void

    @Environment(PlayerController.self) private var player
    @Environment(AppSettings.self) private var settings
    @Environment(AppModel.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: ArtworkPalette = .halo
    @State private var confirmReset = false
    @State private var typing = false
    @State private var typed = ""

    private var session: DriveSession { voice.session }

    var body: some View {
        GeometryReader { proxy in
            let art = min(proxy.size.width - Spacing.lg * 2, proxy.size.height * 0.36)
            VStack(spacing: Spacing.lg) {
                header
                Spacer(minLength: 0)
                artwork(side: art)
                nowPlaying
                transport
                Spacer(minLength: 0)
                replyLine
                talkButton
                typeButton
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.bottom, Spacing.md)
        }
        .foregroundStyle(HaloColor.text)
        .background {
            AmbientBackground(palette: palette, artworkURL: player.item?.largeArtworkURL)
                .ignoresSafeArea()
        }
        .task(id: player.item?.artworkURL) { await loadPalette() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            voice.stop()
        }
        .accessibilityIdentifier("drive")
        .sheet(item: Binding(get: { voice.consentRequest.map(ConsentItem.init) },
                             set: { if $0 == nil, voice.consentRequest != nil { voice.answerConsent(false) } })) { item in
            VoiceConsentView(disclosure: item.disclosure) { voice.answerConsent($0) }
        }
        .alert("Type to Halo", isPresented: $typing) {
            TextField("e.g. Telugu songs pettu", text: $typed)
                .accessibilityIdentifier("typeToHaloField")
            Button("Send") {
                voice.submitTyped(typed)
                typed = ""
            }
            Button("Cancel", role: .cancel) { typed = "" }
        } message: {
            Text("Only when parked or as a passenger.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("HALO DRIVE").font(HaloFont.eyebrow).tracking(1.4)
                    .foregroundStyle(HaloColor.text.opacity(0.7))
                Text(session.summary.isEmpty ? "Say what you'd like to hear" : session.summary)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button("Reset") { confirmReset = true }
                .font(.headline)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
                .accessibilityLabel("Reset this drive")
                .confirmationDialog("Reset this drive?", isPresented: $confirmReset,
                                    titleVisibility: .visible) {
                    Button("Reset", role: .destructive) { session.resetSession() }
                } message: {
                    Text("Halo forgets this drive's requests, skips and today's exclusions. "
                         + "Your queued songs keep playing.")
                }
            Button("End", action: close)
                .font(.headline)
                .padding(.horizontal, Spacing.md)
                .frame(minHeight: 44)
                .background(Capsule().fill(.white.opacity(0.14)))
                .accessibilityLabel("End Halo Drive")
        }
        .padding(.top, Spacing.sm)
    }

    private func artwork(side: CGFloat) -> some View {
        HaloArtwork(url: player.item?.largeArtworkURL ?? player.item?.artworkURL, size: side,
                    cornerRadius: Radius.large)
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .accessibilityHidden(true)
    }

    private var nowPlaying: some View {
        VStack(spacing: 4) {
            Text(player.item?.title ?? "Nothing playing")
                .font(HaloFont.title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(player.item?.subtitle ?? "Tap Talk to Halo and ask for music")
                .font(.title3.weight(.medium))
                .foregroundStyle(HaloColor.text.opacity(0.7))
                .lineLimit(1)
        }
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }

    private var transport: some View {
        HStack(spacing: Spacing.xl) {
            bigButton("backward.fill", label: "Previous", size: 64) { player.previous() }
                .disabled(player.item == nil)
            bigButton(player.isPlaying ? "pause.fill" : "play.fill",
                      label: player.isPlaying ? "Pause" : "Play", size: 88, filled: true) {
                player.togglePlayPause()
            }
            .disabled(player.item == nil)
            bigButton("forward.fill", label: "Next", size: 64) { player.next() }
                .disabled(!player.hasNext)
        }
    }

    private func bigButton(_ symbol: String, label: String, size: CGFloat, filled: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(enabled: settings.hapticsEnabled)
            action()
        } label: {
            ZStack {
                Circle().fill(filled ? HaloColor.text : .white.opacity(0.12))
                Image(systemName: symbol)
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(filled ? palette.color(\.base) : HaloColor.text)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var replyLine: some View {
        let text: String? = switch session.voiceState {
        case .listening: voice.caption.isEmpty ? "Listening…" : voice.caption
        case .understanding, .applying: voice.caption
        case let .error(message): message
        case .done, .idle: session.lastReply
        }
        Text(text ?? " ")
            .font(.title3.weight(.semibold))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(HaloColor.text.opacity(session.voiceState == .listening ? 1 : 0.85))
            .accessibilityLabel(text ?? "")
            .accessibilityAddTraits(.updatesFrequently)
    }

    private var typeButton: some View {
        Button { typing = true } label: {
            Label(typingHint, systemImage: "keyboard")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .accessibilityIdentifier("typeToHalo")
    }

    private var typingHint: String {
        switch voice.typingReason {
        case .permissionDenied: "Microphone off — type instead"
        case .unavailable: "Speech isn't available — type instead"
        case .consentDeclined: "Type instead"
        case .consentNeeded, .none: "Type instead"
        }
    }

    /// The Halo orb: tap to talk (or say "Halo" when the wake word is on).
    private var talkButton: some View {
        Button {
            Haptics.tap(enabled: settings.hapticsEnabled)
            app.talk()
        } label: {
            VStack(spacing: Spacing.xs) {
                AIOrb(size: 84, isActive: voice.isListening || isWorking)
                Text(voice.isListening ? "Listening — tap when done"
                     : settings.wakeWordEnabled ? "Tap Halo or say “Halo”" : "Tap Halo to talk")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(voice.isListening ? "Stop listening" : "Talk to Halo")
        .accessibilityIdentifier("talkToHalo")
    }

    private var isWorking: Bool {
        session.voiceState == .understanding || session.voiceState == .applying
    }

    private func loadPalette() async {
        let fallback = ArtworkPalette.fallback(seed: player.item?.subtitle ?? "Halo")
        guard let url = player.item?.largeArtworkURL ?? player.item?.artworkURL else {
            palette = fallback
            return
        }
        let found = await ArtworkPipeline.shared.palette(for: url)
        guard !Task.isCancelled else { return }
        palette = found ?? fallback
    }
}

private struct ConsentItem: Identifiable {
    var disclosure: ProcessingDisclosure
    var id: String { disclosure.processor.rawValue }
}
