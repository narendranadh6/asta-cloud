import Foundation

// Halo Drive's language-independent intent. Whatever the listener says (English, Telugu,
// romanized Telugu or a mix), the parser produces an `IntentDelta`: small changes to the
// current listening session. Nothing below this layer knows which language was spoken.

/// A music language Halo can play and filter on. ISO 639-1 codes ("te", "en").
public struct MusicLanguage: Hashable, Sendable, Codable, RawRepresentable {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public static let telugu = MusicLanguage(rawValue: "te")
    public static let english = MusicLanguage(rawValue: "en")
    public static let hindi = MusicLanguage(rawValue: "hi")
    public static let tamil = MusicLanguage(rawValue: "ta")
    public static let kannada = MusicLanguage(rawValue: "kn")
    public static let malayalam = MusicLanguage(rawValue: "ml")

    /// Languages with full support in this phase. Others are understood but declined politely.
    public static let supported: Set<MusicLanguage> = [.telugu, .english]

    public var name: String {
        switch rawValue {
        case "te": "Telugu"
        case "en": "English"
        case "hi": "Hindi"
        case "ta": "Tamil"
        case "kn": "Kannada"
        case "ml": "Malayalam"
        default: rawValue.uppercased()
        }
    }
}

/// How several music languages share a session.
public struct LanguagePreference: Hashable, Sendable, Codable {
    public enum Strategy: String, Sendable, Codable {
        /// Only the primary language.
        case only
        /// About four in five songs in the primary language.
        case mostly
        /// Roughly even.
        case mixed
        /// Strictly alternating.
        case alternating
    }

    public var primary: MusicLanguage
    public var secondary: MusicLanguage?
    public var strategy: Strategy

    public init(primary: MusicLanguage, secondary: MusicLanguage? = nil, strategy: Strategy = .only) {
        self.primary = primary
        self.secondary = strategy == .only ? nil : secondary
        self.strategy = secondary == nil ? .only : strategy
    }

    public static func only(_ language: MusicLanguage) -> LanguagePreference {
        LanguagePreference(primary: language)
    }

    public var languages: [MusicLanguage] { [primary] + (secondary.map { [$0] } ?? []) }
}

/// When the music should come from.
public enum Recency: Hashable, Sendable, Codable {
    case any
    /// Released within this many days ("new", "this week").
    case withinDays(Int)
    /// A decade, e.g. 1990 for "90s songs".
    case decade(Int)
    /// Older well-known songs ("old hits", "classics").
    case classics

    /// One step newer, for "newer".
    public var newer: Recency {
        switch self {
        case .any, .classics, .decade: .withinDays(365)
        case let .withinDays(days): .withinDays(max(days / 3, 7))
        }
    }

    /// One step older, for "older".
    public var older: Recency {
        switch self {
        case .any: .classics
        case let .withinDays(days) where days < 365: .withinDays(days * 3)
        case .withinDays: .any
        case let .decade(year): .decade(max(year - 10, 1950))
        case .classics: .classics
        }
    }
}

/// The musical dimensions a listener can steer, each 0…1.
public enum VibeDimension: String, Hashable, Sendable, Codable, CaseIterable {
    /// Calm (0) … intense (1).
    case energy
    /// Dark (0) … bright (1).
    case valence
    /// Slow (0) … fast (1).
    case tempo
    /// Familiar (0) … new to me (1).
    case discovery
}

/// Something the listener named or pointed at.
public enum EntityRef: Hashable, Sendable, Codable {
    /// "this singer", "this artist": the current track's artist.
    case currentArtist
    /// "this song".
    case currentTrack
    /// "this movie", "this album".
    case currentAlbum
    /// A name to resolve against the catalog ("DSP", "Pushpa"). Never guessed by a model.
    case mention(String, kind: Kind)

    public enum Kind: String, Hashable, Sendable, Codable {
        case artist, soundtrack, any
    }
}

/// How long a change lasts.
public enum Scope: String, Hashable, Sendable, Codable {
    /// Until the listening session ends (the default for every vibe change).
    case session
    /// Until midnight ("don't play this artist today").
    case today
    /// Saved to the long-term profile (likes, "never again", "remember this style").
    case profile
}

/// What to start playing.
public enum PlaySource: Hashable, Sendable, Codable {
    /// Music matching the session's vibe, language and recency.
    case vibe
    case entity(EntityRef)
    case similarToCurrent
    case surprise
}

public enum Transport: String, Hashable, Sendable, Codable {
    case pause, resume, next, previous, restart, removeNext, stop
}

public enum Rating: String, Hashable, Sendable, Codable {
    /// Positive signal for this session ("keep this one", "this is good").
    case keep
    case like
    case dislike
    /// Never recommend this song again.
    case neverAgain
    /// Save for later.
    case later
}

public enum Question: String, Hashable, Sendable, Codable {
    case whoIsSinging, whatMovie, whatAlbum, whenReleased, upNext
}

/// Where Halo Flow should go next.
public enum SeedMode: String, Hashable, Sendable, Codable {
    case similar
    /// "Go deeper": stay close to the seed, less popular picks.
    case deeper
    /// "Somewhere different": move away from the current direction.
    case elsewhere
}

/// One change to the listening session.
public enum SessionOperation: Hashable, Sendable, Codable {
    case play(PlaySource)
    case transport(Transport)
    /// Absolute target, e.g. "something calm" → energy 0.2.
    case setVibe(VibeDimension, Double)
    /// Relative step, e.g. "more energy" → energy +0.2.
    case adjustVibe(VibeDimension, Double)
    case setLanguage(LanguagePreference)
    /// "More Telugu": lean toward a language without dropping the other one.
    case favorLanguage(MusicLanguage)
    case setRecency(Recency)
    case newer
    case older
    /// Keep these dimensions as they are while something else changes ("same vibe but English").
    case preserve(Set<Preserved>)
    case lock
    case unlock
    case seedMode(SeedMode)
    /// Weight an artist up or down; negative "not too much X", positive "more from this artist".
    case weightArtist(EntityRef, Double)
    case excludeArtist(EntityRef, Scope)
    /// Prefer a different artist from the current one without excluding them.
    case diversifyArtists
    case rate(Rating)
    case ask(Question)
    case undo

    public enum Preserved: String, Hashable, Sendable, Codable {
        case vibe, language, artist, recency
    }
}

/// The parsed meaning of one utterance.
public struct IntentDelta: Hashable, Sendable, Codable {
    public var operations: [SessionOperation]
    /// Style of the listener's speech, used only to choose the reply's language.
    public var speech: SpeechStyle
    /// 0…1. Low confidence on a lasting change triggers a one-word confirmation.
    public var confidence: Double
    /// Languages that were understood but aren't supported yet ("Tamil").
    public var unsupportedLanguages: [MusicLanguage]

    public init(operations: [SessionOperation], speech: SpeechStyle = .english, confidence: Double = 1,
                unsupportedLanguages: [MusicLanguage] = []) {
        self.operations = operations
        self.speech = speech
        self.confidence = confidence
        self.unsupportedLanguages = unsupportedLanguages
    }

    public var isEmpty: Bool { operations.isEmpty }

    /// Changes that outlive the session should be confirmed when Halo isn't sure.
    public var changesProfile: Bool {
        operations.contains {
            switch $0 {
            case .rate(.neverAgain), .rate(.like), .excludeArtist(_, .profile): true
            default: false
            }
        }
    }

    public var needsConfirmation: Bool { changesProfile && confidence < 0.7 }
}

/// How the listener spoke, so replies can match.
public enum SpeechStyle: String, Hashable, Sendable, Codable {
    case english
    case telugu
    /// Telugu and English words together (also romanized Telugu).
    case mixed
}
