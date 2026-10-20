import Foundation

// Wire models mirroring the Halo backend (snake_case JSON, decoded with
// `.convertFromSnakeCase`). All playable references originate from backend-verified
// YouTube Data API metadata; the app never constructs video ids itself.

public enum MetadataProvider: String, Codable, Sendable, Hashable {
    case youtube
}

public struct Thumbnail: Codable, Sendable, Hashable {
    public var url: String
    public var width: Int?
    public var height: Int?
}

public struct Attribution: Codable, Sendable, Hashable {
    public var provider: MetadataProvider
    public var label: String
    public var url: String?
}

public struct Track: Codable, Sendable, Hashable, Identifiable {
    public var videoId: String
    public var title: String
    public var channelTitle: String
    public var channelId: String?
    public var description: String?
    public var thumbnails: [String: Thumbnail]
    public var durationSeconds: Int?
    public var publishedAt: Date?
    public var viewCount: Int?
    public var isLive: Bool
    public var watchUrl: String
    public var attribution: Attribution

    public var id: String { videoId }

    public var artworkURL: URL? {
        for key in ["maxres", "high", "medium", "standard", "default"] {
            if let raw = thumbnails[key]?.url, let url = URL(string: raw), url.scheme == "https" {
                return url
            }
        }
        return nil
    }

    public init(
        videoId: String, title: String, channelTitle: String, channelId: String? = nil,
        description: String? = nil, thumbnails: [String: Thumbnail] = [:],
        durationSeconds: Int? = nil, publishedAt: Date? = nil, viewCount: Int? = nil,
        isLive: Bool = false, watchUrl: String, attribution: Attribution
    ) {
        self.videoId = videoId
        self.title = title
        self.channelTitle = channelTitle
        self.channelId = channelId
        self.description = description
        self.thumbnails = thumbnails
        self.durationSeconds = durationSeconds
        self.publishedAt = publishedAt
        self.viewCount = viewCount
        self.isLive = isLive
        self.watchUrl = watchUrl
        self.attribution = attribution
    }
}

public enum SearchKind: String, Codable, Sendable, CaseIterable, Identifiable {
    case song, artist, remix, live
    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .song: "Songs"
        case .artist: "Artists"
        case .remix: "Remixes"
        case .live: "Live"
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
    public var provider: MetadataProvider
    public var cached: Bool
}

public struct TrendingResponse: Codable, Sendable {
    public var items: [Track]
    public var nextPageToken: String?
    public var prevPageToken: String?
    public var provider: MetadataProvider
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
    public var videoId: String
    public var title: String
    public var channelTitle: String
    public var thumbnailUrl: String?
    public var durationSeconds: Int?
    public var isAvailable: Bool
    public var watchUrl: String
    public var addedAt: Date
}

public struct RemotePlaylist: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var description: String?
    public var mood: String?
    public var isAiGenerated: Bool
    public var youtubePlaylistId: String?
    public var youtubePlaylistUrl: String?
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
    public var youtubePlaylistId: String?
    public var isAiGenerated: Bool
    public var recommendationSessionId: UUID?
    public var videoIds: [String]

    public init(
        name: String, description: String? = nil, mood: String? = nil,
        youtubePlaylistId: String? = nil, isAiGenerated: Bool = false,
        recommendationSessionId: UUID? = nil, videoIds: [String] = []
    ) {
        self.name = name
        self.description = description
        self.mood = mood
        self.youtubePlaylistId = youtubePlaylistId
        self.isAiGenerated = isAiGenerated
        self.recommendationSessionId = recommendationSessionId
        self.videoIds = videoIds
    }
}

public struct PlaylistUpdateRequest: Codable, Sendable {
    public var name: String?
    public var description: String?
    public var mood: String?
    public var youtubePlaylistId: String?

    public init(name: String? = nil, description: String? = nil, mood: String? = nil,
                youtubePlaylistId: String? = nil) {
        self.name = name
        self.description = description
        self.mood = mood
        self.youtubePlaylistId = youtubePlaylistId
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
    public var youtubeChannelId: String?
    public var id: String { name.lowercased() }
    public init(name: String, youtubeChannelId: String? = nil) {
        self.name = name
        self.youtubeChannelId = youtubeChannelId
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
    public var excludeVideoIds: [String]

    public init(
        description: String, mood: Mood? = nil, genres: [String] = [], language: String? = nil,
        energy: Int? = nil, durationMinutes: Int = 60, discovery: DiscoveryPreference = .balanced,
        excludeVideoIds: [String] = []
    ) {
        self.description = description
        self.mood = mood
        self.genres = genres
        self.language = language
        self.energy = energy
        self.durationMinutes = durationMinutes
        self.discovery = discovery
        self.excludeVideoIds = excludeVideoIds
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
    /// Candidate source: "search", "similar_artist" or "co_listen".
    public var source: String?
    /// True when this was an exploration pick ("something new for you").
    public var explore: Bool?
    public var id: String { track.videoId }
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
    public var provider: MetadataProvider
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
    public var videoId: String
    public var rating: FeedbackRating
    public var sessionId: UUID?
    public var channelTitle: String?
    public init(videoId: String, rating: FeedbackRating, sessionId: UUID? = nil,
                channelTitle: String? = nil) {
        self.videoId = videoId
        self.rating = rating
        self.sessionId = sessionId
        self.channelTitle = channelTitle
    }
}

public struct FeedbackResponse: Codable, Sendable {
    public var id: UUID
    public var videoId: String
    public var rating: FeedbackRating
    public var recorded: Bool
}

public struct HealthResponse: Codable, Sendable {
    public var status: String
    public var metadataProvider: MetadataProvider
    public var aiPlanner: String
    public var checks: [String: String]?

    /// False when the server has no YouTube API key yet.
    public var isSearchConfigured: Bool { checks?["youtube"] != "not_configured" }
}

public struct UpNextResponse: Codable, Sendable {
    public var seedVideoId: String
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

/// Anything that can be shown as a track row and handed off to a browser.
public protocol TrackDisplayable {
    var videoId: String { get }
    var title: String { get }
    var channelTitle: String { get }
    var artworkURL: URL? { get }
    var durationSeconds: Int? { get }
}

extension Track: TrackDisplayable {}
