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
    public var limit: Int

    public init(state: SessionState, seedTrackID: String? = nil, entity: EntityRef? = nil,
                alsoExclude trackIDs: [String] = [], limit: Int = 30) {
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
            state.artistWeights.filter { !$0.key.isEmpty }.prefix(30).map { ($0.key, $0.value) },
            uniquingKeysWith: { first, _ in first })
        excludedArtists = Array(state.excludedArtists.keys.prefix(50))
        let tracks = Array(state.excludedTracks.keys) + trackIDs
        excludedTrackIds = Array(Array(Set(tracks)).filter(TrackID.isValid).prefix(200))
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
