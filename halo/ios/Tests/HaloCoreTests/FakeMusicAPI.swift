import Foundation
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
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

    /// Answer ListenBrainz calls the way the server does when discovery is switched off.
    public private(set) var discoveryDisabled = false
    public func setDiscoveryDisabled(_ disabled: Bool) {
        discoveryDisabled = disabled
    }

    private func checkDiscovery() throws {
        if discoveryDisabled {
            throw APIError.server(
                status: 503, code: "discovery_disabled", message: "Discovery is off", retryAfter: nil)
        }
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
            let sid = "tst" + String(format: "%05d", index)
            return Track(
                id: "audius:\(sid)", source: .audius, sourceId: sid, title: entry.0,
                artist: entry.1, artworkUrl: "https://art.test/\(sid).jpg",
                durationSeconds: 150 + index * 17, genre: "Electronic",
                playCount: 1_000 * (index + 1) * (index + 1),
                streamUrl: "https://stream.test/\(sid).mp3",
                externalUrl: "https://audius.test/\(sid)",
                attribution: Attribution(provider: .audius, label: "Audius"))
        }
    }

    public func health() async throws -> HealthResponse {
        HealthResponse(
            status: "ok", musicSources: ["audius"], aiPlanner: "heuristic",
            checks: ["catalog": "ok"])
    }

    public func search(query: String, kind: SearchKind, pageToken: String?, limit: Int)
        async throws -> SearchResponse
    {
        try checkFailure()
        searchCalls.append((query, pageToken))
        let words = query.lowercased().split(separator: " ").map(String.init)
        let matches = catalog.filter { track in
            let haystack = "\(track.title) \(track.artist)".lowercased()
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
            totalResultsEstimate: matches.count, sources: ["audius"], cached: false)
    }

    public func suggestions(prefix: String) async throws -> [String] {
        let seeds = ["telugu melodies", "lofi beats for coding", "road trip rock", "k-pop dance"]
        let own = history.map(\.query)
        return Array((own + seeds).filter { prefix.isEmpty || $0.hasPrefix(prefix.lowercased()) }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.prefix(8))
    }

    public private(set) var trendingGenres: [String?] = []

    public func trending(genre: String?, limit: Int) async throws -> TrendingResponse {
        try checkFailure()
        trendingGenres.append(genre)
        let ranked = catalog.sorted { ($0.playCount ?? 0) > ($1.playCount ?? 0) }
        return TrendingResponse(
            items: Array(ranked.prefix(limit)), nextPageToken: nil, prevPageToken: nil,
            sources: ["audius"], cached: false, source: "test")
    }

    public func upNext(trackID: String, limit: Int) async throws -> UpNextResponse {
        try checkFailure()
        let picks = catalog.filter { $0.id != trackID }.prefix(limit).map {
            RecommendedTrack(track: $0, score: 1, reasons: ["Similar listeners saved this"],
                             matchedQuery: "co-listening", source: "co_listen", explore: false)
        }
        return UpNextResponse(seedTrackId: trackID, tracks: Array(picks))
    }

    public private(set) var homeSections: [HomeSection]?
    public func setHomeSections(_ sections: [HomeSection]?) {
        homeSections = sections
    }

    public func home() async throws -> HomeFeed {
        try checkFailure()
        let sections = homeSections ?? [
            HomeSection(id: "moods", type: "moods", title: "Play something for…", layout: .tiles,
                        items: [HomeItem(kind: .mood, id: "focused", title: "Focus")], score: 90),
            HomeSection(id: "trending", type: "trending", title: "Trending now", layout: .rail,
                        items: catalog.prefix(3).map {
                            HomeItem(kind: .track, id: $0.id, title: $0.title, track: $0)
                        }, source: "Audius", score: 64),
        ]
        return HomeFeed(sections: sections, personalized: false, generatedAt: Date())
    }

    public func trackMetadata(trackID: String) async throws -> TrackMetadataResponse {
        try checkFailure()
        guard let track = catalog.first(where: { $0.id == trackID }) else {
            return TrackMetadataResponse(
                trackId: trackID, parsedArtist: "", parsedTitle: "", matched: false,
                recording: nil, artist: nil, source: "MusicBrainz")
        }
        let release = ReleaseInfo(
            mbid: "rel-1", title: "\(track.title) (Single)", date: "2024-05-01", country: "IN",
            status: "Official", releaseGroupMbid: "rg-1", releaseGroupType: "Single",
            labels: [RecordLabel(name: "Test Records", mbid: nil, catalogNumber: "TR-1")],
            coverArtUrl: nil)
        let recording = CanonicalRecording(
            recordingMbid: "rec-1", title: track.title,
            artistCredit: [ArtistCredit(name: track.artist, mbid: "art-1", joinPhrase: "")],
            lengthMs: track.durationSeconds.map { $0 * 1000 }, firstReleaseDate: "2024-05-01",
            isrcs: ["INTST2400001"], genres: ["indie pop"], releases: [release], matchScore: 100,
            musicbrainzUrl: "https://musicbrainz.org/recording/rec-1")
        return TrackMetadataResponse(
            trackId: trackID, parsedArtist: track.artist, parsedTitle: track.title,
            matched: true, recording: recording, artist: nil, source: "MusicBrainz")
    }

    public func artistProfile(name: String) async throws -> ArtistProfileResponse {
        try checkFailure()
        return ArtistProfileResponse(artist: nil, popularRecordings: [], sources: ["MusicBrainz"])
    }

    public func freshReleases(days: Int, upcoming: Bool, limit: Int) async throws -> [FreshRelease] {
        try checkFailure()
        try checkDiscovery()
        return catalog.prefix(limit).enumerated().map { index, track in
            FreshRelease(
                releaseMbid: "fresh-\(index)", releaseName: track.title, artistName: track.artist,
                artistMbids: [], releaseDate: "2026-10-1\(index % 10)", releaseGroupMbid: nil,
                releaseType: "Single", tags: [], listenCount: 100 - index, coverArtUrl: nil,
                source: "ListenBrainz")
        }
    }

    public func mostListened(range: ListeningRange, limit: Int) async throws -> [PopularRecording] {
        try checkFailure()
        try checkDiscovery()
        return catalog.prefix(limit).enumerated().map { index, track in
            PopularRecording(
                recordingMbid: "pop-\(index)", title: track.title, artistName: track.artist,
                releaseName: nil, listenCount: 1000 - index, listenerCount: nil, lengthMs: nil,
                similarTo: nil, source: "ListenBrainz")
        }
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

    public func track(id: String) async throws -> Track {
        try checkFailure()
        guard let track = catalog.first(where: { $0.id == id }) else {
            throw APIError.server(
                status: 404, code: "track_unavailable", message: "This song is unavailable",
                retryAfter: nil)
        }
        return track
    }

    /// One artist ("audius:tstArtist") and one album ("audius:tstAlbum") over the sample catalog.
    public func artist(id: String) async throws -> ArtistPage {
        try checkFailure()
        guard id == "audius:tstArtist" else { throw Self.notFound("artist") }
        return ArtistPage(
            id: id, source: .audius, name: "Aarav Strings", handle: "aarav", artworkUrl: nil,
            coverUrl: nil, bio: "Strings from Hyderabad.", followerCount: 1200,
            externalUrl: "https://audius.test/aarav",
            attribution: Attribution(provider: .audius, label: "Audius"),
            topTracks: Array(catalog.prefix(4)),
            albums: [AlbumSummary(
                id: "audius:tstAlbum", source: .audius, title: "First Light", artist: "Aarav Strings",
                artistId: id, artworkUrl: nil, releaseDate: "2026-03-01", trackCount: 3,
                externalUrl: nil)])
    }

    public func album(id: String) async throws -> AlbumPage {
        try checkFailure()
        guard id == "audius:tstAlbum" else { throw Self.notFound("album") }
        return AlbumPage(
            id: id, source: .audius, title: "First Light", artist: "Aarav Strings",
            artistId: "audius:tstArtist", artworkUrl: nil, artworkUrlLarge: nil,
            releaseDate: "2026-03-01", trackCount: 3, externalUrl: nil,
            attribution: Attribution(provider: .audius, label: "Audius"),
            tracks: Array(catalog.prefix(3)))
    }

    private static func notFound(_ kind: String) -> APIError {
        .server(status: 404, code: "\(kind)_unavailable", message: "This \(kind) isn't available",
                retryAfter: nil)
    }

    private func makeRemote(_ id: UUID, name: String, trackIDs: [String], existing: RemotePlaylist?)
        -> RemotePlaylist
    {
        let items = trackIDs.enumerated().compactMap { index, tid -> RemotePlaylistItem? in
            guard let track = catalog.first(where: { $0.id == tid }) else { return nil }
            return RemotePlaylistItem(
                id: UUID(), position: index, note: nil, trackId: tid, title: track.title,
                artist: track.artist, album: track.album, artworkUrl: track.artworkUrl,
                durationSeconds: track.durationSeconds, streamUrl: track.streamUrl,
                isPreview: track.isPreview, isAvailable: true, addedAt: Date())
        }
        return RemotePlaylist(
            id: id, name: name, description: existing?.description, mood: existing?.mood,
            isAiGenerated: existing?.isAiGenerated ?? false, itemCount: items.count,
            totalDurationSeconds: items.compactMap(\.durationSeconds).reduce(0, +),
            artworkUrl: items.first?.artworkUrl, createdAt: existing?.createdAt ?? Date(),
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
        var playlist = makeRemote(id, name: request.name, trackIDs: request.trackIds, existing: nil)
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

    public func addPlaylistItem(playlistID: UUID, trackID: String, position: Int?) async throws
        -> RemotePlaylist
    {
        let playlist = try await self.playlist(id: playlistID)
        var ids = (playlist.items ?? []).map(\.trackId)
        ids.insert(trackID, at: min(position ?? ids.count, ids.count))
        let updated = makeRemote(playlistID, name: playlist.name, trackIDs: ids, existing: playlist)
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
        for track in catalog where !excluding.contains(track.id) {
            guard total < minutes * 60 else { break }
            picked.append(RecommendedTrack(
                track: track, score: 1, reasons: ["Test pick for “\(text)”"], matchedQuery: text))
            total += track.durationSeconds ?? 0
        }
        return PlaylistDraft(
            sessionId: nil, title: "Test Mix", explanation: "Here's a mix for “\(text)”.",
            planner: "heuristic", queries: [text], tracks: picked, totalDurationSeconds: total,
            targetDurationSeconds: minutes * 60, sources: ["audius"],
            warnings: [])
    }

    public func aiPlaylist(_ request: AIPlaylistRequest) async throws -> PlaylistDraft {
        try checkFailure()
        return draft(
            for: request.description, minutes: request.durationMinutes,
            excluding: Set(request.excludeTrackIds))
    }

    public func aiChat(_ request: AIChatRequest) async throws -> AIChatResponse {
        try checkFailure()
        let result = draft(for: request.message, minutes: 20, excluding: [])
        return AIChatResponse(
            conversationId: nil, reply: result.explanation, draft: result, stored: false)
    }

    public func sendFeedback(_ request: FeedbackRequest) async throws -> FeedbackResponse {
        FeedbackResponse(
            id: UUID(), trackId: request.trackId, rating: request.rating,
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
            basis: "Inferred from your activity inside Halo. It never leaves your account.",
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
        try JSONEncoder.halo.encode(["playlists": Array(remotePlaylists.values.map(\.name))])
    }

    public func deleteAccount() async throws {
        remotePlaylists.removeAll()
        history.removeAll()
        prefs = Preferences()
    }
}
