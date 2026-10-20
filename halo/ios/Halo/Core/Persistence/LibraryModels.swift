#if canImport(SwiftData)
import Foundation
import SwiftData

// Local-first library. SwiftData is the source of truth on device; playlists are
// optionally mirrored to the backend by `PlaylistSyncService`. Only references and
// minimal metadata (including the stream URL) are stored — never audio.

/// A track the user saved or opened. `isSaved == false` entries are "recently discovered"
/// and are purged after the metadata retention window.
@Model
final class TrackEntity {
    @Attribute(.unique) var trackID: String
    var title: String
    var artist: String
    var album: String?
    var artworkURLString: String?
    var durationSeconds: Int?
    var sourceRaw: String
    var streamURLString: String?
    var isPreview: Bool
    var externalURLString: String?
    var isSaved: Bool
    var savedAt: Date?
    var lastViewedAt: Date
    var metadataFetchedAt: Date
    var isAvailable: Bool

    init(track: Track, saved: Bool = false, now: Date = .now) {
        trackID = track.id
        title = track.title
        artist = track.artist
        album = track.album
        artworkURLString = track.artworkURL?.absoluteString
        durationSeconds = track.durationSeconds
        sourceRaw = track.source.rawValue
        streamURLString = track.streamURL?.absoluteString
        isPreview = track.isPreview
        externalURLString = track.externalURL?.absoluteString
        isSaved = saved
        savedAt = saved ? now : nil
        lastViewedAt = now
        metadataFetchedAt = now
        isAvailable = true
    }

    func update(from track: Track, now: Date = .now) {
        title = track.title
        artist = track.artist
        album = track.album
        artworkURLString = track.artworkURL?.absoluteString
        durationSeconds = track.durationSeconds
        sourceRaw = track.source.rawValue
        streamURLString = track.streamURL?.absoluteString
        isPreview = track.isPreview
        externalURLString = track.externalURL?.absoluteString
        metadataFetchedAt = now
        isAvailable = true
    }
}

extension TrackEntity: TrackDisplayable {
    var artworkURL: URL? { Track.webURL(artworkURLString) }
}

@Model
final class PlaylistEntity {
    @Attribute(.unique) var id: UUID
    var name: String
    var details: String?
    var mood: String?
    var isAIGenerated: Bool
    var remoteID: UUID?
    var recommendationSessionID: UUID?
    var needsSync: Bool
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \PlaylistItemEntity.playlist)
    var items: [PlaylistItemEntity] = []

    init(name: String, details: String? = nil, mood: String? = nil, isAIGenerated: Bool = false,
         recommendationSessionID: UUID? = nil, now: Date = .now) {
        id = UUID()
        self.name = name
        self.details = details
        self.mood = mood
        self.isAIGenerated = isAIGenerated
        self.recommendationSessionID = recommendationSessionID
        needsSync = true
        createdAt = now
        updatedAt = now
    }

    var orderedItems: [PlaylistItemEntity] {
        items.sorted { $0.position < $1.position }
    }

    var totalDurationSeconds: Int {
        items.compactMap(\.durationSeconds).reduce(0, +)
    }

    var artworkURL: URL? {
        orderedItems.lazy.compactMap(\.artworkURL).first
    }
}

@Model
final class PlaylistItemEntity {
    @Attribute(.unique) var id: UUID
    var position: Int
    var trackID: String
    var title: String
    var artist: String
    var album: String?
    var artworkURLString: String?
    var durationSeconds: Int?
    var sourceRaw: String
    var streamURLString: String?
    var isPreview: Bool
    var addedAt: Date
    var playlist: PlaylistEntity?

    init(track: Track, position: Int, now: Date = .now) {
        id = UUID()
        self.position = position
        trackID = track.id
        title = track.title
        artist = track.artist
        album = track.album
        artworkURLString = track.artworkURL?.absoluteString
        durationSeconds = track.durationSeconds
        sourceRaw = track.source.rawValue
        streamURLString = track.streamURL?.absoluteString
        isPreview = track.isPreview
        addedAt = now
    }
}

extension PlaylistItemEntity: TrackDisplayable {
    var artworkURL: URL? { Track.webURL(artworkURLString) }
}

@Model
final class RecentSearchEntity {
    var query: String
    var kindRaw: String
    var searchedAt: Date

    init(query: String, kind: SearchKind, now: Date = .now) {
        self.query = query
        kindRaw = kind.rawValue
        searchedAt = now
    }
}

/// Artists the user explicitly marked as favorite or excluded.
@Model
final class ArtistEntity {
    @Attribute(.unique) var normalizedName: String
    var name: String
    var isExcluded: Bool
    var addedAt: Date

    init(name: String, excluded: Bool = false, now: Date = .now) {
        self.name = name
        normalizedName = ArtistEntity.normalize(name)
        isExcluded = excluded
        addedAt = now
    }

    static func normalize(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: " ")
    }
}

enum LibrarySchema {
    static var models: [any PersistentModel.Type] {
        [TrackEntity.self, PlaylistEntity.self, PlaylistItemEntity.self, RecentSearchEntity.self,
         ArtistEntity.self]
    }

    /// v2: tracks come from the free catalog (Audius, Jamendo, previews). The v1 store held
    /// YouTube references that can't be played in the app, so v2 starts a fresh store file.
    static let storeName = "HaloLibrary-v2"

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = inMemory
            ? ModelConfiguration(isStoredInMemoryOnly: true)
            : ModelConfiguration(storeName, schema: Schema(models))
        return try ModelContainer(for: Schema(models), configurations: [configuration])
    }
}
#endif
