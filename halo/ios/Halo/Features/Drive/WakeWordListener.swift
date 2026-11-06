import AVFoundation
import Speech

/// Listens for "Halo" while the app is open. Opt-in (Settings › Halo Drive), foreground only,
/// and only with on-device recognition: continuous audio never leaves the iPhone. Audio and
/// transcripts are never stored; each utterance is checked by `WakeWordDetector` and dropped.
@MainActor
@Observable
final class WakeWordListener {
    enum State: Equatable { case off, listening, paused, unavailable(String) }

    private(set) var state: State = .off
    /// Set when the wake word was heard but the command isn't finished yet.
    private(set) var heardWakeWord = false
    @ObservationIgnored var onEvent: ((WakeWordDetector.Event) -> Void)?

    @ObservationIgnored private let audio = AVAudioEngine()
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest?
    @ObservationIgnored private var task: SFSpeechRecognitionTask?
    @ObservationIgnored private var detector = WakeWordDetector()
    @ObservationIgnored private var latest = ""
    @ObservationIgnored private var pauseTimer: Task<Void, Never>?
    @ObservationIgnored private var cycleTimer: Task<Void, Never>?
    @ObservationIgnored private var locale = Locale(identifier: "en-IN")
    /// Recognition requests are restarted this often (iOS limits a single request's length).
    private let cycleSeconds: Double = 50

    /// Whether this iPhone can listen for the wake word in `locale` (on-device recognition).
    static func isSupported(locale: Locale) -> Bool {
        SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition ?? false
    }

    func start(locale: Locale) async {
        self.locale = locale
        guard await SpeechListener.authorize() else {
            state = .unavailable("Allow the microphone and speech recognition for Halo in Settings.")
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            state = .unavailable("This iPhone can't listen for “Halo” on the device in this language.")
            return
        }
        guard state != .listening else { return }
        do {
            try begin(recognizer)
            state = .listening
        } catch {
            stopAudio()
            state = .unavailable("The microphone isn't available right now.")
        }
    }

    /// Stops for good (setting off, app in the background).
    func stop() {
        stopAudio()
        state = .off
    }

    /// Steps aside while a command is being heard or Halo is speaking.
    func pause() {
        guard state == .listening else { return }
        stopAudio()
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        state = .off
        Task { await start(locale: locale) }
    }

    // MARK: Recognition

    private func begin(_ recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .mixWithOthers])
        try session.setActive(true)
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true  // never stream continuous audio to a server
        request.taskHint = .search
        request.contextualStrings = ["Halo", "Hey Halo"]
        self.request = request
        latest = ""
        heardWakeWord = false
        let input = audio.inputNode
        SpeechListener.installTap(on: input, format: input.outputFormat(forBus: 0), request: request)
        audio.prepare()
        try audio.start()
        task = SpeechListener.recognize(recognizer, request) { [weak self] text, _, isFinal, failed in
            self?.received(text, isFinal: isFinal, failed: failed)
        }
        cycleTimer?.cancel()
        cycleTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.cycleSeconds ?? 50))
            guard !Task.isCancelled else { return }
            self?.finishUtterance()
        }
    }

    private func received(_ text: String?, isFinal: Bool, failed: Bool) {
        if let text, !text.isEmpty {
            latest = text
            heardWakeWord = WakeWordDetector.heardWakeWord(text)
            // A pause ends the utterance: quicker after the wake word so commands feel live.
            pauseTimer?.cancel()
            let wait: Double = heardWakeWord ? 1.2 : 2.0
            pauseTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
                self?.finishUtterance()
            }
        }
        if isFinal || failed { finishUtterance() }
    }

    /// Checks the utterance once, forgets it, and listens again.
    private func finishUtterance() {
        guard state == .listening else { return }
        let text = latest
        let event = detector.feed(text, isFinal: true)
        stopAudio()
        state = .off
        if let event {
            state = .paused  // the app resumes listening when the command is done
            onEvent?(event)
        } else {
            Task { await start(locale: locale) }
        }
    }

    private func stopAudio() {
        pauseTimer?.cancel()
        cycleTimer?.cancel()
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        latest = ""
        heardWakeWord = false
    }
}
