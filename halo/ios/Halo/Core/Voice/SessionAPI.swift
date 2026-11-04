import Foundation

// Wire models for POST /api/v1/session/candidates (snake_case on the wire). Built from the
// on-device `SessionState`; the server ranks songs for it and keeps nothing.

public struct SessionCandidatesRequest: Codable, Sendable, Equatable {
    public struct Vibe: Codable, Sendable, Equatable {
        public var energy: Double?
        public var valence: Double?
        public var tempo: Double?
        public var discovery: Double?
    }

    public struct Language: Codable, Sendable, Equatable {
        public var primary: String
        public var secondary: String?
        public var strategy: String
    }

    public struct RecencyWire: Codable, Sendable, Equatable {
        public var mode: String
        public var value: Int?
    }

    public struct Entity: Codable, Sendable, Equatable {
        public var name: String
        public var kind: String
    }

    public var vibe: Vibe
    public var language: Language?
    public var recency: RecencyWire
    public var seedTrackId: String?
    public var seedMode: String
    public var entity: Entity?
    /// Keys are normalized lowercase artist names.
    public var artistWeights: [String: Double]
    public var excludedArtists: [String]
    public var excludedTrackIds: [String]
    public var excludedMoods: [String]
    /// Artists of the last songs heard (normalized), ranked lower for variety.
    public var recentArtists: [String]
    public var limit: Int

    public init(state: SessionState, seedTrackID: String? = nil, entity: EntityRef? = nil,
                alsoExclude trackIDs: [String] = [], limit: Int = 30, now: Date = .now) {
        vibe = Vibe(energy: state.vibe[.energy]?.value, valence: state.vibe[.valence]?.value,
                    tempo: state.vibe[.tempo]?.value, discovery: state.vibe[.discovery]?.value)
        language = state.language.map {
            Language(primary: $0.primary.rawValue, secondary: $0.secondary?.rawValue,
                     strategy: $0.strategy.rawValue)
        }
        switch state.recency {
        case .any: recency = RecencyWire(mode: "any", value: nil)
        case let .withinDays(days): recency = RecencyWire(mode: "within_days", value: days)
        case let .decade(year): recency = RecencyWire(mode: "decade", value: year)
        case .classics: recency = RecencyWire(mode: "classics", value: nil)
        }
        seedTrackId = seedTrackID.flatMap { TrackID.isValid($0) ? $0 : nil }
        seedMode = state.seedMode.rawValue
        if case let .mention(name, kind) = entity {
            self.entity = Entity(name: String(name.prefix(80)), kind: kind.rawValue)
        } else {
            self.entity = nil
        }
        artistWeights = Dictionary(
            state.effectiveArtistWeights.filter { !$0.key.isEmpty }.prefix(30).map { ($0.key, $0.value) },
            uniquingKeysWith: { first, _ in first })
        excludedArtists = Array(state.activeExcludedArtists(at: now).prefix(50))
        recentArtists = Array(state.recentArtists.suffix(10))
        let tracks = Array(state.excludedTracks.keys) + trackIDs
        excludedTrackIds = Array(Array(Set(tracks)).filter(TrackID.isValid).prefix(200))
        excludedMoods = state.avoidedMoods.map(\.rawValue).sorted()
        self.limit = min(max(limit, 1), 60)
    }
}

public struct SessionCandidate: Codable, Sendable, Hashable, Identifiable {
    public var track: Track
    public var score: Double
    public var fit: [String: Double]
    public var source: String
    public var id: String { track.id }
}

public struct SessionCandidatesResponse: Codable, Sendable {
    public var candidates: [SessionCandidate]
    public var rankingVersion: String
    public var sources: [String]
    public var warnings: [String]
}

/// POST /api/v1/intent/fallback: one command's text, never audio or history.
public struct IntentFallbackRequest: Codable, Sendable, Equatable {
    public var transcript: String
    public var speech: String
    public var language: String?
    public var consent: Bool

    public init(transcript: String, speech: SpeechStyle, language: MusicLanguage?, consent: Bool) {
        self.transcript = String(transcript.prefix(200))
        self.speech = speech.rawValue
        self.language = language.flatMap { MusicLanguage.supported.contains($0) ? $0.rawValue : nil }
        self.consent = consent
    }
}

public struct IntentFallbackResponse: Codable, Sendable, Equatable {
    public var outcome: String
    public var operations: [String]
    public var provider: String
    public var latencyMs: Int
    public var note: String?

    public init(outcome: String, operations: [String], provider: String, latencyMs: Int, note: String? = nil) {
        self.outcome = outcome
        self.operations = operations
        self.provider = provider
        self.latencyMs = latencyMs
        self.note = note
    }

    /// The operations, only if every one is inside Halo's vocabulary; otherwise none at all.
    public var validatedOperations: [SessionOperation]? {
        guard outcome == "execute", !operations.isEmpty, operations.count <= 6 else { return nil }
        let parsed = operations.compactMap(SessionOperation.init(wire:))
        return parsed.count == operations.count ? parsed : nil
    }
}
