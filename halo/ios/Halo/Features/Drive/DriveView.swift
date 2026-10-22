import SwiftUI

/// Connects the microphone and voice to a `DriveSession`: one "Talk to Halo" press, one turn.
@MainActor
@Observable
final class DriveVoice {
    let session: DriveSession
    /// What Halo heard so far, shown while listening.
    private(set) var caption = ""
    @ObservationIgnored private let listener = SpeechListener()
    @ObservationIgnored private let player: PlayerController
    @ObservationIgnored private var turn: Task<Void, Never>?

    init(session: DriveSession, player: PlayerController) {
        self.session = session
        self.player = player
        listener.onPartial = { [weak self] text in self?.caption = text }
    }

    var isListening: Bool { session.voiceState == .listening }

    /// Press to talk; press again to finish early.
    func talk(locale: Locale) {
        if isListening {
            listener.stop()
            return
        }
        turn?.cancel()
        caption = ""
        session.beginListening()
        player.duck("listening", true)
        turn = Task {
            do {
                let heard = try await listener.listen(locale: locale)
                player.duck("listening", false)
                caption = heard.text
                await session.handle(heard.text, confidence: heard.confidence)
            } catch is CancellationError {
                player.duck("listening", false)
                session.cancelListening()
            } catch {
                player.duck("listening", false)
                session.failListening(error.localizedDescription)
            }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var palette: ArtworkPalette = .halo

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

    private var talkButton: some View {
        Button {
            Haptics.tap(enabled: settings.hapticsEnabled)
            voice.talk(locale: Locale(identifier: settings.voiceLocale))
        } label: {
            HStack(spacing: Spacing.sm) {
                Image(systemName: voice.isListening ? "waveform" : "mic.fill")
                    .symbolEffect(.variableColor.iterative, isActive: voice.isListening && !reduceMotion)
                Text(voice.isListening ? "Listening — tap when done" : "Talk to Halo")
            }
            .font(.title3.weight(.bold))
            .frame(maxWidth: .infinity, minHeight: 72)
            .foregroundStyle(palette.color(\.base))
            .background(RoundedRectangle(cornerRadius: Radius.large).fill(HaloColor.text))
            .overlay {
                HaloRing(active: voice.isListening || isWorking, cornerRadius: Radius.large + 5)
                    .padding(-5)
            }
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
