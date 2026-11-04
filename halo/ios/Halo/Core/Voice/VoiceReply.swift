import Foundation

/// How much Halo talks back.
public enum ReplyLevel: String, Sendable, Codable {
    /// Never speak (sounds only).
    case silent
    /// A few words, only when the change isn't obvious from the music. Drive default.
    case short
}

/// Halo's spoken replies: a fixed bank of short phrases, never generated text, in the style
/// the listener used (English, Telugu or mixed).
public enum VoiceReply {
    /// What to say after `delta`, or nil to stay quiet (the music itself is the answer).
    public static func text(for delta: IntentDelta, level: ReplyLevel = .short) -> String? {
        guard level != .silent else { return nil }
        let style = delta.speech
        if delta.isEmpty {
            if let language = delta.unsupportedLanguages.first {
                return pick(style,
                            en: "\(language.name) is coming soon.",
                            mixed: "\(language.name) ఇంకా రాలేదు.",
                            te: "\(language.name) ఇంకా రాలేదు.")
            }
            return pick(style, en: "Didn't catch that.", mixed: "అర్థం కాలేదు.", te: "అర్థం కాలేదు.")
        }
        if delta.needsConfirmation {
            return pick(style, en: "Never play this again?", mixed: "ఇక పెట్టొద్దా?", te: "ఇక పెట్టొద్దా?")
        }
        // The most informative operation decides the reply; "play" alone is the fallback.
        for operation in delta.operations where operation != .play(.vibe) {
            if let reply = reply(for: operation, style: style) { return reply }
        }
        return delta.operations.contains(.play(.vibe))
            ? pick(style, en: "Got it.", mixed: "సరే.", te: "సరే.") : nil
    }

    /// "Did you mean …?" for a change Halo wasn't sure about; answered with yes or no.
    public static func confirmation(for delta: IntentDelta) -> String {
        let style = delta.speech
        if delta.changesProfile {
            return pick(style, en: "Never play this again?", mixed: "ఇక పెట్టొద్దా?", te: "ఇక పెట్టొద్దా?")
        }
        let summary = delta.operations.lazy.compactMap { reply(for: $0, style: style) }.first
        let text = (summary ?? pick(style, en: "Do that", mixed: "అలా చేయనా", te: "అలా చేయనా"))
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))
        return text + "?"
    }

    /// The missing part of an incomplete request.
    public static func question(for slot: IntentDecision.Slot, style: SpeechStyle) -> String {
        switch slot {
        case .artist: pick(style, en: "Which artist?", mixed: "ఏ artist?", te: "ఏ గాయకుడు?")
        case .language: pick(style, en: "Which language?", mixed: "ఏ language?", te: "ఏ భాష?")
        case .song: pick(style, en: "Which song?", mixed: "ఏ song?", te: "ఏ పాట?")
        case .album: pick(style, en: "Which album?", mixed: "ఏ album?", te: "ఏ ఆల్బమ్?")
        case .film: pick(style, en: "Which movie?", mixed: "ఏ movie?", te: "ఏ సినిమా?")
        case .something: pick(style, en: "What should I play?", mixed: "ఏం పెట్టాలి?", te: "ఏం పెట్టాలి?")
        }
    }

    private static func reply(for operation: SessionOperation, style: SpeechStyle) -> String? {
        switch operation {
        case .transport, .rate(.keep), .excludeArtist(.currentArtist, _), .rate(.dislike), .ask:
            return nil  // obvious from the music, or answered separately
        case let .setLanguage(preference):
            let name = preference.primary.name
            return preference.strategy == .only
                ? pick(style, en: "Switching to \(name).", mixed: "\(name) songs పెడుతున్నా.",
                       te: "\(teluguName(preference.primary)) పాటలు.")
                : pick(style, en: "Mostly \(name).", mixed: "ఎక్కువ \(name).", te: "ఎక్కువ \(name).")
        case let .favorLanguage(language):
            return pick(style, en: "More \(language.name).", mixed: "ఇంకా \(language.name).",
                        te: "ఇంకా \(teluguName(language)).")
        case let .setVibe(.energy, value), let .adjustVibe(.energy, value):
            let up = operation.isSet ? value >= 0.5 : value > 0
            return up
                ? pick(style, en: "More energy.", mixed: "Okay, energy పెంచుతున్నా.", te: "జోష్ పెంచుతున్నా.")
                : pick(style, en: "Calmer.", mixed: "కొంచెం calm గా.", te: "ప్రశాంతంగా.")
        case .newer, .setRecency(.withinDays):
            return pick(style, en: "Going newer.", mixed: "కొత్తవి పెడుతున్నా.", te: "కొత్తవి.")
        case .older, .setRecency(.classics), .setRecency(.decade):
            return pick(style, en: "Going older.", mixed: "పాతవి పెడుతున్నా.", te: "పాతవి.")
        case .play(.similarToCurrent):
            return pick(style, en: "Playing similar songs.", mixed: "ఇలాంటివే.", te: "ఇలాంటివే.")
        case .play(.surprise):
            return pick(style, en: "Surprise coming up.", mixed: "Surprise!", te: "Surprise!")
        case .adjustVibe(.discovery, _):
            return pick(style, en: "More discovery.", mixed: "కొత్తవి try చేద్దాం.", te: "కొత్తవి try చేద్దాం.")
        case .lock:
            return pick(style, en: "Keeping this vibe.", mixed: "ఇదే vibe.", te: "ఇదే vibe.")
        case .seedMode(.elsewhere):
            return pick(style, en: "Somewhere new.", mixed: "వేరే vibe.", te: "వేరే vibe.")
        case .seedMode(.deeper):
            return pick(style, en: "Going deeper.", mixed: "ఇంకా లోతుగా.", te: "ఇంకా లోతుగా.")
        case .rate(.like):
            return pick(style, en: "Added.", mixed: "Added.", te: "సేవ్ చేశా.")
        case .rate(.later):
            return pick(style, en: "Saved for later.", mixed: "Later కి save చేశా.", te: "తర్వాత కోసం.")
        case .rate(.neverAgain):
            return pick(style, en: "Won't play it again.", mixed: "ఇక పెట్టను.", te: "ఇక పెట్టను.")
        case .excludeTrack:
            return nil  // obvious: the song changes
        case .avoid(.sad):
            return pick(style, en: "No sad songs.", mixed: "Sad songs వద్దు, okay.",
                        te: "బాధ పాటలు వద్దు.")
        case .undo:
            return pick(style, en: "Undone.", mixed: "Undo చేశా.", te: "వెనక్కి.")
        case .play, .setVibe, .adjustVibe, .weightArtist, .excludeArtist, .diversifyArtists,
             .setRecency(.any):
            return pick(style, en: "Got it.", mixed: "సరే.", te: "సరే.")
        case .preserve, .unlock, .seedMode:
            return nil
        }
    }

    private static func pick(_ style: SpeechStyle, en: String, mixed: String, te: String) -> String {
        switch style {
        case .english: en
        case .mixed: mixed
        case .telugu: te
        }
    }

    private static func teluguName(_ language: MusicLanguage) -> String {
        switch language {
        case .telugu: "తెలుగు"
        case .english: "ఇంగ్లీష్"
        default: language.name
        }
    }
}

extension SessionOperation {
    var isSet: Bool {
        if case .setVibe = self { return true }
        return false
    }
}
