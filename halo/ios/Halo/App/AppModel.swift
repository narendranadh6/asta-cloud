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
    /// Halo's voice (tap the Halo orb or say "Halo"); created on first use.
    private(set) var voice: DriveVoice?
    /// The Halo Drive screen is open.
    var driveScreenShown = false
    /// Listens for "Halo" while the app is open, when the listener turned it on.
    let wakeWord = WakeWordListener()
    @ObservationIgnored private var speaker: SystemVoiceSpeaker?
    /// UI tests run without the microphone (system permission prompts would block them).
    let voiceAvailable = !ProcessInfo.processInfo.arguments.contains("-HaloInMemoryStore")
    /// "Not today" exclusions, kept on this device until local midnight.
    let todayExclusions: TodayExclusionStore
    /// What the listener allowed to leave the device (nothing by default).
    let voiceConsent: VoiceConsent
    /// A prompt another screen wants Halo to run (e.g. "more like this" from Now Playing).
    var pendingDJPrompt: String?

    init(api: MusicAPI, settings: AppSettings, context: ModelContext) {
        self.api = api
        self.settings = settings
        library = LibraryStore(context: context)
        sync = PlaylistSyncService(api: api, store: library)
        network = NetworkMonitor()
        notifications = DiscoveryReminderScheduler()
        let inMemory = ProcessInfo.processInfo.arguments.contains("-HaloInMemoryStore")
        todayExclusions = inMemory ? MemoryTodayExclusionStore() : DefaultsTodayExclusionStore()
        voiceConsent = VoiceConsent(store: inMemory ? MemoryVoiceConsentStore() : DefaultsVoiceConsentStore())
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

    /// Halo's voice session, started on first use. Halo Flow follows the spoken session.
    @discardableResult
    func ensureVoice() -> DriveVoice {
        if let voice { return voice }
        let speaker = SystemVoiceSpeaker(player: player)
        speaker.onFinishedSpeaking = { [weak self] in self?.resumeWakeWord() }
        self.speaker = speaker
        let session = DriveSession(api: api, player: player, speaker: speaker, todayStore: todayExclusions)
        session.replyLevel = settings.voiceReplies ? .short : .silent
        session.fallbackAllowed = { [voiceConsent] in voiceConsent.isGranted(.intentFallback) }
        session.onFeedback = { [weak self] rating, track in self?.driveFeedback(rating, track) }
        session.start()
        let voice = DriveVoice(session: session, player: player, consent: voiceConsent)
        voice.onTurnFinished = { [weak self] in self?.resumeWakeWord() }
        self.voice = voice
        return voice
    }

    /// Tap on the Halo orb: listen for one command (tap again to finish early).
    func talk() {
        guard voiceAvailable else { return }
        wakeWord.pause()
        ensureVoice().talk(locale: Locale(identifier: settings.voiceLocale))
    }

    /// Opens the Halo Drive screen.
    func startDrive() {
        ensureVoice()
        driveScreenShown = true
    }

    // MARK: Wake word

    /// Starts or stops listening for "Halo" to match the setting and whether the app is open.
    func updateWakeWord(appActive: Bool) {
        guard voiceAvailable, settings.wakeWordEnabled, appActive else {
            wakeWord.stop()
            return
        }
        wakeWord.onEvent = { [weak self] event in self?.wakeWordHeard(event) }
        Task { await wakeWord.start(locale: Locale(identifier: settings.voiceLocale)) }
    }

    private func wakeWordHeard(_ event: WakeWordDetector.Event) {
        Haptics.tap(enabled: settings.hapticsEnabled)
        switch event {
        case .wake: talk()
        case let .command(text): ensureVoice().handleCommand(text)
        }
    }

    /// After a command and Halo's reply, listen for "Halo" again.
    private func resumeWakeWord() {
        guard settings.wakeWordEnabled, voice?.isListening != true, speaker?.isSpeaking != true else { return }
        wakeWord.resume()
    }

    /// Forgets what Halo Drive learned on this device (today's exclusions and the current
    /// drive's steering and listening signals). The server taste profile is reset separately.
    func resetDriveMemory() {
        todayExclusions.save([:])
        voice?.session.resetSession()
    }

    /// Closes the Halo Drive screen and ends the voice session (Halo Flow goes back to normal).
    func endDrive() {
        driveScreenShown = false
        voice?.stop()
        voice?.session.end()
        voice = nil
        resumeWakeWord()
    }

    /// "I like this" saves the song; "never play this again" tells the server (when
    /// personalization is on). Skips and "not now" stay in the session only.
    private func driveFeedback(_ rating: Rating, _ track: Track) {
        let feedback: FeedbackRating
        switch rating {
        case .like:
            library.setSaved(true, track: track)
            feedback = .save
        case .neverAgain:
            feedback = .dislike
        case .keep, .dislike, .later:
            return
        }
        guard settings.personalizationEnabled else { return }
        Task { [api] in
            _ = try? await api.sendFeedback(
                FeedbackRequest(trackId: track.id, rating: feedback, artist: track.artist))
        }
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
        resetDriveMemory()
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
