import Foundation

// Open music data from MetaBrainz. MusicBrainz supplies canonical facts (recordings,
// releases, labels, ISRCs; CC0); ListenBrainz supplies listening signals and fresh releases.

public struct ArtistCredit: Codable, Sendable, Hashable {
    public var name: String
    public var mbid: String?
    public var joinPhrase: String
}

public struct RecordLabel: Codable, Sendable, Hashable {
    public var name: String
    public var mbid: String?
    public var catalogNumber: String?
}

public struct ReleaseInfo: Codable, Sendable, Hashable, Identifiable {
    public var mbid: String
    public var title: String
    public var date: String?
    public var country: String?
    public var status: String?
    public var releaseGroupMbid: String?
    public var releaseGroupType: String?
    public var labels: [RecordLabel]
    public var coverArtUrl: String?

    public var id: String { mbid }
    public var coverArtURL: URL? { coverArtUrl.flatMap(URL.init(string:)) }
}

public struct CanonicalRecording: Codable, Sendable, Hashable {
    public var recordingMbid: String
    public var title: String
    public var artistCredit: [ArtistCredit]
    public var lengthMs: Int?
    public var firstReleaseDate: String?
    public var isrcs: [String]
    public var genres: [String]
    public var releases: [ReleaseInfo]
    public var matchScore: Int
    public var musicbrainzUrl: String

    public var artistName: String { artistCredit.map { $0.name + $0.joinPhrase }.joined() }
    public var musicBrainzURL: URL? { URL(string: musicbrainzUrl) }
    /// The earliest official release, which the backend puts first.
    public var album: ReleaseInfo? { releases.first }
}

public struct ArtistInfo: Codable, Sendable, Hashable {
    public var mbid: String
    public var name: String
    public var sortName: String?
    public var type: String?
    public var country: String?
    public var area: String?
    public var disambiguation: String?
    public var begin: String?
    public var end: String?
    public var genres: [String]
    public var matchScore: Int
    public var musicbrainzUrl: String

    public var musicBrainzURL: URL? { URL(string: musicbrainzUrl) }
}

public struct TrackMetadataResponse: Codable, Sendable, Hashable {
    public var videoId: String
    public var parsedArtist: String
    public var parsedTitle: String
    public var matched: Bool
    public var recording: CanonicalRecording?
    public var artist: ArtistInfo?
    public var source: String
}

public struct PopularRecording: Codable, Sendable, Hashable, Identifiable {
    public var recordingMbid: String?
    public var title: String
    public var artistName: String
    public var releaseName: String?
    public var listenCount: Int
    public var listenerCount: Int?
    public var lengthMs: Int?
    public var similarTo: String?
    public var source: String

    public var id: String { recordingMbid ?? "\(artistName)|\(title)" }
    /// What to search on YouTube to find this recording.
    public var searchQuery: String { "\(artistName) \(title)" }
}

public struct ArtistProfileResponse: Codable, Sendable, Hashable {
    public var artist: ArtistInfo?
    public var popularRecordings: [PopularRecording]
    public var sources: [String]
}

public struct FreshRelease: Codable, Sendable, Hashable, Identifiable {
    public var releaseMbid: String
    public var releaseName: String
    public var artistName: String
    public var artistMbids: [String]
    public var releaseDate: String
    public var releaseGroupMbid: String?
    public var releaseType: String?
    public var tags: [String]
    public var listenCount: Int
    public var coverArtUrl: String?
    public var source: String

    public var id: String { releaseMbid }
    public var coverArtURL: URL? { coverArtUrl.flatMap(URL.init(string:)) }
    public var searchQuery: String { "\(artistName) \(releaseName)" }
}

public enum ListeningRange: String, Codable, Sendable, CaseIterable {
    case week, month, quarter, year
    case allTime = "all_time"
}
