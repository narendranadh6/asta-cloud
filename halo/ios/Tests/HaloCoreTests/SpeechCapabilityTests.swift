import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

struct FakeSpeechPlatform: SpeechPlatform {
    var locales: [String: LocaleSpeechCapability] = [:]
    var microphone: PermissionState = .granted
    var speech: PermissionState = .granted
    var voices: [SpeechVoiceInfo] = []

    func capability(forLocale localeID: String) -> LocaleSpeechCapability {
        locales[localeID] ?? LocaleSpeechCapability(localeID: localeID, recognizerExists: false,
                                                    available: false, onDevice: false)
    }
    func microphonePermission() -> PermissionState { microphone }
    func speechRecognitionPermission() -> PermissionState { speech }
    func installedVoices() -> [SpeechVoiceInfo] { voices }
    var deviceModel: String { "iPhone (test)" }
    var systemVersion: String { "26.0" }
    var isSimulator: Bool { false }
}

final class SpeechRoutingTests: XCTestCase {
    private func report(_ platform: FakeSpeechPlatform) -> SpeechCapabilityReport {
        SpeechCapabilityProbe(platform: platform).run(now: Date(timeIntervalSince1970: 0))
    }

    private let onDevice = LocaleSpeechCapability(localeID: "en-IN", recognizerExists: true, available: true, onDevice: true)
    private let serverOnly = LocaleSpeechCapability(localeID: "en-IN", recognizerExists: true, available: true, onDevice: false)

    func testOnDeviceIsUsedWhenTheDeviceCan() {
        let r = report(FakeSpeechPlatform(locales: ["en-IN": onDevice]))
        XCTAssertEqual(SpeechRoutePlanner.route(locale: "en-IN", report: r, appleConsent: (false, true)),
                       .onDevice(localeID: "en-IN"))
    }

    func testServerRecognitionNeedsConsentFirst() {
        let r = report(FakeSpeechPlatform(locales: ["en-IN": serverOnly]))
        XCTAssertEqual(SpeechRoutePlanner.route(locale: "en-IN", report: r, appleConsent: (false, true)),
                       .textInput(.consentNeeded(.appleSpeech)))
        XCTAssertEqual(SpeechRoutePlanner.route(locale: "en-IN", report: r, appleConsent: (false, false)),
                       .textInput(.consentDeclined))
        XCTAssertEqual(SpeechRoutePlanner.route(locale: "en-IN", report: r, appleConsent: (true, false)),
                       .appleServer(localeID: "en-IN"))
        XCTAssertTrue(r.capability(for: "en-IN")!.needsNetwork)
    }

    func testMissingLocalesAndDeniedPermissionsFallBackToTyping() {
        let r = report(FakeSpeechPlatform())
        XCTAssertEqual(SpeechRoutePlanner.route(locale: "te-IN", report: r, appleConsent: (true, false)),
                       .textInput(.unavailable))
        let denied = report(FakeSpeechPlatform(locales: ["en-IN": onDevice], microphone: .denied))
        XCTAssertEqual(SpeechRoutePlanner.route(locale: "en-IN", report: denied, appleConsent: (true, false)),
                       .textInput(.permissionDenied))
        // Halo's own server is never used unless configured and agreed to.
        XCTAssertEqual(SpeechRoutePlanner.route(locale: "te-IN", report: r, appleConsent: (false, false),
                                                haloServerConfigured: false, haloServerConsent: true),
                       .textInput(.unavailable))
    }

    func testReportSummaryHasNoVoiceDataAndNamesTheDevice() {
        let r = report(FakeSpeechPlatform(locales: ["en-IN": serverOnly],
                                          voices: [SpeechVoiceInfo(language: "te-IN", name: "Geeta", quality: "default")]))
        XCTAssertTrue(r.summary.contains("en-IN: recognizer=true available=true on-device=false"))
        XCTAssertTrue(r.summary.contains("te-IN Geeta"))
        XCTAssertFalse(r.summary.contains("simulator"))
    }
}

@MainActor
final class VoiceConsentTests: XCTestCase {
    func testNothingIsGrantedByDefaultAndConsentIsRevocable() async {
        let store = MemoryVoiceConsentStore()
        let consent = VoiceConsent(store: store)
        for processor in VoiceProcessor.allCases {
            XCTAssertFalse(consent.isGranted(processor))
            XCTAssertTrue(consent.needsAnswer(processor))
        }
        consent.record(.granted, for: .appleSpeech)
        XCTAssertTrue(VoiceConsent(store: store).isGranted(.appleSpeech))  // persisted
        consent.revoke(.appleSpeech)
        XCTAssertFalse(VoiceConsent(store: store).isGranted(.appleSpeech))
        XCTAssertFalse(consent.needsAnswer(.appleSpeech))  // declined is an answer
    }

    func testDisclosuresSayWhatLeavesWhoProcessesItAndRetention() async {
        for processor in VoiceProcessor.allCases {
            let d = ProcessingDisclosure.of(processor)
            XCTAssertFalse(d.whatLeaves.isEmpty)
            XCTAssertFalse(d.processedBy.isEmpty)
            XCTAssertFalse(d.retention.isEmpty)
        }
        XCTAssertTrue(ProcessingDisclosure.of(.intentFallback).whatLeaves.contains("never audio"))
        XCTAssertTrue(ProcessingDisclosure.of(.haloServerSpeech).processedBy.contains("Not available"))
    }
}

final class SpeechEvaluationTests: XCTestCase {
    func testWordErrorRate() {
        XCTAssertEqual(SpeechEvaluation.wordErrorRate(reference: "Kotha Telugu songs pettu", hypothesis: "kotha telugu songs pettu"), 0)
        XCTAssertEqual(SpeechEvaluation.wordErrorRate(reference: "Kotha Telugu songs pettu", hypothesis: "kota telugu songs"), 0.5, accuracy: 0.001)
        XCTAssertEqual(SpeechEvaluation.wordErrorRate(reference: "తెలుగు పాటలు పెట్టు", hypothesis: "తెలుగు పాటలు పెట్టు"), 0)
    }

    func testIntentMatchIsJudgedOnMeaningNotSpelling() {
        let prompt = SpeechEvaluationPrompt(id: "x", text: "Kotha Telugu songs pettu", localeID: "en-IN", form: "romanized")
        let close = SpeechEvaluation.score(prompt: prompt, transcript: "kotta telugu songs petu", route: .onDevice(localeID: "en-IN"), latencyMs: 900)
        let wrong = SpeechEvaluation.score(prompt: prompt, transcript: "call telugu", route: .onDevice(localeID: "en-IN"), latencyMs: 900)
        XCTAssertFalse(wrong.intentMatches)
        XCTAssertGreaterThan(close.wordErrorRate, 0)
        XCTAssertEqual(close.route, "on-device")
        XCTAssertTrue(SpeechEvaluationPrompt.starterSheet.allSatisfy { IntentInterpreter.interpret($0.text).outcome == .execute })
    }
}
