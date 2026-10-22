import AVFoundation
import Speech

/// Push-to-talk speech recognition. Listens until the listener stops talking (or taps again),
/// then returns the transcript. Audio is never stored or uploaded by Halo; recognition runs on
/// the device whenever iOS supports it for the chosen language.
@MainActor
final class SpeechListener {
    struct Heard: Sendable {
        var text: String
        var confidence: Double
    }

    enum ListenError: LocalizedError {
        case notAllowed, unavailable, nothingHeard

        var errorDescription: String? {
            switch self {
            case .notAllowed: "Allow the microphone and speech recognition for Halo in Settings."
            case .unavailable: "Speech recognition isn't available right now."
            case .nothingHeard: "Didn't catch that."
            }
        }
    }

    /// The words heard so far, for the live caption.
    var onPartial: ((String) -> Void)?

    private let audio = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var continuation: CheckedContinuation<Heard, any Error>?
    private var best: Heard?
    private var timer: Task<Void, Never>?
    /// Seconds of quiet that end a sentence.
    private let pause: Double = 1.4
    private let maxLength: Double = 10

    /// Locales that recognize speech on this device, from the ones Halo asks for.
    static func supported(_ identifiers: [String]) -> [String] {
        let available = SFSpeechRecognizer.supportedLocales().map(\.identifier)
        return identifiers.filter { id in
            available.contains { $0.replacingOccurrences(of: "_", with: "-") == id }
        }
    }

    nonisolated static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func listen(locale: Locale) async throws -> Heard {
        cancel()
        guard await Self.authorize() else { throw ListenError.notAllowed }
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw ListenError.unavailable
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.defaultToSpeaker, .allowBluetoothA2DP, .allowBluetooth])
        try session.setActive(true)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .search
        request.addsPunctuation = false
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.contextualStrings = ["Halo", "Telugu", "English", "pettu", "vaddu", "inka"]
        self.request = request
        best = nil

        let input = audio.inputNode
        Self.installTap(on: input, format: input.outputFormat(forBus: 0), request: request)
        audio.prepare()
        do {
            try audio.start()
        } catch {
            teardown()
            throw ListenError.unavailable
        }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            task = Self.recognize(recognizer, request) { [weak self] text, confidence, isFinal, failed in
                self?.received(text, confidence: confidence, isFinal: isFinal, failed: failed)
            }
            restartTimer(after: maxLength)
        }
    }

    /// The listener tapped again: finish with what was heard.
    func stop() {
        guard continuation != nil else { return }
        endAudio()
    }

    func cancel() {
        guard let continuation else { return }
        self.continuation = nil
        teardown()
        continuation.resume(throwing: CancellationError())
    }

    // MARK: Recognition

    private func received(_ text: String?, confidence: Double, isFinal: Bool, failed: Bool) {
        if let text, !text.isEmpty {
            best = Heard(text: text, confidence: confidence > 0 ? confidence : best?.confidence ?? 0.8)
            onPartial?(text)
            if !isFinal { restartTimer(after: pause) }
        }
        if isFinal || failed { finish() }
    }

    /// Stops the microphone; the recognizer then delivers its final result.
    private func endAudio() {
        audio.stop()
        audio.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            self?.finish()
        }
    }

    private func restartTimer(after seconds: Double) {
        timer?.cancel()
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.endAudio()
        }
    }

    private func finish() {
        guard let continuation else { return }
        self.continuation = nil
        let heard = best
        teardown()
        if let heard, !heard.text.trimmingCharacters(in: .whitespaces).isEmpty {
            continuation.resume(returning: heard)
        } else {
            continuation.resume(throwing: ListenError.nothingHeard)
        }
    }

    private func teardown() {
        timer?.cancel()
        timer = nil
        if audio.isRunning { audio.stop() }
        audio.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        // Back to plain playback so music sounds as it should.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    }

    // Speech and audio callbacks arrive on their own queues; these are built outside the main
    // actor so Swift doesn't assert they run on main, and hop there explicitly.

    private nonisolated static func installTap(
        on node: AVAudioInputNode, format: AVAudioFormat, request: SFSpeechAudioBufferRecognitionRequest
    ) {
        node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    private nonisolated static func recognize(
        _ recognizer: SFSpeechRecognizer, _ request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable @MainActor (String?, Double, Bool, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let segments = result?.bestTranscription.segments ?? []
            let confidence = segments.isEmpty ? 0
                : segments.map { Double($0.confidence) }.reduce(0, +) / Double(segments.count)
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in handler(text, confidence, isFinal, failed) }
        }
    }
}
