import Foundation

/// Where playback is right now. Every screen derives its look from this one value, so the
/// mini player, Now Playing and the lock screen can't disagree.
public enum PlaybackPhase: Equatable, Sendable {
    case idle
    /// Getting a fresh stream link for the track (restored sessions, retry after a failure).
    case resolving
    /// The stream is opening; no audio yet.
    case loading
    /// Audio started, then ran out of data; it resumes by itself.
    case buffering
    case playing
    case paused
    /// Waiting for the engine to land on `target`. `resume` says whether to play afterwards.
    case seeking(target: Double, resume: Bool)
    /// The queue finished.
    case ended
    case failed(PlaybackIssue)

    /// The listener wants sound: the play/pause button shows "pause".
    public var wantsToPlay: Bool {
        switch self {
        case .resolving, .loading, .buffering, .playing: true
        case let .seeking(_, resume): resume
        case .idle, .paused, .ended, .failed: false
        }
    }

    /// Something is in progress that isn't audible yet (drives the Halo Ring).
    public var isWaiting: Bool {
        switch self {
        case .resolving, .loading, .buffering: true
        case let .seeking(_, resume): resume
        default: false
        }
    }

    public var issue: PlaybackIssue? {
        if case let .failed(issue) = self { return issue }
        return nil
    }
}

/// What the engine reports about the audio itself.
public enum EngineStatus: Equatable, Sendable {
    /// Waiting for data (opening or stalled).
    case waiting
    case playing
    /// Stopped by the system (headphones unplugged, a phone call), not by Halo.
    case paused
}

/// Things that move playback from one phase to another.
public enum PlaybackEvent: Equatable, Sendable {
    case resolve
    case load
    case engine(EngineStatus)
    case userPlay
    case userPause
    case seekStarted(Double)
    case seekFinished
    case reachedEnd
    case failed(PlaybackIssue)
    case stop
}

extension PlaybackPhase {
    /// The single place playback rules live. Unknown combinations keep the current phase.
    public func applying(_ event: PlaybackEvent) -> PlaybackPhase {
        switch (self, event) {
        case (_, .stop): return .idle
        case (_, .resolve): return .resolving
        case (_, .load): return .loading
        case let (_, .failed(issue)): return .failed(issue)

        case (.loading, .engine(.playing)), (.buffering, .engine(.playing)): return .playing
        case (.playing, .engine(.waiting)): return .buffering
        case (.playing, .engine(.paused)), (.buffering, .engine(.paused)): return .paused
        // Resumed by the system after an interruption ended.
        case (.paused, .engine(.playing)): return .playing

        case (.paused, .userPlay), (.ended, .userPlay): return .playing
        case (.loading, .userPause), (.buffering, .userPause), (.playing, .userPause),
             (.resolving, .userPause):
            return .paused

        case let (.playing, .seekStarted(target)), let (.buffering, .seekStarted(target)),
             let (.loading, .seekStarted(target)):
            return .seeking(target: target, resume: true)
        case let (.paused, .seekStarted(target)), let (.ended, .seekStarted(target)):
            return .seeking(target: target, resume: false)
        case let (.seeking(_, resume), .seekStarted(target)):
            return .seeking(target: target, resume: resume)
        case let (.seeking(target, _), .userPlay): return .seeking(target: target, resume: true)
        case let (.seeking(target, _), .userPause): return .seeking(target: target, resume: false)
        case let (.seeking(_, resume), .seekFinished): return resume ? .playing : .paused

        case (.playing, .reachedEnd), (.buffering, .reachedEnd), (.paused, .reachedEnd),
             (.resolving, .reachedEnd):
            return .ended
        default: return self
        }
    }
}

/// A problem the listener can understand and act on. Technical detail goes to the log only.
public enum PlaybackIssue: Equatable, Sendable {
    case offline
    /// The song can't be streamed from its source any more.
    case unavailable
    /// The source didn't answer; trying again may work.
    case sourceDown
    case stationDown
    case nothingPlayable

    public enum Action: String, Sendable, CaseIterable {
        case retry, skip, playSimilar
    }

    public var title: String {
        switch self {
        case .offline: "You're offline"
        case .unavailable: "This song isn't available right now"
        case .sourceDown: "Couldn't reach this song's source"
        case .stationDown: "This station isn't responding"
        case .nothingPlayable: "Nothing here can be played"
        }
    }

    public var message: String {
        switch self {
        case .offline: "Connect to the internet to keep listening."
        case .unavailable: "It may have been removed by the artist. Try something similar."
        case .sourceDown: "Try again in a moment, or skip to the next song."
        case .stationDown: "Try another station."
        case .nothingPlayable: "These songs can't be streamed at the moment."
        }
    }

    public var actions: [Action] {
        switch self {
        case .offline, .sourceDown: [.retry, .skip]
        case .unavailable: [.playSimilar, .skip]
        case .stationDown: [.retry]
        case .nothingPlayable: []
        }
    }
}

/// Why the engine couldn't play, as classified on the device.
public struct EngineFailure: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case offline, unavailable, unknown }
    public var kind: Kind
    /// For the log only; never shown.
    public var detail: String

    public init(_ kind: Kind, detail: String = "") {
        self.kind = kind
        self.detail = detail
    }
}
