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
    @ObservationIgnored private var previousSkipHandler: ((Track, Double) -> Void)?
    @ObservationIgnored private var previousCompletionHandler: ((Track) -> Void)?
    @ObservationIgnored private var previousReplayHandler: ((Track) -> Void)?
    @ObservationIgnored private let resolver: EntityResolver
    @ObservationIgnored private let todayStore: TodayExclusionStore?
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let timeZone: @Sendable () -> TimeZone
    /// Names Halo asked about ("Ilaiyaraaja or Yuvan Shankar Raja?"), waiting for the answer.
    @ObservationIgnored private var pendingChoice: (delta: IntentDelta, said: String,
                                                    options: [EntityResolver.Entity])?
    static let title = "Halo Drive"

    public init(api: MusicAPI, player: PlayerController, speaker: VoiceSpeaker?,
                resolver: EntityResolver = EntityResolver(), todayStore: TodayExclusionStore? = nil,
                now: @escaping @Sendable () -> Date = { Date() },
                timeZone: @escaping @Sendable () -> TimeZone = { TimeZone.current }) {
        self.api = api
        self.player = player
        self.speaker = speaker
        self.resolver = resolver
        self.todayStore = todayStore
        self.now = now
        self.timeZone = timeZone
    }

    // MARK: Lifecycle

    /// Starts a drive. Halo Flow now refills from the session instead of from one song.
    public func start() {
        guard !isActive else { return }
        isActive = true
        state = SessionState()
        state.restoreTodayExclusions(todayStore?.load() ?? [:], now: now())
        previousFlowProvider = player.flowProvider
        player.flowProvider = { [weak self] _ in await self?.flowSuggestions() ?? [] }
        previousSkipHandler = player.onListenerSkip
        player.onListenerSkip = { [weak self] track, heard in
            self?.previousSkipHandler?(track, heard)
            self?.listened(.skip(heard: heard, duration: track.durationSeconds.map(Double.init)), track)
        }
        previousCompletionHandler = player.onTrackCompleted
        player.onTrackCompleted = { [weak self] track in
            self?.previousCompletionHandler?(track)
            self?.listened(.complete, track)
        }
        previousReplayHandler = player.onListenerReplay
        player.onListenerReplay = { [weak self] track in
            self?.previousReplayHandler?(track)
            self?.listened(.replay, track)
        }
    }

    /// Skips, completions and replays are weak, session-only signals (see
    /// `SessionState.SignalWeights`); a short skip never becomes a dislike.
    private func listened(_ signal: SessionState.ListeningSignal, _ track: Track) {
        state.record(signal, for: NowPlayingContext(trackID: track.id, artist: track.artist,
                                                     album: track.album))
    }

    /// "Reset": forget this drive's steering and inferred signals, including today's
    /// exclusions, and keep playing. Long-term personalization is reset separately in Settings.
    public func resetSession() {
        state = SessionState()
        todayStore?.save([:])
        summary = ""
        applyRanking()
    }

    public func end() {
        guard isActive else { return }
        isActive = false
        speaker?.stop()
        player.flowProvider = previousFlowProvider
        player.onListenerSkip = previousSkipHandler
        player.onTrackCompleted = previousCompletionHandler
        player.onListenerReplay = previousReplayHandler
        pendingChoice = nil
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
        if let choice = pendingChoice {
            pendingChoice = nil
            if let picked = Self.pick(choice.options, from: transcript) {
                await apply(Self.replacing(choice.said, with: picked.name, in: choice.delta))
                return
            }
        }
        var delta = IntentParser.parse(transcript)
        delta.confidence *= confidence
        let resolved = resolver.resolve(delta)
        delta = resolved.delta
        if let (said, options) = resolved.ambiguous.first {
            pendingChoice = (delta, said, options)
            let names = options.map(\.name)
            let list = names.dropLast().joined(separator: ", ") + " or " + (names.last ?? "")
            reply(Self.pick(delta.speech, en: "\(list)?", mixed: "\(list)?", te: "\(list)?"),
                  style: delta.speech)
            voiceState = .done
            return
        }
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
        let effects = state.apply(delta, current: current, now: now(), timeZone: timeZone())
        todayStore?.save(state.todayExclusions(at: now()))
        var spoken = VoiceReply.text(for: delta, level: replyLevel)
        for effect in effects {
            switch effect {
            case let .startPlaying(source):
                if await !startPlaying(source, delta: delta) {
                    spoken = Self.pick(delta.speech, en: "Nothing available to play.",
                                       mixed: "Play చేయడానికి ఏమీ లేదు.", te: "ఏమీ దొరకలేదు.")
                }
            case .rerank:
                // Nothing of Halo's playing yet ("konchem energy pettu" as the first words):
                // start music for the session instead of re-ranking an empty queue.
                if player.currentTrack == nil {
                    if await !startPlaying(.vibe, delta: delta) {
                        spoken = Self.pick(delta.speech, en: "Nothing available to play.",
                                           mixed: "Play చేయడానికి ఏమీ లేదు.", te: "ఏమీ దొరకలేదు.")
                    }
                } else {
                    await rerank()
                }
            case let .transport(action):
                transport(action)
            case .skipCurrent:
                player.skipForListener()
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
        let ranked = SessionRanker.rank(pool, for: state, excluding: player.playedTrackIDs, today: now())
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
        let ranked = SessionRanker.rank(pool, for: state, excluding: player.playedTrackIDs, today: now())
        if !ranked.isEmpty { player.replaceUpcomingFlow(Array(ranked.prefix(25))) }
    }

    /// Asks the server for candidates; keeps the old pool if it can't be reached (offline).
    @discardableResult
    private func refresh(seed: String?, entity: EntityRef?) async -> Bool {
        let request = SessionCandidatesRequest(
            state: state, seedTrackID: seed, entity: entity,
            alsoExclude: Array(player.playedTrackIDs), limit: 40, now: now())
        guard let response = try? await api.sessionCandidates(request) else { return false }
        pool = response.candidates
        return !pool.isEmpty
    }

    /// Halo Flow during a drive: more songs that fit the session.
    private func flowSuggestions() async -> [FlowSuggestion] {
        if pool.count < 10 { await refresh(seed: player.currentTrack?.id, entity: nil) }
        return SessionRanker.rank(pool, for: state, excluding: player.playedTrackIDs, today: now())
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

    /// Which of the offered artists the answer names ("the first one", "Yuvan").
    static func pick(_ options: [EntityResolver.Entity], from answer: String) -> EntityResolver.Entity? {
        let said = words(answer)
        if said.contains("first") || said.contains("modatidi") { return options.first }
        if said.contains("second") || said.contains("rendodi") { return options.dropFirst().first }
        return options.first { option in
            let name = Set(option.name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted))
            let aliases = Set(option.aliases.map { $0.lowercased() })
            return !said.isDisjoint(with: name.subtracting(["", "s", "a", "r", "m", "j", "p", "k"]))
                || aliases.contains(answer.lowercased().trimmingCharacters(in: .whitespaces))
        }
    }

    static func replacing(_ said: String, with name: String, in delta: IntentDelta) -> IntentDelta {
        func swap(_ ref: EntityRef) -> EntityRef {
            if case let .mention(mention, _) = ref, mention == said { return .mention(name, kind: .artist) }
            return ref
        }
        var copy = delta
        copy.operations = delta.operations.map { operation in
            switch operation {
            case let .play(.entity(ref)): .play(.entity(swap(ref)))
            case let .weightArtist(ref, weight): .weightArtist(swap(ref), weight)
            case let .excludeArtist(ref, scope): .excludeArtist(swap(ref), scope)
            default: operation
            }
        }
        return copy
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
