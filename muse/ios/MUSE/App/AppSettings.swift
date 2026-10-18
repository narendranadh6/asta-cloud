import Foundation
import Observation

/// Device-local preferences backed by UserDefaults. Nothing here is sensitive; the
/// API token lives in the Keychain.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var browserPreference: BrowserDestination {
        didSet { defaults.set(browserPreference.rawValue, forKey: Keys.browser) }
    }
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }
    var personalizationEnabled: Bool {
        didSet { defaults.set(personalizationEnabled, forKey: Keys.personalization) }
    }
    var syncPlaylists: Bool {
        didSet { defaults.set(syncPlaylists, forKey: Keys.sync) }
    }
    var glowEffects: Bool {
        didSet { defaults.set(glowEffects, forKey: Keys.glow) }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) }
    }
    var weeklyDiscoveryReminder: Bool {
        didSet { defaults.set(weeklyDiscoveryReminder, forKey: Keys.reminder) }
    }
    var displayName: String {
        didSet { defaults.set(displayName, forKey: Keys.name) }
    }
    var activeMood: Mood? {
        didSet { defaults.set(activeMood?.rawValue, forKey: Keys.mood) }
    }
    var preferredLanguage: String? {
        didSet { defaults.set(preferredLanguage, forKey: Keys.language) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        browserPreference = BrowserDestination(
            rawValue: defaults.string(forKey: Keys.browser) ?? "") ?? .brave
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        personalizationEnabled = defaults.bool(forKey: Keys.personalization)
        syncPlaylists = defaults.object(forKey: Keys.sync) as? Bool ?? true
        glowEffects = defaults.object(forKey: Keys.glow) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        weeklyDiscoveryReminder = defaults.bool(forKey: Keys.reminder)
        displayName = defaults.string(forKey: Keys.name) ?? ""
        activeMood = defaults.string(forKey: Keys.mood).flatMap(Mood.init(rawValue:))
        preferredLanguage = defaults.string(forKey: Keys.language)
    }

    func reset() {
        for key in Keys.all { defaults.removeObject(forKey: key) }
        browserPreference = .brave
        hasCompletedOnboarding = false
        personalizationEnabled = false
        syncPlaylists = true
        glowEffects = true
        hapticsEnabled = true
        weeklyDiscoveryReminder = false
        displayName = ""
        activeMood = nil
        preferredLanguage = nil
    }

    private enum Keys {
        static let browser = "muse.browserPreference"
        static let onboarding = "muse.onboardingCompleted"
        static let personalization = "muse.personalizationEnabled"
        static let sync = "muse.syncPlaylists"
        static let glow = "muse.glowEffects"
        static let haptics = "muse.haptics"
        static let reminder = "muse.weeklyReminder"
        static let name = "muse.displayName"
        static let mood = "muse.activeMood"
        static let language = "muse.preferredLanguage"
        static let all = [browser, onboarding, personalization, sync, glow, haptics, reminder,
                          name, mood, language]
    }
}
