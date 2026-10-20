import Foundation

// Server-driven Home feed (GET /api/v1/home). The server decides which sections appear and
// in what order; the app decides how each layout looks. Unknown kinds and layouts decode to
// `.unknown` so an older app keeps working when the server adds new ones.

public enum HomeItemKind: String, Codable, Sendable, Hashable {
    case track, recording, release, artist, query, mood, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HomeItemKind(rawValue: raw) ?? .unknown
    }
}

public enum HomeLayout: String, Codable, Sendable, Hashable {
    case rail
    case featureRail = "feature_rail"
    case artistRail = "artist_rail"
    case rows, tiles, local, unknown

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HomeLayout(rawValue: raw) ?? .unknown
    }
}

public struct HomeItem: Codable, Sendable, Hashable, Identifiable {
    public var kind: HomeItemKind
    public var id: String
    public var title: String
    public var subtitle: String?
    public var artworkUrl: String?
    public var query: String?
    public var badge: String?
    public var track: Track?

    public init(kind: HomeItemKind, id: String, title: String, subtitle: String? = nil,
                artworkUrl: String? = nil, query: String? = nil, badge: String? = nil,
                track: Track? = nil) {
        self.kind = kind
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.artworkUrl = artworkUrl
        self.query = query
        self.badge = badge
        self.track = track
    }

    public var artworkURL: URL? { artworkUrl.flatMap(URL.init(string:)) }
}

public struct HomeSection: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var type: String
    public var title: String
    public var eyebrow: String?
    public var layout: HomeLayout
    public var items: [HomeItem]
    public var source: String?
    public var seeAllQuery: String?
    public var score: Double

    public init(id: String, type: String, title: String, eyebrow: String? = nil,
                layout: HomeLayout, items: [HomeItem] = [], source: String? = nil,
                seeAllQuery: String? = nil, score: Double) {
        self.id = id
        self.type = type
        self.title = title
        self.eyebrow = eyebrow
        self.layout = layout
        self.items = items
        self.source = source
        self.seeAllQuery = seeAllQuery
        self.score = score
    }
}

public struct HomeFeed: Codable, Sendable, Hashable {
    public var sections: [HomeSection]
    public var personalized: Bool
    public var generatedAt: Date
}
