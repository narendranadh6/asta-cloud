#if canImport(SwiftData)
import Foundation
import SwiftData

/// All local library mutations go through here so ordering and retention rules live in
/// one tested place. Views read with `@Query` and write through this store.
@MainActor
final class LibraryStore {
    static let recentSearchLimit = 30
    /// Refresh stored YouTube metadata well inside the 30-day policy window.
    static let metadataRefreshAge: TimeInterval = 25 * 24 * 3600
    static let discoveredRetention: TimeInterval = 30 * 24 * 3600

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func save() {
        do {
            try context.save()
        } catch {
            assertionFailure("SwiftData save failed: \(error)")
        }
    }

    // MARK: Tracks

    func trackEntity(videoId: String) -> TrackEntity? {
        var descriptor = FetchDescriptor<TrackEntity>(predicate: #Predicate { $0.videoId == videoId })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Records that the user opened a song (powers "Recently discovered").
    @discardableResult
    func recordDiscovered(_ track: Track, now: Date = .now) -> TrackEntity {
        if let existing = trackEntity(videoId: track.videoId) {
            existing.update(from: track, now: now)
            existing.lastViewedAt = now
            save()
            return existing
        }
        let entity = TrackEntity(track: track, saved: false, now: now)
        context.insert(entity)
        save()
        return entity
    }

    func isSaved(videoId: String) -> Bool {
        trackEntity(videoId: videoId)?.isSaved ?? false
    }

    func setSaved(_ saved: Bool, track: Track, now: Date = .now) {
        let entity = trackEntity(videoId: track.videoId) ?? {
            let created = TrackEntity(track: track, saved: false, now: now)
            context.insert(created)
            return created
        }()
        entity.isSaved = saved
        entity.savedAt = saved ? now : nil
        save()
    }

    func savedTracks() -> [TrackEntity] {
        let descriptor = FetchDescriptor<TrackEntity>(
            predicate: #Predicate { $0.isSaved },
            sortBy: [SortDescriptor(\.savedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(
        name: String, details: String? = nil, mood: String? = nil, tracks: [Track] = [],
        isAIGenerated: Bool = false, recommendationSessionID: UUID? = nil, now: Date = .now
    ) -> PlaylistEntity {
        let cleaned = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let playlist = PlaylistEntity(
            name: cleaned.isEmpty ? "Untitled playlist" : String(cleaned.prefix(120)),
            details: details, mood: mood, isAIGenerated: isAIGenerated,
            recommendationSessionID: recommendationSessionID, now: now)
        context.insert(playlist)
        for (index, track) in tracks.enumerated() {
            let item = PlaylistItemEntity(
                track: track, provider: track.attribution.provider, position: index, now: now)
            context.insert(item)
            item.playlist = playlist
        }
        save()
        return playlist
    }

    func rename(_ playlist: PlaylistEntity, to name: String, details: String? = nil) {
        let cleaned = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !cleaned.isEmpty else { return }
        playlist.name = String(cleaned.prefix(120))
        if let details { playlist.details = details.isEmpty ? nil : details }
        touch(playlist)
    }

    func setYouTubePlaylistID(_ id: String?, on playlist: PlaylistEntity) -> Bool {
        if let id, !id.isEmpty {
            guard YouTubeIdentifier.isValidPlaylistID(id) else { return false }
            playlist.youtubePlaylistID = id
        } else {
            playlist.youtubePlaylistID = nil
        }
        touch(playlist)
        return true
    }

    func add(_ track: Track, to playlist: PlaylistEntity, at position: Int? = nil) {
        var ordered = playlist.orderedItems
        let item = PlaylistItemEntity(
            track: track, provider: track.attribution.provider, position: ordered.count)
        context.insert(item)
        item.playlist = playlist
        let index = min(max(position ?? ordered.count, 0), ordered.count)
        ordered.insert(item, at: index)
        renumber(ordered)
        touch(playlist)
    }

    func removeItems(atOffsets offsets: IndexSet, from playlist: PlaylistEntity) {
        var ordered = playlist.orderedItems
        for index in offsets.sorted(by: >) where ordered.indices.contains(index) {
            let item = ordered.remove(at: index)
            context.delete(item)
        }
        renumber(ordered)
        touch(playlist)
    }

    func moveItems(fromOffsets source: IndexSet, toOffset destination: Int,
                   in playlist: PlaylistEntity) {
        var queue = EditableQueue(playlist.orderedItems.map(IdentifiedItem.init))
        queue.move(fromOffsets: source, toOffset: destination)
        renumber(queue.items.map(\.item))
        touch(playlist)
    }

    func delete(_ playlist: PlaylistEntity) {
        context.delete(playlist)
        save()
    }

    func allPlaylists() -> [PlaylistEntity] {
        let descriptor = FetchDescriptor<PlaylistEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    private func renumber(_ items: [PlaylistItemEntity]) {
        for (index, item) in items.enumerated() where item.position != index {
            item.position = index
        }
    }

    private func touch(_ playlist: PlaylistEntity) {
        playlist.updatedAt = .now
        playlist.needsSync = true
        save()
    }

    // MARK: Searches & artists

    func recordSearch(_ query: String, kind: SearchKind, now: Date = .now) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let all = (try? context.fetch(FetchDescriptor<RecentSearchEntity>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]))) ?? []
        var kept: [RecentSearchEntity] = []
        for entry in all {
            if entry.query.caseInsensitiveCompare(trimmed) == .orderedSame {
                context.delete(entry)
            } else {
                kept.append(entry)
            }
        }
        for entry in kept.dropFirst(Self.recentSearchLimit - 1) {
            context.delete(entry)
        }
        context.insert(RecentSearchEntity(query: trimmed, kind: kind, now: now))
        save()
    }

    func clearRecentSearches() {
        try? context.delete(model: RecentSearchEntity.self)
        save()
    }

    func setArtist(_ name: String, excluded: Bool) {
        let normalized = ArtistEntity.normalize(name)
        guard !normalized.isEmpty else { return }
        var descriptor = FetchDescriptor<ArtistEntity>(
            predicate: #Predicate { $0.normalizedName == normalized })
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            existing.isExcluded = excluded
        } else {
            context.insert(ArtistEntity(name: name.trimmingCharacters(in: .whitespaces),
                                        excluded: excluded))
        }
        save()
    }

    func removeArtist(_ artist: ArtistEntity) {
        context.delete(artist)
        save()
    }

    func artists(excluded: Bool) -> [ArtistEntity] {
        let descriptor = FetchDescriptor<ArtistEntity>(
            predicate: #Predicate { $0.isExcluded == excluded },
            sortBy: [SortDescriptor(\.addedAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: Retention & privacy

    /// Refreshes stale metadata through the backend and drops old unsaved discoveries.
    func enforceRetention(using api: MusicAPI, now: Date = .now) async {
        let cutoff = now.addingTimeInterval(-Self.discoveredRetention)
        let staleDiscovered = (try? context.fetch(FetchDescriptor<TrackEntity>(
            predicate: #Predicate { !$0.isSaved && $0.lastViewedAt < cutoff }))) ?? []
        for entity in staleDiscovered {
            context.delete(entity)
        }
        save()

        let refreshCutoff = now.addingTimeInterval(-Self.metadataRefreshAge)
        let stale = (try? context.fetch(FetchDescriptor<TrackEntity>(
            predicate: #Predicate { $0.metadataFetchedAt < refreshCutoff }))) ?? []
        for entity in stale.prefix(25) {
            do {
                let track = try await api.video(id: entity.videoId)
                entity.update(from: track, now: now)
            } catch let error as APIError where error.status == 404 {
                entity.isAvailable = false
                entity.title = "Unavailable video"
                entity.channelTitle = "Unavailable"
                entity.artworkURLString = nil
                entity.metadataFetchedAt = now
            } catch {
                break  // offline or quota: try again next launch
            }
        }
        save()
    }

    /// Deletes everything stored on this device.
    func wipeAll() {
        for model in LibrarySchema.models {
            try? context.delete(model: model)
        }
        save()
    }

    /// Local library as JSON for data export.
    func exportJSON() throws -> Data {
        struct Export: Encodable {
            struct Song: Encodable { var videoId, title, channelTitle: String; var saved: Bool }
            struct List: Encodable {
                var name: String
                var details: String?
                var isAIGenerated: Bool
                var videoIds: [String]
            }
            var savedSongs: [Song]
            var playlists: [List]
            var recentSearches: [String]
            var favoriteArtists: [String]
            var excludedArtists: [String]
        }
        let tracks = (try? context.fetch(FetchDescriptor<TrackEntity>())) ?? []
        let searches = (try? context.fetch(FetchDescriptor<RecentSearchEntity>(
            sortBy: [SortDescriptor(\.searchedAt, order: .reverse)]))) ?? []
        let export = Export(
            savedSongs: tracks.map { .init(videoId: $0.videoId, title: $0.title,
                                           channelTitle: $0.channelTitle, saved: $0.isSaved) },
            playlists: allPlaylists().map {
                .init(name: $0.name, details: $0.details, isAIGenerated: $0.isAIGenerated,
                      videoIds: $0.orderedItems.map(\.videoId))
            },
            recentSearches: searches.map(\.query),
            favoriteArtists: artists(excluded: false).map(\.name),
            excludedArtists: artists(excluded: true).map(\.name))
        let encoder = JSONEncoder.halo
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }
}

/// Wraps a SwiftData model so it can be reordered with the shared `EditableQueue` logic.
private struct IdentifiedItem: Identifiable, @unchecked Sendable {
    let item: PlaylistItemEntity
    var id: UUID { item.id }
}
#endif
