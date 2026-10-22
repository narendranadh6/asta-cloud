import AVFoundation

/// Halo's spoken replies, through the system voices. Telugu replies use a Telugu voice when
/// the device has one; otherwise an Indian English voice. The music dips while Halo talks.
@MainActor
final class SystemVoiceSpeaker: VoiceSpeaker {
    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeakerDelegate()
    private weak var player: PlayerController?

    init(player: PlayerController) {
        self.player = player
        delegate.onDone = { [weak self] in self?.player?.duck("speaking", false) }
        synthesizer.delegate = delegate
    }

    func say(_ text: String, style: SpeechStyle) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.voice(for: style, text: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        player?.duck("speaking", true)
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        player?.duck("speaking", false)
    }

    /// Whether a Telugu voice is installed (shown in Settings).
    static var hasTeluguVoice: Bool { AVSpeechSynthesisVoice(language: "te-IN") != nil }

    private static func voice(for style: SpeechStyle, text: String) -> AVSpeechSynthesisVoice? {
        let hasTeluguScript = text.unicodeScalars.contains { (0x0C00...0x0C7F).contains($0.value) }
        if style != .english || hasTeluguScript, let telugu = AVSpeechSynthesisVoice(language: "te-IN") {
            return telugu
        }
        return AVSpeechSynthesisVoice(language: "en-IN") ?? AVSpeechSynthesisVoice(language: "en-US")
    }
}

/// The synthesizer reports on its own queue; this hops back to the main actor.
private final class SpeakerDelegate: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    nonisolated(unsafe) var onDone: (@Sendable @MainActor () -> Void)?

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        done()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        done()
    }

    private nonisolated func done() {
        let callback = onDone
        Task { @MainActor in callback?() }
    }
}
