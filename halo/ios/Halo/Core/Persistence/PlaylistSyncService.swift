#if canImport(SwiftData)
import Foundation
import SwiftData

/// Mirrors local playlists to the backend (optional; controlled in Settings).
/// Local data stays authoritative: failures leave `needsSync` set for the next attempt.
@MainActor
final class PlaylistSyncService {
    private let api: MusicAPI
    private let store: LibraryStore
    private var isSyncing = false

    init(api: MusicAPI, store: LibraryStore) {
        self.api = api
        self.store = store
    }

    func syncPending() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        for playlist in store.allPlaylists() where playlist.needsSync {
            do {
                try await sync(playlist)
            } catch let error as APIError where error.isTransient {
                return  // offline: stop and retry later
            } catch {
                continue  // e.g. a song became unavailable; keep flagged, move on
            }
        }
    }

    func sync(_ playlist: PlaylistEntity) async throws {
        let localIDs = playlist.orderedItems.map(\.trackID)
        if let remoteID = playlist.remoteID {
            do {
                try await update(remoteID: remoteID, playlist: playlist, localIDs: localIDs)
            } catch let error as APIError where error.status == 404 {
                playlist.remoteID = nil  // deleted on server: recreate
                try await create(playlist, localIDs: localIDs)
            }
        } else {
            try await create(playlist, localIDs: localIDs)
        }
        playlist.needsSync = false
        store.save()
    }

    func deleteRemote(of playlist: PlaylistEntity) async {
        guard let remoteID = playlist.remoteID else { return }
        try? await api.deletePlaylist(id: remoteID)
    }

    private func create(_ playlist: PlaylistEntity, localIDs: [String]) async throws {
        let remote = try await api.createPlaylist(PlaylistCreateRequest(
            name: playlist.name, description: playlist.details, mood: playlist.mood,
            isAiGenerated: playlist.isAIGenerated,
            recommendationSessionId: playlist.recommendationSessionID,
            trackIds: Array(localIDs.prefix(200))))
        playlist.remoteID = remote.id
    }

    private func update(remoteID: UUID, playlist: PlaylistEntity, localIDs: [String]) async throws {
        var remote = try await api.updatePlaylist(id: remoteID, PlaylistUpdateRequest(
            name: playlist.name, description: playlist.details, mood: playlist.mood))
        let entries = (remote.items ?? []).map {
            PlaylistSyncPlanner.RemoteEntry(itemID: $0.id, trackID: $0.trackId)
        }
        let plan = PlaylistSyncPlanner.plan(local: localIDs, remote: entries)
        for itemID in plan.removals {
            remote = try await api.removePlaylistItem(playlistID: remoteID, itemID: itemID)
        }
        for trackID in plan.additions {
            remote = try await api.addPlaylistItem(playlistID: remoteID, trackID: trackID, position: nil)
        }
        let updated = (remote.items ?? []).map {
            PlaylistSyncPlanner.RemoteEntry(itemID: $0.id, trackID: $0.trackId)
        }
        let currentOrder = updated.map(\.itemID)
        if let desired = PlaylistSyncPlanner.order(local: localIDs, remote: updated),
           desired != currentOrder, !desired.isEmpty {
            _ = try await api.reorderPlaylist(id: remoteID, itemIDs: desired)
        }
    }
}
#endif
