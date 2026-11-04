import Foundation

/// Keeps "not today" exclusions between drives until local midnight. Holds only normalized
/// artist names and end times; nothing is sent anywhere.
public protocol TodayExclusionStore: AnyObject, Sendable {
    func load() -> [String: Date]
    func save(_ exclusions: [String: Date])
}

/// UserDefaults-backed store used by the app.
public final class DefaultsTodayExclusionStore: TodayExclusionStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key = "halo.drive.todayExclusions"

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: key) as? [String: Double] else { return [:] }
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    public func save(_ exclusions: [String: Date]) {
        if exclusions.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(exclusions.mapValues(\.timeIntervalSince1970), forKey: key)
        }
    }
}

/// In-memory store for tests and previews.
public final class MemoryTodayExclusionStore: TodayExclusionStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [String: Date] = [:]

    public init(_ initial: [String: Date] = [:]) {
        stored = initial
    }

    public func load() -> [String: Date] { lock.withLock { stored } }
    public func save(_ exclusions: [String: Date]) { lock.withLock { stored = exclusions } }
}
