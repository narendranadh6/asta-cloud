import Foundation

/// Turns what the listener said (English, Telugu, romanized Telugu or a mix) into an
/// `IntentDelta`. Deterministic and on-device: it never invents songs, and names it doesn't
/// know become `EntityRef.mention`s for the catalog's entity resolver, never guesses.
public enum IntentParser {
    public static func parse(_ text: String) -> IntentDelta {
        let u = Utterance(text)
        guard !u.text.isEmpty else { return IntentDelta(operations: [], speech: .english, confidence: 0) }
        var ops: [SessionOperation] = []
        var unsupported: [MusicLanguage] = []

        // 1. Commands that stand alone.
        if let single = standalone(u) {
            return IntentDelta(operations: single, speech: u.style, confidence: 0.9)
        }

        // 2. The current artist and album.
        let refusing = u.has(VoiceLexicon.refuse) || u.word("not") || u.word("no")
            || u.has(["dont play", "no more", "stop playing", "skip this"])
        if u.has(VoiceLexicon.thisArtist) {
            if u.has(["explore"]) {
                ops.append(.play(.entity(.currentArtist)))
            } else if u.has(VoiceLexicon.less) {
                ops.append(.weightArtist(.currentArtist, -0.6))
            } else if refusing {
                ops.append(.excludeArtist(.currentArtist, u.has(VoiceLexicon.today) ? .today : .session))
            } else {
                ops.append(.weightArtist(.currentArtist, 0.6))
            }
        }
        if u.has(VoiceLexicon.differentArtist) { ops.append(.diversifyArtists) }
        if u.has(["this movie", "this album", "this soundtrack", "ee movie", "ఈ movie", "ఈ సినిమా"]) {
            ops.append(.play(.entity(.currentAlbum)))
        }

        // 3. Languages.
        let mentioned = u.languages
        unsupported = mentioned.filter { !MusicLanguage.supported.contains($0) }
        let playable = mentioned.filter { MusicLanguage.supported.contains($0) }
        if playable.count >= 2 {
            let strategy: LanguagePreference.Strategy =
                u.has(VoiceLexicon.alternateWords) ? .alternating
                : u.has(VoiceLexicon.mostlyWords) || u.has(VoiceLexicon.someWords) ? .mostly
                : .mixed
            ops.append(.setLanguage(LanguagePreference(primary: playable[0], secondary: playable[1],
                                                       strategy: strategy)))
        } else if let language = playable.first {
            if u.has(VoiceLexicon.more) && !u.has(VoiceLexicon.onlyWords) {
                ops.append(.favorLanguage(language))
            } else {
                ops.append(.setLanguage(.only(language)))
            }
        }

        // 4. Vibe.
        let relative = u.has(VoiceLexicon.more) || u.has(VoiceLexicon.less) || u.has(VoiceLexicon.slightly)
        let step = u.has(VoiceLexicon.slightly) ? 0.12 : 0.2
        let sameEnergy = u.has(["same energy"])
        let lowering = u.has(VoiceLexicon.less) && u.has(["energy", "ఎనర్జీ"])
        if u.has(VoiceLexicon.energyDown) || lowering {
            let comparative = u.has(["calmer", "slower", "softer", "quieter"])
            ops.append(relative || comparative ? .adjustVibe(.energy, -step) : .setVibe(.energy, 0.2))
        } else if u.has(VoiceLexicon.energyUp) && !sameEnergy {
            let comparative = u.has(["faster", "louder"])
            ops.append(relative || comparative ? .adjustVibe(.energy, step) : .setVibe(.energy, 0.85))
        }
        let negated = u.has(VoiceLexicon.refuse) || u.has(["dont", "no", "not", "without"])
        if u.has(VoiceLexicon.sad) {
            ops.append(.setVibe(.valence, negated ? 0.65 : 0.25))
        } else if u.has(VoiceLexicon.happy) {
            ops.append(u.has(["happier"]) || relative ? .adjustVibe(.valence, step) : .setVibe(.valence, 0.8))
        }
        if u.has(VoiceLexicon.romantic) {
            ops.append(.setVibe(.valence, 0.65))
            if !ops.contains(where: { $0.dimension == .energy }) { ops.append(.setVibe(.energy, 0.4)) }
        }

        // 5. Time.
        let wantsDiscovery = u.has(VoiceLexicon.discovery) && !u.has(VoiceLexicon.thisArtist)
        if let decade = u.decade {
            ops.append(.setRecency(.decade(decade)))
        } else if u.has(VoiceLexicon.newerWords) {
            ops.append(.newer)
        } else if u.has(VoiceLexicon.olderWords) {
            ops.append(.older)
        } else if u.has(VoiceLexicon.oldWords) {
            ops.append(.setRecency(.classics))
        } else if u.has(VoiceLexicon.newWords) && !wantsDiscovery {
            ops.append(.setRecency(.withinDays(u.recencyDays)))
        }

        // 6. Discovery and direction.
        if u.has(VoiceLexicon.surprise) {
            ops.append(.play(.surprise))
            ops.append(.adjustVibe(.discovery, 0.3))
        } else if wantsDiscovery {
            ops.append(.adjustVibe(.discovery, 0.3))
        } else if u.has(VoiceLexicon.familiar) {
            ops.append(.setVibe(.discovery, 0.15))
        }
        if u.has(VoiceLexicon.deeper) {
            ops.append(.seedMode(.deeper))
        } else if u.has(VoiceLexicon.elsewhere) && !u.has(VoiceLexicon.differentArtist) {
            ops.append(.seedMode(.elsewhere))
            ops.append(.adjustVibe(.discovery, 0.3))
        }
        if u.has(VoiceLexicon.similar) && !u.has(VoiceLexicon.like.filter { $0.hasPrefix("i ") }) {
            ops.append(.play(.similarToCurrent))
        }

        // 7. Named artists and soundtracks (resolved later against the catalog).
        if let name = u.capture(downweightPatterns) {
            ops.append(.weightArtist(.mention(name, kind: .artist), -0.6))
        } else if let name = u.capture(excludePatterns) {
            ops.append(.excludeArtist(.mention(name, kind: .artist),
                                      u.has(VoiceLexicon.today) ? .today : .session))
        } else if !ops.contains(where: \.isPlay), let match = u.captureWithPattern(playPatterns) {
            let soundtrack = u.has(["movie", "film", "cinema", "సినిమా", "soundtrack"])
                || match.pattern.contains("from")
            ops.append(.play(.entity(.mention(match.name, kind: soundtrack ? .soundtrack : .any))))
        }

        // 8. "Keep this vibe" versus "same vibe but …".
        let changes = ops.contains { $0.changesDirection }
        if u.has(VoiceLexicon.lockVibe) && !changes {
            ops.append(.lock)
        } else if u.has(VoiceLexicon.same) && changes {
            ops.insert(.preserve([.vibe]), at: 0)
        }

        // 9. A request ("play …", "… songs పెట్టు") starts new music; a bare change re-ranks.
        let asksToPlay = u.has(playVerbs) || u.has(["songs", "music", "playlist", "పాటలు", "paatalu"])
        let starts = ops.contains { $0.startsMusic }
        if asksToPlay && starts && !ops.contains(where: \.isPlay) {
            ops.insert(.play(.vibe), at: 0)
        }

        // 10. Nothing else: transport words.
        if ops.isEmpty {
            if let transport = transport(u) { ops = [.transport(transport)] }
        }

        let confidence: Double = ops.isEmpty ? 0 : (u.unknownShare > 0.5 ? 0.6 : 0.9)
        return IntentDelta(operations: ops, speech: u.style, confidence: confidence,
                           unsupportedLanguages: unsupported)
    }

    // MARK: Standalone commands

    private static func standalone(_ u: Utterance) -> [SessionOperation]? {
        if u.has(VoiceLexicon.undo) { return [.undo] }
        if u.has(VoiceLexicon.upNext) { return [.ask(.upNext)] }
        if u.has(VoiceLexicon.whoIsSinging) { return [.ask(.whoIsSinging)] }
        if u.has(VoiceLexicon.whatMovie) { return [.ask(.whatMovie)] }
        if u.has(VoiceLexicon.whatAlbum) { return [.ask(.whatAlbum)] }
        if u.has(VoiceLexicon.whenReleased) { return [.ask(.whenReleased)] }
        if u.has(VoiceLexicon.neverAgain) { return [.rate(.neverAgain)] }
        if u.has(VoiceLexicon.later) { return [.rate(.later)] }
        if u.has(VoiceLexicon.removeNext) { return [.transport(.removeNext)] }
        if u.has(VoiceLexicon.dislike) { return [.rate(.dislike)] }
        if u.has(VoiceLexicon.like) && !u.has(["more like", "songs like", "something like"]) {
            return [.rate(.like)]
        }
        if u.has(VoiceLexicon.keep) && !u.has(VoiceLexicon.lockVibe) && !u.has(["vibe"]) {
            return [.rate(.keep)]
        }
        return nil
    }

    private static func transport(_ u: Utterance) -> Transport? {
        if u.has(VoiceLexicon.pause) { return .pause }
        if u.has(VoiceLexicon.restart) { return .restart }
        if u.has(VoiceLexicon.next) { return .next }
        if u.has(VoiceLexicon.previous) { return .previous }
        if u.has(VoiceLexicon.resume) || u.has(playVerbs) { return .resume }
        return nil
    }

    // MARK: Patterns for names

    static let playVerbs = ["play", "put on", "give me", "start", "pettu", "పెట్టు", "cheyyi",
                            "చెయ్యి", "vinipinchu", "వినిపించు", "kavali", "కావాలి"]

    /// "too much Anirudh", "less of DSP", "konchem takkuva Thaman".
    static let downweightPatterns = [
        "too much ([^,]+?)(?: songs| music| please|$)",
        "less of ([^,]+?)(?: songs| music|$)",
        "less ([^,]+?)(?: songs| music|$)",
    ]

    /// "don't play Anirudh", "no DSP today", "Anirudh songs వద్దు".
    static let excludePatterns = [
        "dont play ([^,]+?)(?: songs| music| today| now|$)",
        "no more ([^,]+?)(?: songs| music| today|$)",
        "without ([^,]+?)(?: songs| music|$)",
        "(?:^| )([^ ]+(?: [^ ]+)?) (?:songs |పాటలు |paatalu |patalu )?(?:vaddu|వద్దు)",
    ]

    /// "play DSP songs", "DSP songs పెట్టు", "songs from Pushpa", "Pushpa movie songs".
    static let playPatterns = [
        "songs from ([^,]+)$",
        "songs of ([^,]+)$",
        "(?:^| )([^ ]+(?: [^ ]+)?) (?:movie|cinema|సినిమా|film) (?:songs|పాటలు|paatalu)",
        "play ([^,]+?) songs",
        "(?:^| )([^ ]+(?: [^ ]+)?) songs (?:pettu|పెట్టు|play|vinipinchu|వినిపించు)",
        "(?:^| )([^ ]+(?: [^ ]+)?) పాటలు (?:పెట్టు|వినిపించు)",
        "^play ([^,]+)$",
    ]
}

// MARK: - Operation helpers

extension SessionOperation {
    var isPlay: Bool {
        if case .play = self { return true }
        return false
    }

    var dimension: VibeDimension? {
        switch self {
        case let .setVibe(dimension, _), let .adjustVibe(dimension, _): dimension
        default: nil
        }
    }

    /// Absolute requests that make sense as "start playing this".
    var startsMusic: Bool {
        switch self {
        case .setVibe, .setLanguage, .setRecency: true
        case let .adjustVibe(dimension, _): dimension == .discovery
        default: false
        }
    }

    /// Anything that moves the session somewhere new (so "keep this vibe" isn't a lock).
    var changesDirection: Bool {
        switch self {
        case .setVibe, .adjustVibe, .setLanguage, .favorLanguage, .setRecency, .newer, .older,
             .seedMode, .play: true
        default: false
        }
    }
}

// MARK: - Utterance

/// A normalized utterance with matching helpers.
struct Utterance {
    let text: String
    let style: SpeechStyle
    private let padded: String

    init(_ raw: String) {
        var text = raw.lowercased()
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
        let separators = CharacterSet(charactersIn: ".,!?;:\"()[]{}…-–—/")
        text = text.components(separatedBy: separators).joined(separator: " ")
        text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        for wake in VoiceLexicon.wake.sorted(by: { $0.count > $1.count })
        where text == wake || text.hasPrefix(wake + " ") {
            text = String(text.dropFirst(wake.count)).trimmingCharacters(in: .whitespaces)
            break
        }
        self.text = text
        padded = " " + text + " "
        let hasTelugu = text.unicodeScalars.contains { (0x0C00...0x0C7F).contains($0.value) }
        let hasLatin = text.unicodeScalars.contains { ("a"..."z").contains(Character($0)) }
        if hasTelugu {
            style = hasLatin ? .mixed : .telugu
        } else {
            let romanized = ["pettu", "cheyyi", "vaddu", "kotha", "patalu", "paatalu", "konchem",
                             "kavali", "nachindi", "nachaledu", "ekkuva", "takkuva", "emaina",
                             "vinipinchu", "bagundi", "evaru", "malli", "ivala", "chedham", "matrame"]
            style = romanized.contains(where: { Self.containsWord(" " + text + " ", $0) }) ? .mixed : .english
        }
    }

    /// True when any phrase appears (Latin: at a word start; Telugu: anywhere).
    func has(_ phrases: [String]) -> Bool {
        phrases.contains { phrase in
            Self.isTelugu(phrase) ? text.contains(phrase) : Self.containsWord(padded, phrase)
        }
    }

    /// An exact whole word.
    func word(_ word: String) -> Bool { padded.contains(" " + word + " ") }

    private static func containsWord(_ padded: String, _ phrase: String) -> Bool {
        padded.contains(" " + phrase)
    }

    private static func isTelugu(_ string: String) -> Bool {
        string.unicodeScalars.contains { (0x0C00...0x0C7F).contains($0.value) }
    }

    /// Music languages in the order they were mentioned.
    var languages: [MusicLanguage] {
        VoiceLexicon.languages
            .compactMap { language, words -> (MusicLanguage, String.Index)? in
                let positions = words.compactMap { word -> String.Index? in
                    if Self.isTelugu(word) { return text.range(of: word)?.lowerBound }
                    return padded.range(of: " " + word).map { text.index(text.startIndex,
                        offsetBy: max(padded.distance(from: padded.startIndex, to: $0.lowerBound), 0)) }
                }
                return positions.min().map { (language, $0) }
            }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// "90s" → 1990, "2000s" → 2000, "80s" → 1980.
    var decade: Int? {
        guard let match = text.range(of: #"(?:^| )((?:19|20)?[0-9]0)s(?: |$)"#, options: .regularExpression)
        else { return nil }
        let digits = text[match].filter(\.isNumber)
        guard let value = Int(digits) else { return nil }
        if digits.count == 4 { return value }
        return value >= 30 ? 1900 + value : 2000 + value
    }

    /// How recent "new" means, from the words used.
    var recencyDays: Int {
        if has(["this week", "yesterday", "ఈ వారం", "నిన్న"]) { return 7 }
        if has(["this month", "ఈ నెల"]) { return 30 }
        if has(["last few months", "few months"]) { return 120 }
        if has(["this year", "ఈ సంవత్సరం"]) { return 365 }
        return 90
    }

    /// Share of words Halo doesn't know at all (a hint the recognizer misheard).
    var unknownShare: Double {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return 1 }
        let unknown = words.filter { !VoiceLexicon.knownWords.contains($0) && Int($0) == nil }
        return Double(unknown.count) / Double(words.count)
    }

    /// The first pattern's capture, with known words removed; nil when nothing is left.
    func capture(_ patterns: [String]) -> String? {
        captureWithPattern(patterns)?.name
    }

    func captureWithPattern(_ patterns: [String]) -> (name: String, pattern: String)? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text) else { continue }
            let name = text[captured].split(separator: " ")
                .map(String.init)
                .filter { !VoiceLexicon.knownWords.contains($0) }
                .joined(separator: " ")
            if !name.isEmpty { return (name, pattern) }
        }
        return nil
    }
}
