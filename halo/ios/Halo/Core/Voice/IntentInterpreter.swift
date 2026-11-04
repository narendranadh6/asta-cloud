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

    public static func recognitionFailed() -> IntentDecision {
        IntentDecision(outcome: .noAction, reason: .recognitionFailed, delta: IntentDelta(operations: []),
                       utterance: "", evidence: 0, calibratedConfidence: nil)
    }
}

/// How risky a change is, which sets how sure Halo must be before acting without asking.
public enum ActionRisk: Int, Comparable, Sendable {
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
    var required: Double {
        switch self {
        case .low: 0.5
        case .session: 0.6
        case .lasting: 0.85
        }
    }
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

        let resolved = resolve(delta, resolver: resolver)
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

        let evidence = IntentEvidence.score(u, delta: delta, unresolvedNames: resolved.unresolved,
                                            recognizerConfidence: recognizerConfidence)
        let calibrated = IntentCalibration.confidence(forEvidence: evidence)
        delta.confidence = calibrated
        let risk = ActionRisk.of(delta)
        var decision = IntentDecision(outcome: .execute, reason: .understood, delta: delta, utterance: text,
                                      evidence: evidence, calibratedConfidence: calibrated)
        if calibrated < risk.required {
            decision.outcome = .clarify
            decision.reason = .lowConfidence
        }
        return decision
    }

    /// "play songs by", "set the language to", "don't play": a request with its object missing.
    static func incompleteSlot(_ u: Utterance) -> IntentDecision.Slot? {
        let text = u.text
        let endings: [(String, IntentDecision.Slot)] = [
            (" by", .artist), (" songs of", .artist), (" songs from", .film), ("language to", .language),
            ("switch to", .language), ("play the song", .song), ("play song", .song), ("play the album", .album),
            ("play album", .album), ("from the movie", .film), ("from the film", .film),
        ]
        for (ending, slot) in endings where text.hasSuffix(ending) { return slot }
        if ["dont play", "do not play", "no more", "dont play any", "play some", "put on some"].contains(text) {
            return text.hasPrefix("play") || text.hasPrefix("put") ? .something : .artist
        }
        return nil
    }

    /// Resolves artist and film names; a name known only by its first words ("thaman lately")
    /// keeps the known part. Returns ambiguous names to ask about and names left unresolved.
    static func resolve(_ delta: IntentDelta, resolver: EntityResolver)
        -> (delta: IntentDelta, ambiguous: [(String, [String])], unresolved: Int) {
        var ambiguous: [(String, [String])] = []
        var unresolved = 0
        func canonical(_ ref: EntityRef) -> EntityRef {
            guard case let .mention(name, kind) = ref, [.artist, .any, .soundtrack].contains(kind) else { return ref }
            let words = name.split(separator: " ").map(String.init)
            for length in stride(from: words.count, through: 1, by: -1) {
                let candidate = words.prefix(length).joined(separator: " ")
                switch resolver.resolve(candidate) {
                case let .known(entity):
                    return .mention(entity.name, kind: entity.kind == .film ? .soundtrack : .artist)
                case let .ambiguous(options) where length == words.count:
                    ambiguous.append((name, options.map(\.name)))
                    return ref
                default:
                    continue
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
        return (resolved, ambiguous, unresolved)
    }
}

/// The deterministic evidence behind a parse. Higher means the words left little room for
/// doubt. It is a score, not a probability: `IntentCalibration` maps it to one.
public enum IntentEvidence {
    static func score(_ u: Utterance, delta: IntentDelta, unresolvedNames: Int,
                      recognizerConfidence: Double) -> Double {
        var score = 1.0
        score -= 0.6 * u.unknownShare
        score -= 0.12 * Double(unresolvedNames)
        let dimensions = delta.operations.compactMap(\.dimension)
        if Set(dimensions).count < dimensions.count { score -= 0.2 }  // e.g. energy up and down
        if delta.operations.count > 4 { score -= 0.1 }
        score -= 0.5 * (1 - min(max(recognizerConfidence, 0), 1))
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

    /// Plays or favours something specific: the opposite of refusing it.
    var isPositiveTarget: Bool {
        switch self {
        case .play(.entity), .transport(.resume), .rate(.like), .setVibe(.valence, 0.25): true
        case let .weightArtist(_, weight): weight > 0
        default: false
        }
    }
}
