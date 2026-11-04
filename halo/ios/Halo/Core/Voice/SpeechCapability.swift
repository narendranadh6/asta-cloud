import Foundation

// Real-device speech capability detection and routing. The platform (Speech framework,
// AVFoundation) is behind `SpeechPlatform` so the rules are tested without a microphone, and
// nothing here assumes what a simulator reported: every answer comes from the device it runs on.

public enum PermissionState: String, Hashable, Sendable, Codable {
    case notDetermined, granted, denied, restricted
}

/// What the device says about recognizing one locale right now.
public struct LocaleSpeechCapability: Hashable, Sendable, Codable {
    public var localeID: String
    /// A recognizer can be created for the locale.
    public var recognizerExists: Bool
    /// It can recognize right now (network or downloaded assets permitting).
    public var available: Bool
    /// It can recognize without sending audio off the device.
    public var onDevice: Bool

    public init(localeID: String, recognizerExists: Bool, available: Bool, onDevice: Bool) {
        self.localeID = localeID
        self.recognizerExists = recognizerExists
        self.available = available
        self.onDevice = onDevice
    }

    /// Recognition works only through a server (Apple's, for the Speech framework).
    public var needsNetwork: Bool { available && !onDevice }
}

public struct SpeechVoiceInfo: Hashable, Sendable, Codable {
    public var language: String
    public var name: String
    public var quality: String

    public init(language: String, name: String, quality: String) {
        self.language = language
        self.name = name
        self.quality = quality
    }
}

public struct SpeechCapabilityReport: Hashable, Sendable, Codable {
    public var locales: [LocaleSpeechCapability]
    public var microphone: PermissionState
    public var speechRecognition: PermissionState
    public var voices: [SpeechVoiceInfo]
    public var deviceModel: String
    public var systemVersion: String
    public var isSimulator: Bool
    public var probedAt: Date

    public func capability(for localeID: String) -> LocaleSpeechCapability? {
        locales.first { $0.localeID == localeID }
    }

    /// Plain text for a device test log (no voice data).
    public var summary: String {
        var lines = ["Halo speech capabilities", "device: \(deviceModel) iOS \(systemVersion)"
                     + (isSimulator ? " (simulator)" : ""),
                     "microphone: \(microphone.rawValue), speech recognition: \(speechRecognition.rawValue)"]
        for locale in locales {
            lines.append("\(locale.localeID): recognizer=\(locale.recognizerExists) available=\(locale.available) "
                         + "on-device=\(locale.onDevice)")
        }
        let interesting = voices.filter { $0.language.hasPrefix("te") || $0.language == "en-IN" }
        lines.append("voices: " + (interesting.isEmpty ? "none for te/en-IN"
                     : interesting.map { "\($0.language) \($0.name) (\($0.quality))" }.joined(separator: ", ")))
        return lines.joined(separator: "\n")
    }
}

/// The device's speech facilities. `SystemSpeechPlatform` on iOS; fakes in tests.
public protocol SpeechPlatform: Sendable {
    func capability(forLocale localeID: String) -> LocaleSpeechCapability
    func microphonePermission() -> PermissionState
    func speechRecognitionPermission() -> PermissionState
    func installedVoices() -> [SpeechVoiceInfo]
    var deviceModel: String { get }
    var systemVersion: String { get }
    var isSimulator: Bool { get }
}

public struct SpeechCapabilityProbe: Sendable {
    /// Locales Halo asks about by default.
    public static let defaultLocales = ["te-IN", "en-IN", "en-US", "hi-IN"]

    let platform: SpeechPlatform

    public init(platform: SpeechPlatform) {
        self.platform = platform
    }

    public func run(locales: [String] = defaultLocales, now: Date = Date()) -> SpeechCapabilityReport {
        SpeechCapabilityReport(
            locales: locales.map(platform.capability(forLocale:)),
            microphone: platform.microphonePermission(),
            speechRecognition: platform.speechRecognitionPermission(),
            voices: platform.installedVoices(),
            deviceModel: platform.deviceModel,
            systemVersion: platform.systemVersion,
            isSimulator: platform.isSimulator,
            probedAt: now)
    }
}

// MARK: - Consent

/// Who would process the listener's voice or words off the device.
public enum VoiceProcessor: String, Hashable, Sendable, Codable, CaseIterable {
    /// Apple's Speech framework when on-device recognition isn't available for the locale.
    case appleSpeech
    /// A speech provider run for Halo (none is configured yet).
    case haloServerSpeech
    /// Halo's optional text fallback for commands the phone couldn't understand.
    case intentFallback
}

public struct ConsentRecord: Hashable, Sendable, Codable {
    public enum Choice: String, Hashable, Sendable, Codable { case granted, declined }
    public var choice: Choice
    public var decidedAt: Date
    /// The disclosure version the listener saw; a new version asks again.
    public var disclosureVersion: Int
}

public protocol VoiceConsentStore: AnyObject, Sendable {
    func load() -> [VoiceProcessor: ConsentRecord]
    func save(_ records: [VoiceProcessor: ConsentRecord])
}

/// What the listener is told before anything leaves the device. Wording about third parties
/// points to their own terms; Halo only states what Halo itself does.
public struct ProcessingDisclosure: Hashable, Sendable {
    public var processor: VoiceProcessor
    public var version: Int
    public var title: String
    public var whatLeaves: String
    public var processedBy: String
    public var retention: String
    public var policyURL: URL?

    public static func of(_ processor: VoiceProcessor) -> ProcessingDisclosure {
        switch processor {
        case .appleSpeech:
            ProcessingDisclosure(
                processor: processor, version: 1, title: "Use Apple's speech recognition?",
                whatLeaves: "While you hold Talk to Halo, the audio of what you say is sent to Apple to turn it "
                    + "into text, because this iPhone can't recognize this language on the device.",
                processedBy: "Apple, through the iOS Speech framework.",
                retention: "Halo receives only the text, uses it for that one command, and doesn't store the "
                    + "audio or the text. Apple's handling is covered by Apple's privacy policy.",
                policyURL: URL(string: "https://www.apple.com/legal/privacy/"))
        case .haloServerSpeech:
            ProcessingDisclosure(
                processor: processor, version: 1, title: "Use Halo's server speech recognition?",
                whatLeaves: "The audio of what you say while Talk to Halo is active.",
                processedBy: "Not available: no server speech provider is set up.",
                retention: "Not available.", policyURL: nil)
        case .intentFallback:
            ProcessingDisclosure(
                processor: processor, version: 1, title: "Send unclear commands to Halo's server?",
                whatLeaves: "Only the text of a command the phone couldn't understand (never audio), with the "
                    + "session's language.",
                processedBy: "Halo's server, which may use a language model provider configured by Halo.",
                retention: "The text is used for that one request and isn't stored by Halo.", policyURL: nil)
        }
    }
}

/// The listener's choices, revocable at any time. Nothing is ever granted by default.
@MainActor
public final class VoiceConsent {
    private let store: VoiceConsentStore
    private var records: [VoiceProcessor: ConsentRecord]

    public init(store: VoiceConsentStore) {
        self.store = store
        records = store.load()
    }

    public func isGranted(_ processor: VoiceProcessor) -> Bool {
        guard let record = records[processor] else { return false }
        return record.choice == .granted && record.disclosureVersion == ProcessingDisclosure.of(processor).version
    }

    /// True when the listener hasn't answered the current disclosure yet.
    public func needsAnswer(_ processor: VoiceProcessor) -> Bool {
        guard let record = records[processor] else { return true }
        return record.disclosureVersion != ProcessingDisclosure.of(processor).version
    }

    public func record(_ choice: ConsentRecord.Choice, for processor: VoiceProcessor, at date: Date = Date()) {
        records[processor] = ConsentRecord(choice: choice, decidedAt: date,
                                           disclosureVersion: ProcessingDisclosure.of(processor).version)
        store.save(records)
    }

    public func revoke(_ processor: VoiceProcessor, at date: Date = Date()) {
        record(.declined, for: processor, at: date)
    }
}

// MARK: - Routing

/// How the next "Talk to Halo" will be understood.
public enum SpeechRoute: Hashable, Sendable {
    /// Recognized on the iPhone; no audio leaves it.
    case onDevice(localeID: String)
    /// Apple's server recognition, only after the listener agreed.
    case appleServer(localeID: String)
    /// Halo's own server recognition (not configured in this build).
    case haloServer(localeID: String)
    /// Type instead, and why.
    case textInput(TextInputReason)
}

public enum TextInputReason: Hashable, Sendable {
    case permissionDenied
    /// Ask before using a server: the consent screen comes first.
    case consentNeeded(VoiceProcessor)
    case consentDeclined
    case unavailable
}

public enum SpeechRoutePlanner {
    /// On-device first; a server only with consent; otherwise typing.
    public static func route(locale localeID: String, report: SpeechCapabilityReport,
                             appleConsent: (granted: Bool, unanswered: Bool),
                             haloServerConfigured: Bool = false, haloServerConsent: Bool = false) -> SpeechRoute {
        if [.denied, .restricted].contains(report.microphone)
            || [.denied, .restricted].contains(report.speechRecognition) {
            return .textInput(.permissionDenied)
        }
        let capability = report.capability(for: localeID)
        if let capability, capability.available, capability.onDevice {
            return .onDevice(localeID: localeID)
        }
        if let capability, capability.available {
            if appleConsent.granted { return .appleServer(localeID: localeID) }
            if appleConsent.unanswered { return .textInput(.consentNeeded(.appleSpeech)) }
        }
        if haloServerConfigured && haloServerConsent { return .haloServer(localeID: localeID) }
        return capability?.available == true ? .textInput(.consentDeclined) : .textInput(.unavailable)
    }
}
