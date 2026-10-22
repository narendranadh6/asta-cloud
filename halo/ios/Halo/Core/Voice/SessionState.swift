import Foundation

/// One steering target, remembering whether the listener asked for it or Halo inferred it.
public struct VibeTarget: Hashable, Sendable, Codable {
    public enum Source: String, Hashable, Sendable, Codable { case explicit, inferred }
    public var value: Double
    public var source: Source

    public init(_ value: Double, source: Source = .explicit) {
        self.value = min(max(value, 0), 1)
        self.source = source
    }
}

/// What is playing now, so "this singer" and "more like this" have something to point at.
public struct NowPlayingContext: Hashable, Sendable {
    public var trackID: String
    public var artist: String
    public var album: String?

    public init(trackID: String, artist: String, album: String? = nil) {
        self.trackID = trackID
        self.artist = artist
        self.album = album
    }
}

/// What the player and recommender should do after a change.
public enum SessionEffect: Hashable, Sendable {
    /// Start something new (replaces Halo's part of the queue, never the listener's).
    case startPlaying(PlaySource)
    /// Re-rank Halo's upcoming songs against the new session state.
    case rerank
    case transport(Transport)
    /// Skip the current song (e.g. after excluding its artist).
    case skipCurrent
    case feedback(Rating, trackID: String)
    case answer(Question)
}

/// Halo Drive's session: what the listener has asked for during this drive. Lives on the
/// phone, is sent with recommendation requests, and never rewrites the long-term profile.
/// Only `Scope.profile` changes are passed on as feedback.
public struct SessionState: Hashable, Sendable, Codable {
    public var vibe: [VibeDimension: VibeTarget] = [:]
    public var language: LanguagePreference?
    public var recency: Recency = .any
    public var seedMode: SeedMode = .similar
    /// "Keep this vibe": inferred nudges and drift are ignored.
    public var locked = false
    /// Artist weights by normalized name; negative means "less of".
    public var artistWeights: [String: Double] = [:]
    public var excludedArtists: [String: Scope] = [:]
    public var excludedTracks: [String: Scope] = [:]
    public var keeps: [String] = []
    public var likes: [String] = []
    public var skips: [String] = []
    public var startedAt: Date
    /// Earlier states, newest last, for "undo". Not nested: snapshots carry no history.
    private(set) var history: [SessionState] = []

    public init(startedAt: Date = .now) {
        self.startedAt = startedAt
    }

    public static let maxHistory = 10

    /// A name normalized for matching ("S. Thaman" → "s thaman").
    public static func key(_ name: String) -> String {
        name.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: Applying an utterance

    /// Applies every operation in order and returns what the player should do.
    @discardableResult
    public mutating func apply(_ delta: IntentDelta, current: NowPlayingContext?) -> [SessionEffect] {
        guard !delta.isEmpty else { return [] }
        if delta.operations == [.undo] {
            return undo() ? [.rerank] : []
        }
        var snapshot = self
        snapshot.history = []
        var effects: [SessionEffect] = []
        var needsRerank = false

        for operation in delta.operations {
            switch operation {
            case let .play(source):
                locked = false
                seedMode = .similar
                effects.append(.startPlaying(source))
            case let .transport(action):
                effects.append(.transport(action))
            case let .setVibe(dimension, value):
                vibe[dimension] = VibeTarget(value)
                needsRerank = true
            case let .adjustVibe(dimension, step):
                let base = vibe[dimension]?.value ?? 0.5
                vibe[dimension] = VibeTarget(base + step)
                needsRerank = true
            case let .setLanguage(preference):
                language = preference
                needsRerank = true
            case let .favorLanguage(favored):
                if let current = language, current.primary != favored {
                    language = LanguagePreference(primary: favored, secondary: current.primary,
                                                  strategy: .mostly)
                } else {
                    language = .only(favored)
                }
                needsRerank = true
            case let .setRecency(value):
                recency = value
                needsRerank = true
            case .newer:
                recency = recency.newer
                needsRerank = true
            case .older:
                recency = recency.older
                needsRerank = true
            case .preserve:
                break  // the session already keeps everything that isn't changed
            case .lock:
                locked = true
            case .unlock:
                locked = false
            case let .seedMode(mode):
                seedMode = mode
                if mode == .elsewhere { locked = false }
                needsRerank = true
            case let .weightArtist(ref, weight):
                if let name = Self.artistKey(ref, current) {
                    artistWeights[name, default: 0] += weight
                    needsRerank = true
                }
            case let .excludeArtist(ref, scope):
                if let name = Self.artistKey(ref, current) {
                    excludedArtists[name] = scope
                    needsRerank = true
                    if ref == .currentArtist || Self.key(current?.artist ?? "") == name {
                        effects.append(.skipCurrent)
                    }
                }
            case .diversifyArtists:
                if let current {
                    artistWeights[Self.key(current.artist), default: 0] -= 0.5
                }
                needsRerank = true
            case let .rate(rating):
                guard let current else { break }
                switch rating {
                case .keep:
                    keeps.append(current.trackID)
                case .like:
                    likes.append(current.trackID)
                    effects.append(.feedback(.like, trackID: current.trackID))
                case .dislike:
                    artistWeights[Self.key(current.artist), default: 0] -= 0.3
                    effects.append(.feedback(.dislike, trackID: current.trackID))
                    effects.append(.skipCurrent)
                    needsRerank = true
                case .neverAgain:
                    excludedTracks[current.trackID] = .profile
                    effects.append(.feedback(.neverAgain, trackID: current.trackID))
                    effects.append(.skipCurrent)
                case .later:
                    effects.append(.feedback(.later, trackID: current.trackID))
                }
            case let .ask(question):
                effects.append(.answer(question))
            case .undo:
                break  // only meaningful on its own
            }
        }
        if needsRerank && !effects.contains(where: { if case .startPlaying = $0 { true } else { false } }) {
            effects.append(.rerank)
        }
        if snapshot != self.withoutHistory {
            history.append(snapshot)
            if history.count > Self.maxHistory { history.removeFirst() }
        }
        return effects
    }

    /// Restores the state before the last change. False when there is nothing to undo.
    public mutating func undo() -> Bool {
        guard var previous = history.popLast() else { return false }
        previous.history = history
        self = previous
        return true
    }

    // MARK: Signals from listening

    /// A skip is a weak, inferred signal: each one lowers that artist a little this session.
    public mutating func recordSkip(_ context: NowPlayingContext) {
        skips.append(context.trackID)
        guard !locked else { return }
        let name = Self.key(context.artist)
        artistWeights[name, default: 0] -= 0.1
    }

    // MARK: Helpers

    private var withoutHistory: SessionState {
        var copy = self
        copy.history = []
        return copy
    }

    private static func artistKey(_ ref: EntityRef, _ current: NowPlayingContext?) -> String? {
        switch ref {
        case .currentArtist, .currentTrack, .currentAlbum: current.map { key($0.artist) }
        case let .mention(name, _): key(name)
        }
    }
}
