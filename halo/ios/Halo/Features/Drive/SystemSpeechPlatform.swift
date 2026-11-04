import AVFoundation
import Speech
import UIKit

/// The real device's speech facilities, read fresh each time (availability can change with
/// the network or downloaded language assets).
struct SystemSpeechPlatform: SpeechPlatform {
    func capability(forLocale localeID: String) -> LocaleSpeechCapability {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else {
            return LocaleSpeechCapability(localeID: localeID, recognizerExists: false, available: false, onDevice: false)
        }
        return LocaleSpeechCapability(localeID: localeID, recognizerExists: true, available: recognizer.isAvailable,
                                      onDevice: recognizer.supportsOnDeviceRecognition)
    }

    func microphonePermission() -> PermissionState {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: .granted
        case .denied: .denied
        default: .notDetermined
        }
    }

    func speechRecognitionPermission() -> PermissionState {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: .granted
        case .denied: .denied
        case .restricted: .restricted
        default: .notDetermined
        }
    }

    func installedVoices() -> [SpeechVoiceInfo] {
        AVSpeechSynthesisVoice.speechVoices().map { voice in
            let quality = switch voice.quality {
            case .enhanced: "enhanced"
            case .premium: "premium"
            default: "default"
            }
            return SpeechVoiceInfo(language: voice.language, name: voice.name, quality: quality)
        }
    }

    var deviceModel: String { MainActor.assumeIsolated { UIDevice.current.model } }
    var systemVersion: String { MainActor.assumeIsolated { UIDevice.current.systemVersion } }

    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
