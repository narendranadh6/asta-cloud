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

    private enum CodingKeys: String, CodingKey {
        case id, type, title, eyebrow, layout, items, source, seeAllQuery, score
    }

    /// Items the app can't read (e.g. a track from a newer source shape) are skipped.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        eyebrow = try container.decodeIfPresent(String.self, forKey: .eyebrow)
        layout = try container.decode(HomeLayout.self, forKey: .layout)
        items = try container.decodeIfPresent([Lossy<HomeItem>].self, forKey: .items)?
            .compactMap(\.value) ?? []
        source = try container.decodeIfPresent(String.self, forKey: .source)
        seeAllQuery = try container.decodeIfPresent(String.self, forKey: .seeAllQuery)
        score = try container.decode(Double.self, forKey: .score)
    }

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

    public init(sections: [HomeSection], personalized: Bool, generatedAt: Date) {
        self.sections = sections
        self.personalized = personalized
        self.generatedAt = generatedAt
    }

    private enum CodingKeys: String, CodingKey { case sections, personalized, generatedAt }

    /// A section the app can't read is dropped instead of failing the whole feed.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decode([Lossy<HomeSection>].self, forKey: .sections)
            .compactMap(\.value)
        personalized = try container.decode(Bool.self, forKey: .personalized)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
    }
}

/// Decodes a value, or nil if this element is malformed, so one bad entry can't sink a list.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}
