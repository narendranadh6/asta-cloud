import Foundation
import Observation

/// Device-local preferences backed by UserDefaults. Nothing here is sensitive; the
/// API token lives in the Keychain.
@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    /// Halo Flow: keep playing related music when the queue runs out.
    var autoplay: Bool {
        didSet { defaults.set(autoplay, forKey: Keys.autoplay) }
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
    /// Energy level from Mood Hub (0–100), used as a default in Playlist Studio.
    var preferredEnergy: Int? {
        didSet { defaults.set(preferredEnergy, forKey: Keys.energy) }
    }
    var discovery: DiscoveryPreference {
        didSet { defaults.set(discovery.rawValue, forKey: Keys.discovery) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoplay = defaults.object(forKey: Keys.autoplay) as? Bool ?? true
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
        personalizationEnabled = defaults.bool(forKey: Keys.personalization)
        syncPlaylists = defaults.object(forKey: Keys.sync) as? Bool ?? true
        glowEffects = defaults.object(forKey: Keys.glow) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Keys.haptics) as? Bool ?? true
        weeklyDiscoveryReminder = defaults.bool(forKey: Keys.reminder)
        displayName = defaults.string(forKey: Keys.name) ?? ""
        activeMood = defaults.string(forKey: Keys.mood).flatMap(Mood.init(rawValue:))
        preferredLanguage = defaults.string(forKey: Keys.language)
        preferredEnergy = defaults.object(forKey: Keys.energy) as? Int
        discovery = DiscoveryPreference(rawValue: defaults.string(forKey: Keys.discovery) ?? "")
            ?? .balanced
    }

    func reset() {
        for key in Keys.all { defaults.removeObject(forKey: key) }
        autoplay = true
        hasCompletedOnboarding = false
        personalizationEnabled = false
        syncPlaylists = true
        glowEffects = true
        hapticsEnabled = true
        weeklyDiscoveryReminder = false
        displayName = ""
        activeMood = nil
        preferredLanguage = nil
        preferredEnergy = nil
        discovery = .balanced
    }

    private enum Keys {
        static let autoplay = "halo.autoplay"
        static let onboarding = "halo.onboardingCompleted"
        static let personalization = "halo.personalizationEnabled"
        static let sync = "halo.syncPlaylists"
        static let glow = "halo.glowEffects"
        static let haptics = "halo.haptics"
        static let reminder = "halo.weeklyReminder"
        static let name = "halo.displayName"
        static let mood = "halo.activeMood"
        static let language = "halo.preferredLanguage"
        static let energy = "halo.preferredEnergy"
        static let discovery = "halo.discovery"
        static let all = [autoplay, onboarding, personalization, sync, glow, haptics, reminder,
                          name, mood, language, energy, discovery]
    }
}
