import Foundation
import Observation
#if canImport(os)
import os
#endif

/// Time moves several times a second; keeping it out of `PlayerController` means only the
/// views that read it (seek bar, progress ring) redraw as a song plays.
@MainActor
@Observable
public final class PlaybackClock {
    public internal(set) var position: Double = 0
    public internal(set) var duration: Double?
    /// How far ahead the stream has loaded, in seconds from the start.
    public internal(set) var bufferedUntil: Double?

    public init() {}

    /// 0…1, or nil when the length isn't known (live radio).
    public var fraction: Double? {
        guard let duration, duration > 0 else { return nil }
        return min(max(position / duration, 0), 1)
    }

    public var bufferedFraction: Double? {
        guard let duration, duration > 0, let bufferedUntil else { return nil }
        return min(max(bufferedUntil / duration, 0), 1)
    }

    func reset(duration: Double?, position: Double = 0) {
        self.position = position
        self.duration = duration
        bufferedUntil = nil
    }
}

/// Where the audio is going (shown as "Playing on AirPods").
public struct OutputRoute: Equatable, Sendable, Codable {
    public enum Kind: String, Sendable, Codable { case speaker, headphones, bluetooth, airPlay, car, other }
    public var name: String
    public var kind: Kind

    public init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    /// The phone's own speaker isn't worth announcing.
    public var isExternal: Bool { kind != .speaker }
}

/// What the engine reports as a song plays.
public struct EngineProgress: Equatable, Sendable {
    public var position: Double
    public var duration: Double?
    public var bufferedUntil: Double?

    public init(position: Double, duration: Double? = nil, bufferedUntil: Double? = nil) {
        self.position = position
        self.duration = duration
        self.bufferedUntil = bufferedUntil
    }
}

/// The queue and position, saved so a relaunch picks up where the listener left off.
public struct PlaybackSession: Codable, Equatable, Sendable {
    public var queue: PlaybackQueue
    public var position: Double
    public var savedAt: Date

    public init(queue: PlaybackQueue, position: Double, savedAt: Date = .now) {
        self.queue = queue
        self.position = position
        self.savedAt = savedAt
    }
}

public protocol PlaybackSessionStoring: Sendable {
    func load() -> PlaybackSession?
    func save(_ session: PlaybackSession?)
}

/// Saves the session as a small JSON file in Application Support (never in iCloud backups).
public final class FilePlaybackSessionStore: PlaybackSessionStoring {
    private let url: URL

    public init(directory: URL? = nil) {
        let base = directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        var url = base.appendingPathComponent("playback-session.json")
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        self.url = url
    }

    public func load() -> PlaybackSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PlaybackSession.self, from: data)
    }

    public func save(_ session: PlaybackSession?) {
        guard let session else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard let data = try? JSONEncoder().encode(session) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

/// Technical detail about playback problems goes here, never to the screen.
enum PlaybackLog {
    #if canImport(os)
    private static let logger = Logger(subsystem: "app.halo", category: "playback")
    #endif

    static func problem(_ message: String) {
        #if canImport(os)
        logger.error("\(message, privacy: .public)")
        #endif
    }
}
