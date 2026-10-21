import Foundation

// Wire models mirroring the Halo backend (snake_case JSON, decoded with
// `.convertFromSnakeCase`). Every track comes from the backend's catalog (Audius, Jamendo,
// or an iTunes preview) with a stream URL; the app never constructs track ids itself.

/// Where a track's audio comes from.
public enum TrackSource: String, Codable, Sendable, Hashable {
    case audius, jamendo, itunes, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TrackSource(rawValue: raw) ?? .unknown
    }

    public var label: String {
        switch self {
        case .audius: "Audius"
        case .jamendo: "Jamendo"
        case .itunes: "Apple Music preview"
        case .unknown: "Music"
        }
    }
}

public struct Attribution: Codable, Sendable, Hashable {
    public var provider: TrackSource
    public var label: String
    public var url: String?

    public init(provider: TrackSource, label: String, url: String? = nil) {
        self.provider = provider
        self.label = label
        self.url = url
    }
}

/// Creative Commons licence carried by Jamendo tracks.
public struct TrackLicense: Codable, Sendable, Hashable {
    public var name: String
    public var url: String?
}

public struct Track: Codable, Sendable, Hashable, Identifiable {
    /// "<source>:<id>", e.g. "audius:D7KyD".
    public var id: String
    public var source: TrackSource
    public var sourceId: String
    public var title: String
    public var artist: String
    public var artistId: String?
    public var album: String?
    public var artworkUrl: String?
    /// Sharper copy for the full-screen player, when the source has one.
    public var artworkUrlLarge: String?
    public var durationSeconds: Int?
    public var genre: String?
    public var mood: String?
    public var releaseDate: String?
    public var playCount: Int?
    public var streamUrl: String?
    /// A 30-second preview (iTunes), not the full song.
    public var isPreview: Bool
    public var license: TrackLicense?
    public var externalUrl: String?
    public var attribution: Attribution

    public init(
        id: String, source: TrackSource, sourceId: String, title: String, artist: String,
        artistId: String? = nil, album: String? = nil, artworkUrl: String? = nil,
        artworkUrlLarge: String? = nil, durationSeconds: Int? = nil, genre: String? = nil, mood: String? = nil,
        releaseDate: String? = nil, playCount: Int? = nil, streamUrl: String? = nil,
        isPreview: Bool = false, license: TrackLicense? = nil, externalUrl: String? = nil,
        attribution: Attribution
    ) {
        self.id = id
        self.source = source
        self.sourceId = sourceId
        self.title = title
        self.artist = artist
        self.artistId = artistId
        self.album = album
        self.artworkUrl = artworkUrl
        self.artworkUrlLarge = artworkUrlLarge
        self.durationSeconds = durationSeconds
        self.genre = genre
        self.mood = mood
        self.releaseDate = releaseDate
        self.playCount = playCount
        self.streamUrl = streamUrl
        self.isPreview = isPreview
        self.license = license
        self.externalUrl = externalUrl
        self.attribution = attribution
    }

    public var artworkURL: URL? { Self.webURL(artworkUrl) }
    public var largeArtworkURL: URL? { Self.webURL(artworkUrlLarge) }
    public var streamURL: URL? { Self.webURL(streamUrl) }
    /// The track's page at its source (for previews: the Apple Music page).
    public var externalURL: URL? { Self.webURL(externalUrl) }

    /// Only http(s) URLs are ever loaded or opened.
    static func webURL(_ raw: String?) -> URL? {
        guard let raw, let url = URL(string: raw), ["https", "http"].contains(url.scheme ?? "")
        else { return nil }
        return url
    }
}

public enum SearchKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case song, artist
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .song: "Songs"
        case .artist: "Artists"
        }
    }
}

public struct SearchResponse: Codable, Sendable {
    public var query: String
    public var kind: SearchKind
    public var items: [Track]
    public var nextPageToken: String?
    public var prevPageToken: String?
    public var totalResultsEstimate: Int?
    public var sources: [String]
    public var cached: Bool
}

public struct TrendingResponse: Codable, Sendable {
    public var items: [Track]
    public var nextPageToken: String?
    public var prevPageToken: String?
    public var sources: [String]
    public var cached: Bool
    public var source: String
}

public struct SuggestionsResponse: Codable, Sendable {
    public var query: String
    public var suggestions: [String]
}

public struct TokenResponse: Codable, Sendable {
    public var accessToken: String
    public var tokenType: String
    public var expiresAt: Date
    public var userId: UUID
}

// MARK: Playlists

public struct RemotePlaylistItem: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var position: Int
    public var note: String?
    public var trackId: String
    public var title: String
    public var artist: String
    public var album: String?
    public var artworkUrl: String?
    public var durationSeconds: Int?
    public var streamUrl: String?
    public var isPreview: Bool
    public var isAvailable: Bool
    public var addedAt: Date
}

public struct RemotePlaylist: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var mood: String?
    public var isAiGenerated: Bool
    public var itemCount: Int
    public var totalDurationSeconds: Int
    public var artworkUrl: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var items: [RemotePlaylistItem]?
}

public struct PlaylistPage: Codable, Sendable {
    public var items: [RemotePlaylist]
    public var total: Int
    public var limit: Int
    public var offset: Int
}

public struct PlaylistCreateRequest: Codable, Sendable {
    public var name: String
    public var description: String?
    public var mood: String?
    public var isAiGenerated: Bool
    public var recommendationSessionId: UUID?
    public var trackIds: [String]

    public init(
        name: String, description: String? = nil, mood: String? = nil,
        isAiGenerated: Bool = false, recommendationSessionId: UUID? = nil,
        trackIds: [String] = []
    ) {
        self.name = name
        self.description = description
        self.mood = mood
        self.isAiGenerated = isAiGenerated
        self.recommendationSessionId = recommendationSessionId
        self.trackIds = trackIds
    }
}

public struct PlaylistUpdateRequest: Codable, Sendable {
    public var name: String?
    public var description: String?
    public var mood: String?

    public init(name: String? = nil, description: String? = nil, mood: String? = nil) {
        self.name = name
        self.description = description
        self.mood = mood
    }
}

// MARK: Preferences & taste

public enum Mood: String, Codable, Sendable, CaseIterable, Identifiable {
    case calm, happy, focused, energetic, romantic, sleep, workout, travel
    public var id: String { rawValue }
    public var label: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .calm: "leaf"
        case .happy: "sun.max"
        case .focused: "brain.head.profile"
        case .energetic: "bolt"
        case .romantic: "heart"
        case .sleep: "moon.zzz"
        case .workout: "figure.run"
        case .travel: "car"
        }
    }
    /// Seed text used for discovery and playlist generation.
    public var discoveryPrompt: String {
        switch self {
        case .calm: "calm relaxing songs"
        case .happy: "happy feel good songs"
        case .focused: "focus music for deep work with minimal vocals"
        case .energetic: "energetic upbeat dance songs"
        case .romantic: "romantic love songs"
        case .sleep: "soft sleep music instrumental"
        case .workout: "high energy workout songs"
        case .travel: "road trip songs for a long drive"
        }
    }
}

public enum DiscoveryPreference: String, Codable, Sendable, CaseIterable, Identifiable {
    case familiar, balanced, discovery
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .familiar: "Familiar"
        case .balanced: "Balanced"
        case .discovery: "Discovery"
        }
    }
}

public struct ArtistPreference: Codable, Sendable, Hashable, Identifiable {
    public var name: String
    public var id: String { name.lowercased() }
    public init(name: String) {
        self.name = name
    }
}

public struct Preferences: Codable, Sendable, Equatable {
    public var personalizationEnabled: Bool = false
    public var storeAiConversations: Bool = false
    public var recordSearchHistory: Bool = true
    public var languages: [String] = []
    public var genres: [String] = []
    public var moods: [Mood] = []
    public var discoveryPreference: DiscoveryPreference = .balanced
    public var favoriteArtists: [ArtistPreference] = []
    public var excludedArtists: [ArtistPreference] = []
    public var onboardingCompleted: Bool = false
    public var personalizationConsentAt: Date?
    public var updatedAt: Date?

    public init() {}
}

public struct TasteSignal: Codable, Sendable, Hashable, Identifiable {
    public var label: String
    public var weight: Double
    public var evidence: String
    public var id: String { label }
}

public struct TasteProfile: Codable, Sendable {
    public var personalizationEnabled: Bool
    public var basis: String
    public var topArtists: [TasteSignal]
    public var topTerms: [TasteSignal]
    public var declaredLanguages: [String]
    public var declaredGenres: [String]
    public var excludedArtists: [String]
    public var activityCounts: [String: Int]
}

public struct SearchHistoryEntry: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var query: String
    public var kind: String
    public var resultCount: Int
    public var createdAt: Date
}

// MARK: AI

public struct AIPlaylistRequest: Codable, Sendable, Equatable {
    public var description: String
    public var mood: Mood?
    public var genres: [String]
    public var language: String?
    public var energy: Int?
    public var durationMinutes: Int
    public var discovery: DiscoveryPreference
    public var excludeTrackIds: [String]

    public init(
        description: String, mood: Mood? = nil, genres: [String] = [], language: String? = nil,
        energy: Int? = nil, durationMinutes: Int = 60, discovery: DiscoveryPreference = .balanced,
        excludeTrackIds: [String] = []
    ) {
        self.description = description
        self.mood = mood
        self.genres = genres
        self.language = language
        self.energy = energy
        self.durationMinutes = durationMinutes
        self.discovery = discovery
        self.excludeTrackIds = excludeTrackIds
    }
}

public struct ChatTurn: Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public var role: Role
    public var content: String
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct AIChatRequest: Codable, Sendable {
    public var message: String
    public var conversationId: UUID?
    public var history: [ChatTurn]
    public init(message: String, conversationId: UUID? = nil, history: [ChatTurn] = []) {
        self.message = message
        self.conversationId = conversationId
        self.history = history
    }
}

public struct RecommendedTrack: Codable, Sendable, Hashable, Identifiable {
    public var track: Track
    public var score: Double
    public var reasons: [String]
    public var matchedQuery: String
    /// Candidate source: "search", "similar_artist", "co_listen" or "listenbrainz".
    public var source: String?
    /// True when this was an exploration pick ("something new for you").
    public var explore: Bool?
    public var id: String { track.id }
}

public struct PlaylistDraft: Codable, Sendable, Hashable {
    public var sessionId: UUID?
    public var title: String
    public var explanation: String
    public var planner: String
    public var queries: [String]
    public var tracks: [RecommendedTrack]
    public var totalDurationSeconds: Int
    public var targetDurationSeconds: Int
    public var sources: [String]
    public var warnings: [String]
}

public struct AIChatResponse: Codable, Sendable {
    public var conversationId: UUID?
    public var reply: String
    public var draft: PlaylistDraft?
    public var stored: Bool
}

public enum FeedbackRating: String, Codable, Sendable {
    case like, dislike, skip, save
}

public struct FeedbackRequest: Codable, Sendable {
    public var trackId: String
    public var rating: FeedbackRating
    public var sessionId: UUID?
    public var artist: String?
    public init(trackId: String, rating: FeedbackRating, sessionId: UUID? = nil,
                artist: String? = nil) {
        self.trackId = trackId
        self.rating = rating
        self.sessionId = sessionId
        self.artist = artist
    }
}

public struct FeedbackResponse: Codable, Sendable {
    public var id: UUID
    public var trackId: String
    public var rating: FeedbackRating
    public var recorded: Bool
}

public struct HealthResponse: Codable, Sendable {
    public var status: String
    public var musicSources: [String]
    public var aiPlanner: String
    public var checks: [String: String]?

    /// False when the server has no music source enabled.
    public var isCatalogConfigured: Bool { checks?["catalog"] != "not_configured" }
}

public struct UpNextResponse: Codable, Sendable {
    public var seedTrackId: String
    public var tracks: [RecommendedTrack]
}

/// A live internet radio station (Radio Browser directory). Streams belong to the station.
public struct RadioStation: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var streamUrl: String
    public var homepage: String?
    public var favicon: String?
    public var tags: [String]
    public var countryCode: String?
    public var language: String?
    public var codec: String?
    public var bitrate: Int?
    public var popularity: Int

    public var streamURL: URL? {
        guard let url = URL(string: streamUrl), ["https", "http"].contains(url.scheme ?? "") else {
            return nil
        }
        return url
    }
}

// MARK: Display abstraction

/// Anything that can be shown as a track row and played.
public protocol TrackDisplayable {
    var trackID: String { get }
    var title: String { get }
    var artist: String { get }
    var artworkURL: URL? { get }
    var durationSeconds: Int? { get }
    var isPreview: Bool { get }
}

extension Track: TrackDisplayable {
    public var trackID: String { id }
}
