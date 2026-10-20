import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Everything the app needs from the Halo backend.
public protocol MusicAPI: Sendable {
    func health() async throws -> HealthResponse
    /// Home feed: ordered sections chosen by the server.
    func home() async throws -> HomeFeed
    func search(query: String, kind: SearchKind, pageToken: String?, limit: Int) async throws
        -> SearchResponse
    func suggestions(prefix: String) async throws -> [String]
    func trending(pageToken: String?, limit: Int) async throws -> TrendingResponse
    func video(id: String) async throws -> Track

    func playlists(limit: Int, offset: Int) async throws -> PlaylistPage
    func playlist(id: UUID) async throws -> RemotePlaylist
    func createPlaylist(_ request: PlaylistCreateRequest) async throws -> RemotePlaylist
    func updatePlaylist(id: UUID, _ request: PlaylistUpdateRequest) async throws -> RemotePlaylist
    func deletePlaylist(id: UUID) async throws
    func addPlaylistItem(playlistID: UUID, videoID: String, position: Int?) async throws
        -> RemotePlaylist
    func removePlaylistItem(playlistID: UUID, itemID: UUID) async throws -> RemotePlaylist
    func reorderPlaylist(id: UUID, itemIDs: [UUID]) async throws -> RemotePlaylist

    func aiPlaylist(_ request: AIPlaylistRequest) async throws -> PlaylistDraft
    func aiChat(_ request: AIChatRequest) async throws -> AIChatResponse
    func sendFeedback(_ request: FeedbackRequest) async throws -> FeedbackResponse
    /// Songs to choose next after `videoID` (co-listening, same and similar artists).
    func upNext(videoID: String, limit: Int) async throws -> UpNextResponse
    /// Live internet radio stations (Radio Browser directory).
    func radioStations(tag: String?, language: String?, query: String?, limit: Int) async throws
        -> [RadioStation]

    /// Canonical facts about a song from MusicBrainz; `matched` is false when unsure.
    func trackMetadata(videoID: String) async throws -> TrackMetadataResponse
    /// MusicBrainz artist facts plus ListenBrainz popular recordings when available.
    func artistProfile(name: String) async throws -> ArtistProfileResponse
    /// Recent (or upcoming) releases from ListenBrainz.
    func freshReleases(days: Int, upcoming: Bool, limit: Int) async throws -> [FreshRelease]
    /// Most-listened recordings across ListenBrainz.
    func mostListened(range: ListeningRange, limit: Int) async throws -> [PopularRecording]

    func preferences() async throws -> Preferences
    func updatePreferences(_ preferences: Preferences) async throws -> Preferences
    func taste() async throws -> TasteProfile
    func resetTaste() async throws
    func searchHistory() async throws -> [SearchHistoryEntry]
    func clearSearchHistory() async throws

    func exportData() async throws -> Data
    func deleteAccount() async throws
}

/// Production client. Registers an anonymous device account on first use, stores the
/// token in the Keychain, re-registers once if the token is rejected, and retries
/// idempotent requests on transient failures with exponential backoff.
public actor APIClient: MusicAPI {
    public struct Configuration: Sendable {
        public var baseURL: URL
        public var maxRetries: Int
        public var retryBaseDelay: TimeInterval

        public init(baseURL: URL, maxRetries: Int = 2, retryBaseDelay: TimeInterval = 0.5) {
            self.baseURL = baseURL
            self.maxRetries = maxRetries
            self.retryBaseDelay = retryBaseDelay
        }
    }

    private let configuration: Configuration
    private let transport: HTTPTransport
    private let tokens: TokenStore
    private var registration: Task<String, Error>?

    public init(configuration: Configuration, transport: HTTPTransport, tokens: TokenStore) {
        self.configuration = configuration
        self.transport = transport
        self.tokens = tokens
    }

    // MARK: Core request pipeline

    enum Method: String {
        case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
        var isIdempotent: Bool { self != .post }
    }

    struct Empty: Codable {}

    private func makeURL(_ path: String, query: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(
            url: configuration.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false)
        else { throw APIError.notConfigured }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw APIError.notConfigured }
        return url
    }

    private func token() async throws -> String {
        if let existing = tokens.readToken() { return existing }
        if let registration { return try await registration.value }
        let task = Task { [configuration, transport, tokens] () throws -> String in
            var request = URLRequest(
                url: configuration.baseURL.appendingPathComponent("api/v1/auth/register"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
            let (data, response) = try await Self.perform(request, transport: transport)
            guard (200..<300).contains(response.statusCode) else {
                throw APIError.from(
                    status: response.statusCode, data: data, headers: response.allHeaderFields)
            }
            let token = try JSONDecoder.halo.decode(TokenResponse.self, from: data)
            try tokens.saveToken(token.accessToken)
            return token.accessToken
        }
        registration = task
        defer { registration = nil }
        return try await task.value
    }

    private static func perform(_ request: URLRequest, transport: HTTPTransport) async throws
        -> (Data, HTTPURLResponse)
    {
        do {
            return try await transport.send(request)
        } catch let error as URLError {
            throw APIError.from(urlError: error)
        } catch let error as APIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw APIError.transport(message: String(describing: error))
        }
    }

    func sendRaw(
        _ method: Method, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
        allowReauth: Bool = true
    ) async throws -> Data {
        let url = try makeURL(path, query: query)
        var attempt = 0
        while true {
            var request = URLRequest(url: url)
            request.httpMethod = method.rawValue
            request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
            if let body {
                request.httpBody = body
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            do {
                let (data, response) = try await Self.perform(request, transport: transport)
                if (200..<300).contains(response.statusCode) { return data }
                throw APIError.from(
                    status: response.statusCode, data: data, headers: response.allHeaderFields)
            } catch let error as APIError {
                if error.requiresReauthentication && allowReauth {
                    tokens.deleteToken()
                    return try await sendRaw(
                        method, path, query: query, body: body, allowReauth: false)
                }
                let retryable = error.isTransient && method.isIdempotent
                guard retryable, attempt < configuration.maxRetries else { throw error }
                var delay = configuration.retryBaseDelay * pow(2, Double(attempt))
                if case let .server(_, _, _, retryAfter?) = error {
                    guard retryAfter <= 10 else { throw error }
                    delay = max(delay, retryAfter)
                }
                attempt += 1
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    func send<Response: Decodable>(
        _ method: Method, _ path: String, query: [URLQueryItem] = [], body: Data? = nil,
        as type: Response.Type = Response.self
    ) async throws -> Response {
        let data = try await sendRaw(method, path, query: query, body: body)
        do {
            return try JSONDecoder.halo.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding(message: String(describing: error))
        }
    }

    func encode<Body: Encodable>(_ body: Body) throws -> Data {
        try JSONEncoder.halo.encode(body)
    }

    // MARK: Endpoints

    public func health() async throws -> HealthResponse {
        let url = configuration.baseURL.appendingPathComponent("health")
        let (data, response) = try await Self.perform(URLRequest(url: url), transport: transport)
        guard response.statusCode == 200 else {
            throw APIError.from(status: response.statusCode, data: data, headers: [:])
        }
        return try JSONDecoder.halo.decode(HealthResponse.self, from: data)
    }

    public func home() async throws -> HomeFeed {
        try await send(.get, "api/v1/home")
    }

    public func search(query: String, kind: SearchKind, pageToken: String?, limit: Int)
        async throws -> SearchResponse
    {
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let pageToken { items.append(URLQueryItem(name: "page_token", value: pageToken)) }
        return try await send(.get, "api/v1/search", query: items)
    }

    public func suggestions(prefix: String) async throws -> [String] {
        let response: SuggestionsResponse = try await send(
            .get, "api/v1/search/suggestions", query: [URLQueryItem(name: "q", value: prefix)])
        return response.suggestions
    }

    public func trending(pageToken: String?, limit: Int) async throws -> TrendingResponse {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let pageToken { items.append(URLQueryItem(name: "page_token", value: pageToken)) }
        return try await send(.get, "api/v1/discover/trending", query: items)
    }

    public func video(id: String) async throws -> Track {
        guard YouTubeIdentifier.isValidVideoID(id) else {
            throw APIError.server(
                status: 422, code: "invalid_video_id", message: "Invalid video id", retryAfter: nil)
        }
        return try await send(.get, "api/v1/videos/\(id)")
    }

    public func playlists(limit: Int, offset: Int) async throws -> PlaylistPage {
        try await send(.get, "api/v1/playlists", query: [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
    }

    public func playlist(id: UUID) async throws -> RemotePlaylist {
        try await send(.get, "api/v1/playlists/\(id.uuidString)")
    }

    public func createPlaylist(_ request: PlaylistCreateRequest) async throws -> RemotePlaylist {
        try await send(.post, "api/v1/playlists", body: try encode(request))
    }

    public func updatePlaylist(id: UUID, _ request: PlaylistUpdateRequest) async throws
        -> RemotePlaylist
    {
        try await send(.patch, "api/v1/playlists/\(id.uuidString)", body: try encode(request))
    }

    public func deletePlaylist(id: UUID) async throws {
        _ = try await sendRaw(.delete, "api/v1/playlists/\(id.uuidString)")
    }

    public func addPlaylistItem(playlistID: UUID, videoID: String, position: Int?) async throws
        -> RemotePlaylist
    {
        struct Body: Encodable { var videoId: String; var position: Int? }
        return try await send(
            .post, "api/v1/playlists/\(playlistID.uuidString)/items",
            body: try encode(Body(videoId: videoID, position: position)))
    }

    public func removePlaylistItem(playlistID: UUID, itemID: UUID) async throws -> RemotePlaylist {
        try await send(
            .delete, "api/v1/playlists/\(playlistID.uuidString)/items/\(itemID.uuidString)")
    }

    public func reorderPlaylist(id: UUID, itemIDs: [UUID]) async throws -> RemotePlaylist {
        struct Body: Encodable { var itemIds: [UUID] }
        return try await send(
            .put, "api/v1/playlists/\(id.uuidString)/items/order",
            body: try encode(Body(itemIds: itemIDs)))
    }

    public func aiPlaylist(_ request: AIPlaylistRequest) async throws -> PlaylistDraft {
        try await send(.post, "api/v1/ai/playlist", body: try encode(request))
    }

    public func aiChat(_ request: AIChatRequest) async throws -> AIChatResponse {
        try await send(.post, "api/v1/ai/chat", body: try encode(request))
    }

    public func sendFeedback(_ request: FeedbackRequest) async throws -> FeedbackResponse {
        try await send(.post, "api/v1/recommendations/feedback", body: try encode(request))
    }

    public func upNext(videoID: String, limit: Int) async throws -> UpNextResponse {
        guard YouTubeIdentifier.isValidVideoID(videoID) else {
            throw APIError.server(
                status: 422, code: "invalid_video_id", message: "Invalid video id", retryAfter: nil)
        }
        return try await send(.get, "api/v1/recommendations/next", query: [
            URLQueryItem(name: "video_id", value: videoID),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    public func radioStations(tag: String?, language: String?, query: String?, limit: Int)
        async throws -> [RadioStation]
    {
        var items = [URLQueryItem(name: "limit", value: String(limit))]
        if let tag, !tag.isEmpty { items.append(URLQueryItem(name: "tag", value: tag)) }
        if let language, !language.isEmpty { items.append(URLQueryItem(name: "language", value: language)) }
        if let query, !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        return try await send(.get, "api/v1/radio/stations", query: items)
    }

    public func trackMetadata(videoID: String) async throws -> TrackMetadataResponse {
        guard YouTubeIdentifier.isValidVideoID(videoID) else {
            throw APIError.server(
                status: 422, code: "invalid_video_id", message: "Invalid video id", retryAfter: nil)
        }
        return try await send(.get, "api/v1/metadata/track", query: [
            URLQueryItem(name: "video_id", value: videoID),
        ])
    }

    public func artistProfile(name: String) async throws -> ArtistProfileResponse {
        try await send(.get, "api/v1/metadata/artist", query: [URLQueryItem(name: "name", value: name)])
    }

    public func freshReleases(days: Int, upcoming: Bool, limit: Int) async throws -> [FreshRelease] {
        try await send(.get, "api/v1/discover/fresh-releases", query: [
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "upcoming", value: upcoming ? "true" : "false"),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    public func mostListened(range: ListeningRange, limit: Int) async throws -> [PopularRecording] {
        try await send(.get, "api/v1/discover/most-listened", query: [
            URLQueryItem(name: "range", value: range.rawValue),
            URLQueryItem(name: "limit", value: String(limit)),
        ])
    }

    public func preferences() async throws -> Preferences {
        try await send(.get, "api/v1/preferences")
    }

    public func updatePreferences(_ preferences: Preferences) async throws -> Preferences {
        try await send(.put, "api/v1/preferences", body: try encode(preferences))
    }

    public func taste() async throws -> TasteProfile {
        try await send(.get, "api/v1/preferences/taste")
    }

    public func resetTaste() async throws {
        _ = try await sendRaw(.delete, "api/v1/preferences/taste")
    }

    public func searchHistory() async throws -> [SearchHistoryEntry] {
        try await send(.get, "api/v1/history/search")
    }

    public func clearSearchHistory() async throws {
        _ = try await sendRaw(.delete, "api/v1/history/search")
    }

    public func exportData() async throws -> Data {
        try await sendRaw(.get, "api/v1/me/export")
    }

    public func deleteAccount() async throws {
        _ = try await sendRaw(.delete, "api/v1/me", allowReauth: false)
        tokens.deleteToken()
    }
}
