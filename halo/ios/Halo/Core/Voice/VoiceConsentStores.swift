import Foundation

/// UserDefaults-backed consent records (choices and dates only).
public final class DefaultsVoiceConsentStore: VoiceConsentStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "halo.voice.consent"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [VoiceProcessor: ConsentRecord] {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: ConsentRecord].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: decoded.compactMap { key, value in
            VoiceProcessor(rawValue: key).map { ($0, value) }
        })
    }

    public func save(_ records: [VoiceProcessor: ConsentRecord]) {
        let encodable = Dictionary(uniqueKeysWithValues: records.map { ($0.key.rawValue, $0.value) })
        defaults.set(try? JSONEncoder().encode(encodable), forKey: key)
    }
}

public final class MemoryVoiceConsentStore: VoiceConsentStore, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [VoiceProcessor: ConsentRecord] = [:]

    public init() {}

    public func load() -> [VoiceProcessor: ConsentRecord] { lock.withLock { records } }
    public func save(_ records: [VoiceProcessor: ConsentRecord]) { lock.withLock { self.records = records } }
}
