#if canImport(Speech) && os(iOS)
import AVFoundation
import Speech
import XCTest
@testable import Halo

/// Halo Drive spike: records which speech recognizers and voices this iOS build offers for
/// Telugu and Indian English. Prints lines prefixed "HALO-SPIKE:" (CI shows them) and never
/// fails; it needs no permission because it only reads what is supported.
final class SpeechSupportDiagnostics: XCTestCase {
    func testReportSpeechSupportForHaloDrive() async {
        let locales = SFSpeechRecognizer.supportedLocales().map(\.identifier).sorted()
        let indian = locales.filter { $0.hasSuffix("-IN") || $0.hasSuffix("_IN") || $0.hasPrefix("te") }
        print("HALO-SPIKE: SFSpeechRecognizer locales=\(locales.count) indian=\(indian)")
        for identifier in ["te-IN", "en-IN", "hi-IN"] {
            let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier))
            print("HALO-SPIKE: SFSpeechRecognizer \(identifier) exists=\(recognizer != nil) "
                  + "available=\(recognizer?.isAvailable ?? false) "
                  + "onDevice=\(recognizer?.supportsOnDeviceRecognition ?? false)")
        }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let transcriber = await SpeechTranscriber.supportedLocales.map(\.identifier).sorted()
            print("HALO-SPIKE: SpeechTranscriber locales=\(transcriber.count) "
                  + "telugu=\(transcriber.filter { $0.hasPrefix("te") }) "
                  + "indianEnglish=\(transcriber.filter { $0.hasPrefix("en") && $0.hasSuffix("IN") })")
        }
        #endif
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let telugu = voices.filter { $0.language.hasPrefix("te") }.map { "\($0.language) \($0.name)" }
        let indianEnglish = voices.filter { $0.language == "en-IN" }.map(\.name)
        print("HALO-SPIKE: voices telugu=\(telugu) en-IN=\(indianEnglish)")
    }

    /// The same probe the app uses on a real iPhone (Settings › Voice & privacy).
    @MainActor
    func testCapabilityProbeReport() async {
        let report = SpeechCapabilityProbe(platform: SystemSpeechPlatform()).run()
        for line in report.summary.split(separator: "\n") { print("HALO-SPIKE: probe \(line)") }
        let route = SpeechRoutePlanner.route(locale: "en-IN", report: report, appleConsent: (false, true))
        print("HALO-SPIKE: probe route en-IN without consent = \(route)")
    }
}
#endif
