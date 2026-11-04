import SwiftUI

/// Settings › Voice & privacy: what may leave the iPhone (each can be revoked), what this
/// iPhone can actually recognize, and a speech test for recording-based evaluation.
struct VoiceSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(AppSettings.self) private var settings
    @State private var report: SpeechCapabilityReport?
    @State private var pending: ProcessingDisclosure?
    @State private var revision = 0

    var body: some View {
        List {
            Section {
                consentToggle(.appleSpeech)
                consentToggle(.intentFallback)
                LabeledContent("Halo server speech", value: "Not available")
            } header: {
                Text("Allowed to leave this iPhone")
            } footer: {
                Text("Off by default. Halo never records all the time: it listens only while you hold "
                     + "Talk to Halo, and never saves audio or transcripts.")
            }

            Section {
                if let report {
                    ForEach(report.locales, id: \.localeID) { locale in
                        LabeledContent(locale.localeID, value: describe(locale))
                    }
                    LabeledContent("Microphone", value: report.microphone.rawValue)
                    LabeledContent("Speech recognition", value: report.speechRecognition.rawValue)
                    LabeledContent("Telugu voice", value: report.voices.contains { $0.language.hasPrefix("te") }
                                   ? "installed" : "not installed")
                    ShareLink(item: report.summary) { Label("Share this report", systemImage: "square.and.arrow.up") }
                } else {
                    ProgressView()
                }
                Button("Check again") { probe() }
            } header: {
                Text("This iPhone")
            } footer: {
                Text("Checked on this device now; results differ between iPhones, iOS versions and the simulator.")
            }

            Section {
                NavigationLink("Speech test") { SpeechTestView() }
            } footer: {
                Text("Read a few commands aloud to measure recognition on this iPhone. Only the recognized "
                     + "text is kept, on this device, until you share or clear it.")
            }
        }
        .navigationTitle("Voice & privacy")
        .onAppear(perform: probe)
        .sheet(item: Binding(get: { pending.map(DisclosureItem.init) }, set: { if $0 == nil { pending = nil } })) { item in
            VoiceConsentView(disclosure: item.disclosure) { granted in
                app.voiceConsent.record(granted ? .granted : .declined, for: item.disclosure.processor)
                pending = nil
                revision += 1
            }
        }
    }

    private func consentToggle(_ processor: VoiceProcessor) -> some View {
        let disclosure = ProcessingDisclosure.of(processor)
        return Toggle(isOn: Binding(
            get: { _ = revision; return app.voiceConsent.isGranted(processor) },
            set: { on in
                if on { pending = disclosure } else { app.voiceConsent.revoke(processor); revision += 1 }
            })) {
            Text(processor == .appleSpeech ? "Apple speech recognition" : "Unclear commands to Halo's server")
        }
    }

    private func describe(_ locale: LocaleSpeechCapability) -> String {
        if !locale.recognizerExists { return "not supported" }
        if !locale.available { return "unavailable now" }
        return locale.onDevice ? "on this iPhone" : "needs Apple's server"
    }

    private func probe() {
        report = SpeechCapabilityProbe(platform: SystemSpeechPlatform()).run()
    }
}

private struct DisclosureItem: Identifiable {
    var disclosure: ProcessingDisclosure
    var id: String { disclosure.processor.rawValue }
}

/// Reads prompts one by one, recognizes them on this iPhone, and scores each.
struct SpeechTestView: View {
    @Environment(AppModel.self) private var app
    @State private var index = 0
    @State private var results: [SpeechEvaluationResult] = []
    @State private var listening = false
    @State private var message: String?
    @State private var listener = SpeechListener()

    private let prompts = SpeechEvaluationPrompt.starterSheet

    var body: some View {
        List {
            Section("Read this aloud") {
                Text(prompts[index].text).font(.title3.weight(.semibold))
                Text("\(prompts[index].localeID) · \(prompts[index].form)").font(.footnote)
                Button(listening ? "Listening…" : "Record") { record() }.disabled(listening)
                if let message { Text(message).font(.footnote) }
            }
            if !results.isEmpty {
                Section("Results (\(results.count))") {
                    ForEach(results, id: \.self) { result in
                        VStack(alignment: .leading) {
                            Text("\(result.promptID): \(result.transcript)").font(.subheadline)
                            Text(String(format: "WER %.2f · %@ · %@ · %d ms", result.wordErrorRate,
                                        result.intentMatches ? "understood" : "not understood",
                                        result.route, result.latencyMs)).font(.footnote)
                        }
                    }
                    ShareLink(item: exportText) { Label("Share results (text only)", systemImage: "square.and.arrow.up") }
                    Button("Clear results", role: .destructive) { results = [] }
                }
            }
        }
        .navigationTitle("Speech test")
    }

    private var exportText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(results)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private func record() {
        let prompt = prompts[index]
        let report = SpeechCapabilityProbe(platform: SystemSpeechPlatform()).run(locales: [prompt.localeID])
        let route = SpeechRoutePlanner.route(
            locale: prompt.localeID, report: report,
            appleConsent: (app.voiceConsent.isGranted(.appleSpeech), app.voiceConsent.needsAnswer(.appleSpeech)))
        let requireOnDevice: Bool
        switch route {
        case .onDevice: requireOnDevice = true
        case .appleServer: requireOnDevice = false
        default:
            message = "Not recognizable on this iPhone without consent (\(SpeechEvaluation.describe(route)))."
            return
        }
        listening = true
        message = nil
        let start = Date()
        Task {
            defer { listening = false }
            do {
                let heard = try await listener.listen(locale: Locale(identifier: prompt.localeID),
                                                      requireOnDevice: requireOnDevice)
                let latency = Int(Date().timeIntervalSince(start) * 1000)
                results.append(SpeechEvaluation.score(prompt: prompt, transcript: heard.text, route: route,
                                                      latencyMs: latency))
                index = (index + 1) % prompts.count
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
