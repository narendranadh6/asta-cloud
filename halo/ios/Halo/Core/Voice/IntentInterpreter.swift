import Foundation

/// What Halo should do with one utterance, decided before anything changes.
public struct IntentDecision: Hashable, Sendable {
    public enum Outcome: String, Hashable, Sendable, CaseIterable {
        /// A clear music command: apply `delta`.
        case execute
        /// Ask first; `delta` holds what would happen (for "did you mean …?" confirmations).
        case clarify
        /// Outside music (or an unsupported language): change nothing, say so briefly.
        case unsupported
        /// Nothing to do (noise, "never mind", "don't skip").
        case noAction = "no_action"
    }

    public enum Reason: Hashable, Sendable {
        case understood
        case ambiguousEntity(said: String, options: [String])
        case incomplete(Slot)
        /// Understood, but the evidence is too weak for this kind of change.
        case lowConfidence
        case outsideMusic
        case unsupportedLanguage([MusicLanguage])
        case noise
        case neverMind
        case negatedControl
        case notUnderstood
        /// The speech recognizer produced nothing usable.
        case recognitionFailed
    }

    public enum Slot: String, Hashable, Sendable { case artist, language, song, album, film, something }

    public var outcome: Outcome
    public var reason: Reason
    /// Parsed and resolved; only applied for `.execute` (or after a confirmed `.clarify`).
    public var delta: IntentDelta
    /// The words as heard, kept for the reply and for the optional fallback; never stored.
    public var utterance: String
    /// Deterministic evidence score in 0…1 (not a probability).
    public var evidence: Double
    /// Estimated chance the interpretation is right, from the calibration table; nil when the
    /// outcome didn't need one.
    public var calibratedConfidence: Double?
    /// What the evidence score was computed from (only for decisions that reached the gate).
    public var features: EvidenceFeatures? = nil

    public static func recognitionFailed() -> IntentDecision {
        IntentDecision(outcome: .noAction, reason: .recognitionFailed, delta: IntentDelta(operations: []),
                       utterance: "", evidence: 0, calibratedConfidence: nil)
    }
}

/// How risky a change is, which sets how sure Halo must be before acting without asking.
public enum ActionRisk: Int, Comparable, Sendable, Hashable {
    /// Transport, questions: easy to see and undo.
    case low
    /// Session changes (vibe, language, artists for this drive).
    case session
    /// Lasting changes (likes, "never again", profile exclusions).
    case lasting

    public static func < (a: ActionRisk, b: ActionRisk) -> Bool { a.rawValue < b.rawValue }

    static func of(_ delta: IntentDelta) -> ActionRisk {
        if delta.changesProfile { return .lasting }
        let lowOnly = delta.operations.allSatisfy {
            switch $0 {
            case .transport, .ask, .undo, .rate(.keep): true
            default: false
            }
        }
        return lowOnly ? .low : .session
    }

    /// Minimum calibrated confidence to act without asking.
    var required: Double { required(GateThresholds.current) }

    func required(_ thresholds: GateThresholds) -> Double {
        switch self {
        case .low: thresholds.low
        case .session: thresholds.session
        case .lasting: thresholds.lasting
        }
    }
}

/// Confidence needed per risk before acting without asking.
public struct GateThresholds: Hashable, Sendable {
    public var low: Double
    public var session: Double
    public var lasting: Double

    /// Session 0.5 (was 0.6) chosen by cross-validation on development data, 2026-11-06; lasting
    /// changes keep the stricter 0.85.
    public static let current = GateThresholds(low: 0.5, session: 0.5, lasting: 0.85)
}

/// Turns an utterance into an `IntentDecision`: parse (deterministic), resolve entities, then
/// decide whether acting is safe. Nothing here changes state; `SessionState.apply` does that,
/// only for executed (or confirmed) decisions.
public enum IntentInterpreter {
    public static func interpret(_ text: String, resolver: EntityResolver = EntityResolver(),
                                 recognizerConfidence: Double = 1) -> IntentDecision {
        let u = Utterance(text)
        func decide(_ outcome: IntentDecision.Outcome, _ reason: IntentDecision.Reason,
                    _ delta: IntentDelta = IntentDelta(operations: [], speech: u.style)) -> IntentDecision {
            IntentDecision(outcome: outcome, reason: reason, delta: delta, utterance: text, evidence: 0,
                           calibratedConfidence: nil)
        }
        let words = u.text.split(separator: " ").map(String.init)
        if words.isEmpty || words.allSatisfy({ VoiceLexicon.noise.contains($0) }) {
            return decide(.noAction, .noise)
        }
        let meaningful = words.filter { !VoiceLexicon.noise.contains($0) && !["please", "bro", "plz"].contains($0) }

        if Set(meaningful).isSubset(of: ["no", "vaddu", "వద్దు", "nope", "cancel"]) {
            return decide(.noAction, .neverMind)
        }
        if let slot = incompleteSlot(u) {
            return decide(.clarify, .incomplete(slot))
        }

        if u.negatesAControl {
            return decide(.noAction, .negatedControl)
        }
        var delta = IntentParser.parse(text)
        let controlOnly = !delta.isEmpty && delta.operations.allSatisfy {
            if case .transport = $0 { true } else { false }
        }
        if (controlOnly || delta.isEmpty), u.has(VoiceLexicon.controlNegation) || u.isNegated,
           u.has(VoiceLexicon.controlWords) {
            return decide(.noAction, .negatedControl)
        }
        if delta.isEmpty, u.has(VoiceLexicon.neverMind) {
            return decide(.noAction, .neverMind)
        }
        // Known names anywhere in the sentence ("I feel like some Keeravani", "Raja music"),
        // when nothing else named one.
        if !delta.operations.contains(where: \.namesSomething), let name = knownName(in: u, resolver: resolver),
           u.isNegated || u.has(IntentParser.playVerbs) || u.has(VoiceLexicon.requestCues) || u.text == name {
            let ref = EntityRef.mention(name, kind: .any)
            let lasting = u.isLasting(refusing: u.isNegated)
            let scope: Scope = u.has(VoiceLexicon.today) ? .today : lasting ? .profile : .session
            delta.operations.insert(u.isNegated ? .excludeArtist(ref, scope) : .play(.entity(ref)), at: 0)
            delta.operations.removeAll { $0 == .play(.vibe) || $0 == .transport(.resume) }
        }
        let musicOps = delta.operations.filter {
            if case .transport = $0 { false } else { true }
        }
        if u.has(VoiceLexicon.offDomain), musicOps.isEmpty {
            return decide(.unsupported, .outsideMusic)
        }
        if delta.isEmpty {
            if !delta.unsupportedLanguages.isEmpty {
                return decide(.unsupported, .unsupportedLanguage(delta.unsupportedLanguages), delta)
            }
            return decide(.noAction, .notUnderstood)
        }

        let resolved = resolve(delta, resolver: resolver, utterance: u)
        delta = resolved.delta
        if let (said, options) = resolved.ambiguous.first {
            return decide(.clarify, .ambiguousEntity(said: said, options: options), delta)
        }

        // A negated sentence that came out purely positive (more of an artist, play it, resume,
        // like, sad songs) is the opposite of what was asked: ask instead of acting.
        if u.isNegated, !delta.operations.contains(where: \.isNegative),
           delta.operations.contains(where: \.isPositiveTarget) {
            return IntentDecision(outcome: .clarify, reason: .lowConfidence, delta: delta, utterance: text,
                                  evidence: 0, calibratedConfidence: nil)
        }

        let dimensions = delta.operations.compactMap(\.dimension)
        let features = EvidenceFeatures(
            unknownShare: u.unknownShare(knownNames: resolved.knownWords),
            unresolvedNames: resolved.unresolved,
            conflictingDimensions: Set(dimensions).count < dimensions.count,
            operationCount: delta.operations.count,
            recognizerConfidence: recognizerConfidence,
            risk: ActionRisk.of(delta))
        let undecided = IntentDecision(outcome: .execute, reason: .understood, delta: delta, utterance: text,
                                       evidence: 0, calibratedConfidence: nil, features: features)
        return gate(undecided)
    }

    /// Scores the evidence, maps it to confidence, and asks instead of acting when the
    /// confidence is below what the change's risk requires. Decisions without features pass.
    public static func gate(_ decision: IntentDecision, weights: EvidenceWeights = .current,
                            table: [Double] = IntentCalibration.table,
                            thresholds: GateThresholds = .current) -> IntentDecision {
        guard let features = decision.features else { return decision }
        var gated = decision
        gated.evidence = weights.score(features)
        let calibrated = IntentCalibration.confidence(forEvidence: gated.evidence, table: table)
        gated.calibratedConfidence = calibrated
        gated.delta.confidence = calibrated
        let ok = calibrated >= features.risk.required(thresholds)
        gated.outcome = ok ? .execute : .clarify
        gated.reason = ok ? .understood : .lowConfidence
        return gated
    }

    /// The longest run of one to three words that names a known or shared artist or film.
    static func knownName(in u: Utterance, resolver: EntityResolver) -> String? {
        let words = u.text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }
        for length in stride(from: min(3, words.count), through: 1, by: -1) {
            for start in 0...(words.count - length) {
                let candidate = words[start..<(start + length)].joined(separator: " ")
                guard !VoiceLexicon.commonWords.contains(candidate), !VoiceLexicon.knownWords.contains(candidate)
                else { continue }
                switch resolver.resolve(candidate) {
                case .known, .ambiguous: return candidate
                case .unknown: continue
                }
            }
        }
        return nil
    }

    /// "play songs by", "set the language to", "don't play": a request with its object missing.
    static func incompleteSlot(_ u: Utterance) -> IntentDecision.Slot? {
        // Hesitations don't complete a request: "play songs by… umm", "adi… ante… pettu".
        let all = u.text.split(separator: " ").map(String.init)
        let hesitated = all.contains { VoiceLexicon.hesitations.contains($0) }
        var words = all
        while let last = words.last, VoiceLexicon.noise.contains(last) || VoiceLexicon.hesitations.contains(last) {
            words.removeLast()
        }
        let text = words.joined(separator: " ")
        let content = all.filter { !VoiceLexicon.hesitations.contains($0) && !VoiceLexicon.noise.contains($0) }
        if hesitated, !content.isEmpty,
           content.allSatisfy({ IntentParser.playVerbs.contains($0) || ["cheyyi", "chey", "please", "plz"].contains($0) }) {
            return .something
        }
        let namesLanguage = u.has(["language", "bhasha", "భాష"])
        let changes = u.has(["marchu", "maarchu", "change", "switch", "మార్చు", "మార్చండి"])
        if (u.has(VoiceLexicon.languageChange) || namesLanguage && changes) && u.languages.isEmpty { return .language }
        if u.has(VoiceLexicon.forgotName) {
            return u.has(["movie", "film", "cinema", "సినిమా"]) ? .film : .something
        }
        if text.hasSuffix(" some"), u.has(IntentParser.playVerbs) || u.has(VoiceLexicon.requestCues) { return .something }
        if words.count == 1, let only = words.first, !VoiceLexicon.controlNegation.contains(only),
           Utterance.isNegativeImperative(only) || ["పెట్టకు", "వినిపించకు", "పెట్టకండి"].contains(only) {
            return .artist
        }
        let endings: [(String, IntentDecision.Slot)] = [
            (" by", .artist), (" songs of", .artist), (" songs from", .film), ("language to", .language),
            ("dont put on", .artist), (" put on", .something), ("from the movie", .film),
            ("switch to", .language), ("play the song", .song), ("play song", .song), ("play the album", .album),
            ("play album", .album), ("from the movie", .film), ("from the film", .film),
        ]
        for (ending, slot) in endings where text.hasSuffix(ending) { return slot }
        if ["dont play", "do not play", "no more", "dont play any", "dont put on", "play some", "put on some"].contains(text) {
            return text.hasPrefix("play") || text.hasPrefix("put") ? .something : .artist
        }
        return nil
    }

    /// Resolves artist and film names; a name known only by its first words ("thaman lately")
    /// keeps the known part. Returns ambiguous names to ask about and names left unresolved.
    static func resolve(_ delta: IntentDelta, resolver: EntityResolver, utterance: Utterance = Utterance(""))
        -> (delta: IntentDelta, ambiguous: [(String, [String])], unresolved: Int, knownWords: Set<String>) {
        var ambiguous: [(String, [String])] = []
        var unresolved = 0
        var knownWords = Set<String>()
        func canonical(_ ref: EntityRef) -> EntityRef {
            guard case let .mention(name, kind) = ref, [.artist, .any, .soundtrack].contains(kind) else { return ref }
            let words = name.split(separator: " ").map(String.init)
            for length in stride(from: words.count, through: 1, by: -1) {
                let candidate = words.prefix(length).joined(separator: " ")
                switch resolver.resolve(candidate) {
                case let .known(entity):
                    knownWords.formUnion(words.prefix(length))
                    return .mention(entity.name, kind: entity.kind == .film ? .soundtrack : .artist)
                case let .ambiguous(options) where length == words.count:
                    ambiguous.append((name, options.map(\.name)))
                    return ref
                default:
                    continue
                }
            }
            // A known name in the sentence that contains the captured words: the capture lost part
            // of it ("Gopi Sundar vi …" captured "sundar").
            if let full = knownName(in: utterance, resolver: resolver),
               Set(full.split(separator: " ").map(String.init)).isSuperset(of: words),
               case let .known(entity) = resolver.resolve(full) {
                knownWords.formUnion(full.split(separator: " ").map(String.init))
                return .mention(entity.name, kind: entity.kind == .film ? .soundtrack : .artist)
            }
            // A known name at the end of the capture ("ivala thaman", "ఈరోజు దేవి శ్రీ ప్రసాద్").
            for drop in 1..<max(words.count, 1) {
                if case let .known(entity) = resolver.resolve(words.dropFirst(drop).joined(separator: " ")) {
                    knownWords.formUnion(words.dropFirst(drop))
                    return .mention(entity.name, kind: entity.kind == .film ? .soundtrack : .artist)
                }
            }
            unresolved += 1
            return ref
        }
        var resolved = delta
        resolved.operations = delta.operations.map { operation in
            switch operation {
            case let .play(.entity(ref)): .play(.entity(canonical(ref)))
            case let .weightArtist(ref, weight): .weightArtist(canonical(ref), weight)
            case let .excludeArtist(ref, scope): .excludeArtist(canonical(ref), scope)
            default: operation
            }
        }
        return (resolved, ambiguous, unresolved, knownWords)
    }
}

/// The deterministic evidence behind a parse. Higher means the words left little room for
/// doubt. It is a score, not a probability: `IntentCalibration` maps it to one.
public struct EvidenceFeatures: Hashable, Sendable {
    public var unknownShare: Double
    public var unresolvedNames: Int
    public var conflictingDimensions: Bool
    public var operationCount: Int
    public var recognizerConfidence: Double
    public var risk: ActionRisk
}

/// Penalties that turn evidence features into a 0…1 score. `current` is chosen by
/// cross-validation on development data (`EvidenceTuningTests`, run with HALO_TUNE=1).
public struct EvidenceWeights: Hashable, Sendable {
    public var unknownShare: Double
    public var unresolvedName: Double
    public var conflict: Double
    public var manyOperations: Double
    public var recognizer: Double

    /// unknownShare 0.45 (was 0.6) chosen by 5-fold cross-validation on 1,329 development
    /// commands (corpus + retired holdouts v1–v4): CV exact accuracy 88.5% → 89.2%, no fold worse.
    /// Conflict and many-operations penalties made no difference and stay as they were. The
    /// recognizer penalty can't be tuned on text (confidence is always 1 there); it is 0.8 so a
    /// barely-heard command (recognizer confidence 0.1) always asks.
    public static let current = EvidenceWeights(unknownShare: 0.45, unresolvedName: 0.12, conflict: 0.2,
                                                manyOperations: 0.1, recognizer: 0.8)

    public func score(_ f: EvidenceFeatures) -> Double {
        var score = 1.0
        score -= unknownShare * f.unknownShare
        score -= unresolvedName * Double(f.unresolvedNames)
        if f.conflictingDimensions { score -= conflict }  // e.g. energy up and down
        if f.operationCount > 4 { score -= manyOperations }
        score -= recognizer * (1 - min(max(f.recognizerConfidence, 0), 1))
        return min(max(score, 0), 1)
    }
}

extension SessionOperation {
    /// Rules something out or reduces it.
    var isNegative: Bool {
        switch self {
        case .excludeArtist, .excludeTrack, .avoid, .rate(.dislike), .rate(.neverAgain), .diversifyArtists: true
        case let .weightArtist(_, weight): weight < 0
        case .setLanguage: true  // a refused language becomes "only the other one"
        default: false
        }
    }

    /// Refers to a named artist, film, album, song or genre.
    var namesSomething: Bool {
        switch self {
        case .play(.entity(.mention)), .weightArtist(.mention, _), .excludeArtist(.mention, _): true
        default: false
        }
    }

    /// Plays or favours something specific: the opposite of refusing it.
    var isPositiveTarget: Bool {
        switch self {
        case .play(.entity), .transport(.resume), .rate(.like), .setVibe(.valence, 0.25): true
        case let .weightArtist(_, weight): weight > 0
        default: false
        }
    }
}
