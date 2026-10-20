import Foundation
import Observation
import SwiftData

/// Dependency container shared through the SwiftUI environment.
@MainActor
@Observable
final class AppModel {
    let api: MusicAPI
    let settings: AppSettings
    let library: LibraryStore
    let handoff: BraveBrowserHandoffService
    let sync: PlaylistSyncService
    let network: NetworkMonitor
    let notifications: DiscoveryReminderScheduler
    let radio = RadioPlayer()

    /// False when the server reports it has no YouTube API key yet.
    private(set) var searchConfigured = true
    private(set) var aiPlanner: String?
    /// A prompt another screen wants the AI DJ to run (e.g. "find similar" from Now in Brave).
    var pendingDJPrompt: String?

    init(api: MusicAPI, settings: AppSettings, context: ModelContext, opener: URLOpening) {
        self.api = api
        self.settings = settings
        library = LibraryStore(context: context)
        handoff = BraveBrowserHandoffService(opener: opener, preference: { [settings] in
            settings.browserPreference
        })
        sync = PlaylistSyncService(api: api, store: library)
        network = NetworkMonitor()
        notifications = DiscoveryReminderScheduler()
    }

    /// Startup work: provider status, retention, pending sync.
    func bootstrap() async {
        if let health = try? await api.health() {
            searchConfigured = health.isSearchConfigured
            aiPlanner = health.aiPlanner
        }
        await library.enforceRetention(using: api)
        if settings.syncPlaylists {
            await sync.syncPending()
        }
    }

    func playlistChanged(_ playlist: PlaylistEntity) {
        guard settings.syncPlaylists else { return }
        Task { try? await sync.sync(playlist) }
    }

    /// Deletes the server account and everything on this device.
    func deleteEverything() async throws {
        try await api.deleteAccount()
        library.wipeAll()
        settings.reset()
        await notifications.cancelAll()
    }

    static func makeAPI() -> MusicAPI {
        // UI tests and staging builds can point at another server.
        let override = ProcessInfo.processInfo.environment["MUSE_API_BASE_URL"]
        let raw = override ?? Bundle.main.object(forInfoDictionaryKey: "MUSEAPIBaseURL") as? String
        guard let raw, let url = URL(string: raw), url.scheme != nil else {
            preconditionFailure("MUSEAPIBaseURL is missing from Info.plist")
        }
        return APIClient(
            configuration: .init(baseURL: url), transport: URLSessionTransport.makeDefault(),
            tokens: KeychainTokenStore())
    }
}
