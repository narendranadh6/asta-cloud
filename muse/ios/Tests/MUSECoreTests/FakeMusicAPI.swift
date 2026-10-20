import Foundation
#if canImport(MUSECore)
@testable import MUSECore
#else
@testable import MUSE
#endif

/// In-memory MusicAPI for unit tests. Test-only; never part of the app.
actor FakeMusicAPI: MusicAPI {
    public private(set) var catalog: [Track]
    private var remotePlaylists: [UUID: RemotePlaylist] = [:]
    private var prefs = Preferences()
    private var history: [SearchHistoryEntry] = []
    public var failNextRequest: APIError?
    public private(set) var searchCalls: [(query: String, pageToken: String?)] = []

    public init(catalog: [Track] = FakeMusicAPI.sampleCatalog()) {
        self.catalog = catalog
    }

    public func setFailure(_ error: APIError?) {
        failNextRequest = error
    }

    private func checkFailure() throws {
        if let error = failNextRequest {
            failNextRequest = nil
            throw error
        }
    }

    public static func sampleCatalog() -> [Track] {
        let names = [
            ("Telugu Melody No. 1", "Aarav Strings"), ("Moonlit Lofi", "The Quiet Hours"),
            ("Monsoon Drive", "Madras Monsoon"), ("Saanjh (Live Session)", "Saanjh Project"),
            ("Neon Run (Remix)", "Dawn Circuit"), ("Sol de Tarde", "Luz de Mar"),
            ("Late Night Commit", "Velvet Atlas"), ("Raag at Dawn", "Raag Riders"),
            ("Seoul Lights", "Hanbit Room"), ("Kaveri Breeze", "Kaveri Echo"),
            ("Midnight Coffee", "Northern Static"), ("Godavari Evenings", "Godavari Collective"),
        ]
        return names.enumerated().map { index, entry in
            let id = "tst" + String(format: "%08d", index)
            return Track(
                videoId: id, title: entry.0, channelTitle: entry.1,
                thumbnails: ["high": Thumbnail(
                    url: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg", width: 480, height: 360)],
                durationSeconds: 150 + index * 17, viewCount: 1_000 * (index + 1) * (index + 1),
                watchUrl: "https://www.youtube.com/watch?v=\(id)",
                attribution: Attribution(provider: .youtube, label: "YouTube"))
        }
    }

    public func health() async throws -> HealthResponse {
        HealthResponse(status: "ok", metadataProvider: .youtube, aiPlanner: "heuristic", checks: ["youtube": "ok"])
    }

    public func search(query: String, kind: SearchKind, pageToken: String?, limit: Int)
        async throws -> SearchResponse
    {
        try checkFailure()
        searchCalls.append((query, pageToken))
        let words = query.lowercased().split(separator: " ").map(String.init)
        let matches = catalog.filter { track in
            let haystack = "\(track.title) \(track.channelTitle)".lowercased()
            return words.contains { haystack.contains($0) } || words.isEmpty
        }
        let offset = pageToken.flatMap(Int.init) ?? 0
        let page = Array(matches.dropFirst(offset).prefix(limit))
        let next = offset + limit < matches.count ? String(offset + limit) : nil
        if pageToken == nil {
            history.insert(
                SearchHistoryEntry(
                    id: UUID(), query: query, kind: kind.rawValue, resultCount: page.count,
                    createdAt: Date()), at: 0)
        }
        return SearchResponse(
            query: query, kind: kind, items: page, nextPageToken: next,
            prevPageToken: offset > 0 ? String(max(0, offset - limit)) : nil,
            totalResultsEstimate: matches.count, provider: .youtube, cached: false)
    }

    public func suggestions(prefix: String) async throws -> [String] {
        let seeds = ["telugu melodies", "lofi beats for coding", "road trip rock", "k-pop dance"]
        let own = history.map(\.query)
        return Array((own + seeds).filter { prefix.isEmpty || $0.hasPrefix(prefix.lowercased()) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(8))
    }

    public func trending(pageToken: String?, limit: Int) async throws -> TrendingResponse {
        try checkFailure()
        let ranked = catalog.sorted { ($0.viewCount ?? 0) > ($1.viewCount ?? 0) }
        let offset = pageToken.flatMap(Int.init) ?? 0
        let next = offset + limit < ranked.count ? String(offset + limit) : nil
        return TrendingResponse(
            items: Array(ranked.dropFirst(offset).prefix(limit)), nextPageToken: next,
            prevPageToken: nil, provider: .youtube, cached: false, source: "test")
    }

    public func upNext(videoID: String, limit: Int) async throws -> UpNextResponse {
        try checkFailure()
        let picks = catalog.filter { $0.videoId != videoID }.prefix(limit).map {
            RecommendedTrack(track: $0, score: 1, reasons: ["Similar listeners saved this"],
                             matchedQuery: "co-listening", source: "co_listen", explore: false)
        }
        return UpNextResponse(seedVideoId: videoID, tracks: Array(picks))
    }

    public func radioStations(tag: String?, language: String?, query: String?, limit: Int)
        async throws -> [RadioStation]
    {
        try checkFailure()
        return [RadioStation(
            id: "s1", name: "Test FM", streamUrl: "https://radio.test/live", homepage: nil,
            favicon: nil, tags: [tag ?? "pop"], countryCode: "IN", language: language, codec: "MP3",
            bitrate: 128, popularity: 10)]
    }

    public func video(id: String) async throws -> Track {
        try checkFailure()
        guard let track = catalog.first(where: { $0.videoId == id }) else {
            throw APIError.server(
                status: 404, code: "video_unavailable", message: "This video is unavailable",
                retryAfter: nil)
        }
        return track
    }

    private func makeRemote(_ id: UUID, name: String, videoIDs: [String], existing: RemotePlaylist?)
        -> RemotePlaylist
    {
        let items = videoIDs.enumerated().compactMap { index, vid -> RemotePlaylistItem? in
            guard let track = catalog.first(where: { $0.videoId == vid }) else { return nil }
            return RemotePlaylistItem(
                id: UUID(), position: index, note: nil, videoId: vid, title: track.title,
                channelTitle: track.channelTitle, thumbnailUrl: track.artworkURL?.absoluteString,
                durationSeconds: track.durationSeconds, isAvailable: true,
                watchUrl: track.watchUrl, addedAt: Date())
        }
        return RemotePlaylist(
            id: id, name: name, description: existing?.description, mood: existing?.mood,
            isAiGenerated: existing?.isAiGenerated ?? false, youtubePlaylistId: nil,
            youtubePlaylistUrl: nil, itemCount: items.count,
            totalDurationSeconds: items.compactMap(\.durationSeconds).reduce(0, +),
            artworkUrl: items.first?.thumbnailUrl, createdAt: existing?.createdAt ?? Date(),
            updatedAt: Date(), items: items)
    }

    public func playlists(limit: Int, offset: Int) async throws -> PlaylistPage {
        let all = remotePlaylists.values.sorted { $0.updatedAt > $1.updatedAt }
        return PlaylistPage(
            items: Array(all.dropFirst(offset).prefix(limit)), total: all.count, limit: limit,
            offset: offset)
    }

    public func playlist(id: UUID) async throws -> RemotePlaylist {
        guard let playlist = remotePlaylists[id] else {
            throw APIError.server(status: 404, code: "not_found", message: "Playlist not found",
                                  retryAfter: nil)
        }
        return playlist
    }

    public func createPlaylist(_ request: PlaylistCreateRequest) async throws -> RemotePlaylist {
        try checkFailure()
        let id = UUID()
        var playlist = makeRemote(id, name: request.name, videoIDs: request.videoIds, existing: nil)
        playlist.description = request.description
        playlist.isAiGenerated = request.isAiGenerated
        remotePlaylists[id] = playlist
        return playlist
    }

    public func updatePlaylist(id: UUID, _ request: PlaylistUpdateRequest) async throws
        -> RemotePlaylist
    {
        var playlist = try await self.playlist(id: id)
        if let name = request.name { playlist.name = name }
        if let description = request.description { playlist.description = description }
        remotePlaylists[id] = playlist
        return playlist
    }

    public func deletePlaylist(id: UUID) async throws {
        remotePlaylists[id] = nil
    }

    public func addPlaylistItem(playlistID: UUID, videoID: String, position: Int?) async throws
        -> RemotePlaylist
    {
        let playlist = try await self.playlist(id: playlistID)
        var ids = (playlist.items ?? []).map(\.videoId)
        ids.insert(videoID, at: min(position ?? ids.count, ids.count))
        let updated = makeRemote(playlistID, name: playlist.name, videoIDs: ids, existing: playlist)
        remotePlaylists[playlistID] = updated
        return updated
    }

    public func removePlaylistItem(playlistID: UUID, itemID: UUID) async throws -> RemotePlaylist {
        var playlist = try await self.playlist(id: playlistID)
        var items = (playlist.items ?? []).filter { $0.id != itemID }
        for index in items.indices { items[index].position = index }
        playlist.items = items
        playlist.itemCount = items.count
        remotePlaylists[playlistID] = playlist
        return playlist
    }

    public func reorderPlaylist(id: UUID, itemIDs: [UUID]) async throws -> RemotePlaylist {
        var playlist = try await self.playlist(id: id)
        let byID = Dictionary(uniqueKeysWithValues: (playlist.items ?? []).map { ($0.id, $0) })
        playlist.items = itemIDs.enumerated().compactMap { index, itemID in
            guard var item = byID[itemID] else { return nil }
            item.position = index
            return item
        }
        remotePlaylists[id] = playlist
        return playlist
    }

    private func draft(for text: String, minutes: Int, excluding: Set<String>) -> PlaylistDraft {
        var picked: [RecommendedTrack] = []
        var total = 0
        for track in catalog where !excluding.contains(track.videoId) {
            guard total < minutes * 60 else { break }
            picked.append(RecommendedTrack(
                track: track, score: 1, reasons: ["Test pick for “\(text)”"], matchedQuery: text))
            total += track.durationSeconds ?? 0
        }
        return PlaylistDraft(
            sessionId: nil, title: "Test Mix", explanation: "Here's a mix for “\(text)”.",
            planner: "heuristic", queries: [text], tracks: picked, totalDurationSeconds: total,
            targetDurationSeconds: minutes * 60, provider: .youtube,
            warnings: [])
    }

    public func aiPlaylist(_ request: AIPlaylistRequest) async throws -> PlaylistDraft {
        try checkFailure()
        return draft(
            for: request.description, minutes: request.durationMinutes,
            excluding: Set(request.excludeVideoIds))
    }

    public func aiChat(_ request: AIChatRequest) async throws -> AIChatResponse {
        try checkFailure()
        let result = draft(for: request.message, minutes: 20, excluding: [])
        return AIChatResponse(
            conversationId: nil, reply: result.explanation, draft: result, stored: false)
    }

    public func sendFeedback(_ request: FeedbackRequest) async throws -> FeedbackResponse {
        FeedbackResponse(
            id: UUID(), videoId: request.videoId, rating: request.rating,
            recorded: prefs.personalizationEnabled)
    }

    public func preferences() async throws -> Preferences { prefs }

    public func updatePreferences(_ preferences: Preferences) async throws -> Preferences {
        prefs = preferences
        return prefs
    }

    public func taste() async throws -> TasteProfile {
        TasteProfile(
            personalizationEnabled: prefs.personalizationEnabled,
            basis: "Inferred from your activity inside MUSE. MUSE cannot see what you play in Brave.",
            topArtists: prefs.favoriteArtists.map {
                TasteSignal(label: $0.name, weight: 3, evidence: "marked as favorite")
            },
            topTerms: [], declaredLanguages: prefs.languages, declaredGenres: prefs.genres,
            excludedArtists: prefs.excludedArtists.map(\.name),
            activityCounts: ["playlists": remotePlaylists.count, "searches": history.count,
                             "feedback": 0])
    }

    public func resetTaste() async throws { history.removeAll() }
    public func searchHistory() async throws -> [SearchHistoryEntry] { history }
    public func clearSearchHistory() async throws { history.removeAll() }

    public func exportData() async throws -> Data {
        try JSONEncoder.muse.encode(["playlists": Array(remotePlaylists.values.map(\.name))])
    }

    public func deleteAccount() async throws {
        remotePlaylists.removeAll()
        history.removeAll()
        prefs = Preferences()
    }
}
