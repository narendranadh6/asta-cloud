import Foundation
import Observation

/// Speaks Halo's short replies. AVSpeechSynthesizer on iOS, a recorder in tests.
@MainActor
public protocol VoiceSpeaker: AnyObject {
    func say(_ text: String, style: SpeechStyle)
    /// Stops mid-sentence (the listener started talking again).
    func stop()
}

/// Halo Drive: turns what the listener says into session changes and music. Owns the session
/// state and a pool of ranked candidates; plays through the one `PlayerController`.
@MainActor
@Observable
public final class DriveSession {
    public enum VoiceState: Equatable, Sendable {
        case idle, listening, understanding, applying, done
        case error(String)
    }

    public private(set) var state = SessionState()
    public private(set) var voiceState: VoiceState = .idle
    public private(set) var isActive = false
    /// A few words describing the session ("Telugu · newer · more energy").
    public private(set) var summary = ""
    /// Halo's last reply, shown briefly under the artist.
    public private(set) var lastReply: String?
    public var replyLevel: ReplyLevel = .short

    /// Saves likes and "never again" in the library and on the server.
    @ObservationIgnored public var onFeedback: ((Rating, Track) -> Void)?

    @ObservationIgnored private let api: MusicAPI
    @ObservationIgnored private let player: PlayerController
    @ObservationIgnored private let speaker: VoiceSpeaker?
    @ObservationIgnored private var pool: [SessionCandidate] = []
    @ObservationIgnored private var pendingConfirmation: IntentDelta?
    @ObservationIgnored private var previousFlowProvider: ((Track) async -> [FlowSuggestion])?
    static let title = "Halo Drive"

    public init(api: MusicAPI, player: PlayerController, speaker: VoiceSpeaker?) {
        self.api = api
        self.player = player
        self.speaker = speaker
    }

    // MARK: Lifecycle

    /// Starts a drive. Halo Flow now refills from the session instead of from one song.
    public func start() {
        guard !isActive else { return }
        isActive = true
        state = SessionState()
        previousFlowProvider = player.flowProvider
        player.flowProvider = { [weak self] _ in await self?.flowSuggestions() ?? [] }
    }

    public func end() {
        guard isActive else { return }
        isActive = false
        speaker?.stop()
        player.flowProvider = previousFlowProvider
        pool = []
        voiceState = .idle
        lastReply = nil
    }

    /// The listener pressed "Talk to Halo": Halo stops talking and listens.
    public func beginListening() {
        speaker?.stop()
        voiceState = .listening
    }

    public func cancelListening() {
        if voiceState == .listening { voiceState = .idle }
    }

    public func failListening(_ message: String) {
        voiceState = .error(message)
    }

    // MARK: Handling speech

    /// Applies one utterance. `confidence` is the recognizer's (0…1).
    public func handle(_ transcript: String, confidence: Double = 1) async {
        voiceState = .understanding
        if let pending = pendingConfirmation {
            pendingConfirmation = nil
            if Self.isYes(transcript) {
                var confirmed = pending
                confirmed.confidence = 1
                await apply(confirmed)
                return
            }
            if Self.isNo(transcript) {
                reply(Self.pick(pending.speech, en: "Okay.", mixed: "సరే.", te: "సరే."),
                      style: pending.speech)
                voiceState = .done
                return
            }
        }
        var delta = IntentParser.parse(transcript)
        delta.confidence *= confidence
        if delta.needsConfirmation {
            pendingConfirmation = delta
            reply(VoiceReply.text(for: delta, level: replyLevel), style: delta.speech)
            voiceState = .done
            return
        }
        await apply(delta)
    }

    private func apply(_ delta: IntentDelta) async {
        guard !delta.isEmpty else {
            reply(VoiceReply.text(for: delta, level: replyLevel), style: delta.speech)
            voiceState = delta.unsupportedLanguages.isEmpty ? .error("Didn't catch that.") : .done
            return
        }
        voiceState = .applying
        let current = nowPlaying
        let effects = state.apply(delta, current: current)
        var spoken = VoiceReply.text(for: delta, level: replyLevel)
        for effect in effects {
            switch effect {
            case let .startPlaying(source):
                if await !startPlaying(source, delta: delta) {
                    spoken = Self.pick(delta.speech, en: "Nothing available to play.",
                                       mixed: "Play చేయడానికి ఏమీ లేదు.", te: "ఏమీ దొరకలేదు.")
                }
            case .rerank:
                await rerank()
            case let .transport(action):
                transport(action)
            case .skipCurrent:
                player.next()
            case let .feedback(rating, trackID):
                if let track = player.currentTrack, track.id == trackID { onFeedback?(rating, track) }
            case let .answer(question):
                spoken = answer(question, style: delta.speech)
            }
        }
        summary = Self.summary(of: state)
        reply(spoken, style: delta.speech)
        voiceState = .done
    }

    // MARK: Effects

    private var nowPlaying: NowPlayingContext? {
        player.currentTrack.map { NowPlayingContext(trackID: $0.id, artist: $0.artist, album: $0.album) }
    }

    /// Fetches fresh candidates for the session and starts playing them.
    private func startPlaying(_ source: PlaySource, delta: IntentDelta) async -> Bool {
        var entity: EntityRef?
        var seed: String?
        switch source {
        case let .entity(.mention(name, kind)): entity = .mention(name, kind: kind)
        case .entity(.currentArtist):
            if let artist = player.currentTrack?.artist { entity = .mention(artist, kind: .artist) }
        case .entity: seed = player.currentTrack?.id
        case .similarToCurrent: seed = player.currentTrack?.id
        case .vibe, .surprise: break
        }
        guard await refresh(seed: seed, entity: entity) else { return false }
        let ranked = SessionRanker.rank(pool, for: state, excluding: player.playedTrackIDs)
        guard !ranked.isEmpty else { return false }
        player.startHalo(Array(ranked.prefix(25)), title: Self.title)
        return true
    }

    /// Re-ranks Halo's upcoming picks instantly, then tops the pool up from the server.
    private func rerank() async {
        applyRanking()
        if await refresh(seed: player.currentTrack?.id, entity: nil) { applyRanking() }
    }

    private func applyRanking() {
        let ranked = SessionRanker.rank(pool, for: state, excluding: player.playedTrackIDs)
        if !ranked.isEmpty { player.replaceUpcomingFlow(Array(ranked.prefix(25))) }
    }

    /// Asks the server for candidates; keeps the old pool if it can't be reached (offline).
    @discardableResult
    private func refresh(seed: String?, entity: EntityRef?) async -> Bool {
        let request = SessionCandidatesRequest(
            state: state, seedTrackID: seed, entity: entity,
            alsoExclude: Array(player.playedTrackIDs), limit: 40)
        guard let response = try? await api.sessionCandidates(request) else { return false }
        pool = response.candidates
        return !pool.isEmpty
    }

    /// Halo Flow during a drive: more songs that fit the session.
    private func flowSuggestions() async -> [FlowSuggestion] {
        if pool.count < 10 { await refresh(seed: player.currentTrack?.id, entity: nil) }
        return SessionRanker.rank(pool, for: state, excluding: player.playedTrackIDs)
            .prefix(10).map { FlowSuggestion(track: $0, reason: "Halo Drive") }
    }

    private func transport(_ action: Transport) {
        switch action {
        case .pause: player.pause()
        case .resume: player.resume()
        case .next: player.next()
        case .previous: player.previous()
        case .restart: player.seek(to: 0)
        case .stop: player.stop()
        case .removeNext:
            if let next = player.queue.upNext.first { player.removeFromQueue(next.id) }
        }
    }

    /// Short answers from the current song's own metadata; never guessed.
    private func answer(_ question: Question, style: SpeechStyle) -> String? {
        let track = player.currentTrack
        let unknown = Self.pick(style, en: "Not listed.", mixed: "తెలియదు.", te: "తెలియదు.")
        switch question {
        case .whoIsSinging: return track?.artist ?? unknown
        case .whatMovie, .whatAlbum: return track?.album ?? unknown
        case .whenReleased: return track?.releaseDate.map { String($0.prefix(4)) } ?? unknown
        case .upNext:
            guard let next = player.queue.upNext.first?.track else {
                return Self.pick(style, en: "Halo will pick next.", mixed: "Halo choose చేస్తుంది.",
                                 te: "Halo ఎంచుకుంటుంది.")
            }
            return "\(next.title), \(next.artist)."
        }
    }

    // MARK: Replies

    private func reply(_ text: String?, style: SpeechStyle) {
        guard let text else { return }
        lastReply = text
        if replyLevel != .silent { speaker?.say(text, style: style) }
    }

    static func summary(of state: SessionState) -> String {
        var parts: [String] = []
        if let language = state.language {
            parts.append(language.strategy == .only ? language.primary.name
                         : "\(language.strategy.rawValue) \(language.primary.name)")
        }
        if let energy = state.vibe[.energy]?.value {
            parts.append(energy >= 0.65 ? "high energy" : energy <= 0.35 ? "calm" : "medium energy")
        }
        switch state.recency {
        case .withinDays: parts.append("new")
        case let .decade(year): parts.append("\(year % 100)s")
        case .classics: parts.append("classics")
        case .any: break
        }
        if (state.vibe[.discovery]?.value ?? 0) >= 0.65 { parts.append("discovery") }
        if state.locked { parts.append("locked") }
        return parts.joined(separator: " · ")
    }

    private static func pick(_ style: SpeechStyle, en: String, mixed: String, te: String) -> String {
        switch style {
        case .english: en
        case .mixed: mixed
        case .telugu: te
        }
    }

    static func isYes(_ text: String) -> Bool {
        !words(text).isDisjoint(with: ["yes", "yeah", "yep", "sure", "ok", "okay", "avunu", "అవును",
                                       "haan", "sare", "సరే"])
    }

    static func isNo(_ text: String) -> Bool {
        !words(text).isDisjoint(with: ["no", "nope", "cancel", "vaddu", "వద్దు", "kaadu", "కాదు"])
    }

    /// Whole words only, so "piano" never reads as "no".
    private static func words(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.nonBaseCharacters).inverted)
            .filter { !$0.isEmpty })
    }
}
