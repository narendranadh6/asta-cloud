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

    /// Which metadata source the backend is serving (demo until confirmed otherwise).
    private(set) var provider: MetadataProvider?
    private(set) var aiPlanner: String?

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
            provider = health.metadataProvider
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
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-MUSEMockAPI") {
            return MockMusicAPI()
        }
        let raw = Bundle.main.object(forInfoDictionaryKey: "MUSEAPIBaseURL") as? String
        guard let raw, let url = URL(string: raw), !raw.isEmpty else {
            assertionFailure("MUSEAPIBaseURL missing from Info.plist; using the demo API")
            return MockMusicAPI()
        }
        return APIClient(
            configuration: .init(baseURL: url), transport: URLSessionTransport.makeDefault(),
            tokens: KeychainTokenStore())
    }
}
