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
    let sync: PlaylistSyncService
    let network: NetworkMonitor
    let notifications: DiscoveryReminderScheduler
    /// The one audio player: songs and live radio both play through it.
    let player: PlayerController
    private let mediaControls: SystemMediaControls

    /// False when the server reports it has no music source enabled.
    private(set) var catalogConfigured = true
    private(set) var musicSources: [String] = []
    private(set) var aiPlanner: String?
    /// A prompt another screen wants the AI DJ to run (e.g. "more like this" from Now Playing).
    var pendingDJPrompt: String?

    init(api: MusicAPI, settings: AppSettings, context: ModelContext) {
        self.api = api
        self.settings = settings
        library = LibraryStore(context: context)
        sync = PlaylistSyncService(api: api, store: library)
        network = NetworkMonitor()
        notifications = DiscoveryReminderScheduler()
        // UI tests start from a clean player every run.
        let restores = !ProcessInfo.processInfo.arguments.contains("-HaloInMemoryStore")
        player = PlayerController(
            engine: StreamingAudioEngine(),
            sessionStore: restores ? FilePlaybackSessionStore() : nil)
        mediaControls = SystemMediaControls(player: player)
        // Songs that actually start playing count as "recently discovered".
        player.onTrackStarted = { [weak library] track in library?.recordDiscovered(track) }
        // A restored or failing song gets a fresh stream link from the server first.
        player.resolveTrack = { [api] track in try await api.track(id: track.id) }
        // Halo Flow continues from the current song with the server's up-next picks.
        player.autoplayEnabled = settings.autoplay
        player.flowProvider = { [api] seed in
            let response = try? await api.upNext(trackID: seed.id, limit: 10)
            return response?.tracks.map(FlowSuggestion.init) ?? []
        }
        player.restoreSession()
    }

    /// Startup work: catalog status, retention, pending sync.
    func bootstrap() async {
        if let health = try? await api.health() {
            catalogConfigured = health.isCatalogConfigured
            musicSources = health.musicSources
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
        let override = ProcessInfo.processInfo.environment["HALO_API_BASE_URL"]
        let raw = override ?? Bundle.main.object(forInfoDictionaryKey: "HaloAPIBaseURL") as? String
        guard let raw, let url = URL(string: raw), url.scheme != nil else {
            preconditionFailure("HaloAPIBaseURL is missing from Info.plist")
        }
        // UI tests run unsigned builds, which have no Keychain access.
        let tokens: TokenStore = ProcessInfo.processInfo.arguments.contains("-HaloInMemoryStore")
            ? InMemoryTokenStore() : FallbackTokenStore(primary: KeychainTokenStore())
        return APIClient(
            configuration: .init(baseURL: url), transport: URLSessionTransport.makeDefault(),
            tokens: tokens)
    }
}
