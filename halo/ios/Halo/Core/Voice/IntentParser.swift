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
        // "Skip this artist" refuses the artist (skipping a song is a control, handled below).
        let refusing = u.isNegated || (u.has(["skip"]) && u.has(VoiceLexicon.thisArtist))
        // "Today" is the most specific; "never" / "don't ever … again" make it lasting.
        let lasting = u.has(VoiceLexicon.never) || (u.word("ever") && refusing)
        let lastingScope: Scope = u.has(VoiceLexicon.today) ? .today : lasting ? .profile : .session
        if u.has(VoiceLexicon.thisSong) && refusing && !u.has(VoiceLexicon.thisArtist) {
            // "Never this song" is the song-level "never again"; otherwise just this session.
            ops.append(lastingScope == .profile ? .rate(.neverAgain) : .excludeTrack(.currentTrack, .session))
        }
        if u.has(VoiceLexicon.thisArtist) {
            if u.has(["explore"]) {
                ops.append(.play(.entity(.currentArtist)))
            } else if u.has(VoiceLexicon.less) {
                ops.append(.weightArtist(.currentArtist, -0.6))
            } else if refusing {
                ops.append(.excludeArtist(.currentArtist, lastingScope))
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
        var playable = mentioned.filter { MusicLanguage.supported.contains($0) }
        // "Telugu songs, not English" / "English vaddu": a negated language is ruled out, and with
        // two supported languages that leaves the other one.
        let refused = playable.filter { u.isNegatedNear(language: $0) }
        var languageOnlyFromRefusal = false
        if !refused.isEmpty {
            playable.removeAll { refused.contains($0) }
            if playable.isEmpty, refused.count == 1,
               let other = MusicLanguage.supported.subtracting(refused).sorted(by: { $0.rawValue > $1.rawValue }).first {
                ops.append(.setLanguage(.only(other)))
                languageOnlyFromRefusal = true
            }
        }
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
        let asksToPlay = u.has(playVerbs) || u.has(["songs", "music", "playlist", "పాటలు", "paatalu", "patalu"])
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
        if u.has(VoiceLexicon.tempoFast) {
            // A fast-tempo request is absolute: "beat ekkuva" isn't "more energy".
            ops.removeAll { $0.dimension == .energy }
            ops.append(.setVibe(.tempo, 0.8))
            ops.append(.setVibe(.energy, 0.85))
        } else if u.has(VoiceLexicon.tempoSlow) {
            ops.append(.setVibe(.tempo, 0.3))
        }
        let negated = u.isNegated
        if u.has(VoiceLexicon.sad) {
            ops.append(negated ? .avoid(.sad) : .setVibe(.valence, 0.25))
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
        let onlyAnything = u.has(VoiceLexicon.anything) && ops.isEmpty
        if u.has(VoiceLexicon.surprise) || onlyAnything {
            ops.append(.play(.surprise))
            ops.append(.adjustVibe(.discovery, 0.3))
        } else if wantsDiscovery {
            ops.append(.adjustVibe(.discovery, 0.3))
        } else if u.has(VoiceLexicon.familiar) {
            ops.append(.setVibe(.discovery, 0.15))
        }
        if u.has(VoiceLexicon.deeper) {
            ops.append(.seedMode(.deeper))
        } else if u.has(VoiceLexicon.otherSongs) {
            ops.append(.preserve([.vibe]))
            ops.append(.play(.vibe))
        } else if u.has(VoiceLexicon.elsewhere) && !u.has(VoiceLexicon.differentArtist) {
            ops.append(.seedMode(.elsewhere))
            ops.append(.adjustVibe(.discovery, 0.3))
        }
        if u.has(VoiceLexicon.similar) && !u.has(VoiceLexicon.like.filter { $0.hasPrefix("i ") }) {
            ops.append(.play(.similarToCurrent))
        }

        // 7. Named artists, films, albums, songs and genres (resolved later; never guessed).
        let hasDimension = ops.contains { $0.dimension != nil }
        if let name = u.capture(downweightPatterns) {
            ops.append(.weightArtist(.mention(name, kind: .artist), -0.6))
        } else if let name = u.capture(excludePatterns) {
            ops.append(.excludeArtist(.mention(name, kind: .artist), lastingScope))
        } else if u.has(VoiceLexicon.lessOfThem) && !u.has(VoiceLexicon.thisArtist) && !hasDimension {
            ops.append(.weightArtist(.lastMentioned, -0.6))
        } else if !ops.contains(where: \.isPlay) {
            if let title = u.captureRaw(songPatterns) {
                ops.append(.play(.entity(.mention(title, kind: .song))))
            } else if let album = u.captureRaw(albumPatterns) {
                ops.append(.play(.entity(.mention(album, kind: .album))))
            } else if let genre = u.genre, !u.has(VoiceLexicon.thisArtist) {
                ops.append(.play(.entity(.mention(genre, kind: .genre))))
            } else if let match = u.captureWithPattern(playPatterns),
                      !(match.pattern == Self.weakPlayPattern && !ops.isEmpty) {
                let soundtrack = u.has(["movie", "film", "cinema", "సినిమా", "soundtrack"])
                    || match.pattern.contains("from")
                ops.append(.play(.entity(.mention(match.name, kind: soundtrack ? .soundtrack : .any))))
            }
        }

        // 8. "Keep this vibe" versus "same vibe but …".
        let changes = ops.contains { $0.changesDirection }
        if (u.has(VoiceLexicon.lockVibe) || u.has(VoiceLexicon.same)) && !changes {
            ops.append(.lock)
        } else if u.has(VoiceLexicon.same) && changes && !ops.contains(.preserve([.vibe])) {
            ops.insert(.preserve([.vibe]), at: 0)
        }

        // 9. A request ("play …", "… songs పెట్టు") starts new music; a bare change re-ranks.
        let starts = ops.contains { $0.startsMusic }
        // "No English songs" sets a rule; it isn't a request to start something.
        // Accepting a mood ("I don't mind sad songs") or setting a rule ("Telugu songs matrame")
        // changes the session but doesn't start music unless a play verb says so.
        let onlyARule = (languageOnlyFromRefusal && ops.filter(\.startsMusic).count == 1
                         || u.has(VoiceLexicon.acceptances) || u.has(VoiceLexicon.restrictions))
            && !u.has(playVerbs)
        if asksToPlay && starts && !onlyARule && !ops.contains(where: \.isPlay) {
            ops.insert(.play(.vibe), at: 0)
        }

        // 10. Nothing else: transport words.
        if ops.isEmpty && unsupported.isEmpty {
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
        // "What's playing next?", "tarvata emi vastundi": asking, not skipping.
        if u.has(VoiceLexicon.nextWords), VoiceLexicon.questionWords.contains(where: u.word),
           !u.has(playVerbs) || u.has(["playing next", "plays after", "plays next"]) {
            return [.ask(.upNext)]
        }
        if u.has(VoiceLexicon.whoIsSinging) { return [.ask(.whoIsSinging)] }
        if u.has(VoiceLexicon.whatMovie) { return [.ask(.whatMovie)] }
        if u.has(VoiceLexicon.whatAlbum) { return [.ask(.whatAlbum)] }
        if u.has(VoiceLexicon.whenReleased) { return [.ask(.whenReleased)] }
        if u.has(VoiceLexicon.neverAgain) && !u.has(VoiceLexicon.thisArtist) { return [.rate(.neverAgain)] }
        if u.has(VoiceLexicon.never), u.has(VoiceLexicon.thisSong) || u.word("this"), !u.has(VoiceLexicon.thisArtist),
           !u.has(VoiceLexicon.sad), u.languages.isEmpty {
            return [.rate(.neverAgain)]
        }
        if u.has(VoiceLexicon.later) { return [.rate(.later)] }
        if u.has(VoiceLexicon.removeNext) { return [.transport(.removeNext)] }
        if u.has(VoiceLexicon.dislike) { return [.rate(.dislike)] }
        if u.has(VoiceLexicon.like) && !u.has(["more like", "songs like", "something like"]) {
            return [.rate(.like)]
        }
        if u.has(VoiceLexicon.keep) && !u.has(VoiceLexicon.lockVibe) && !u.has(["vibe"]) {
            // "Keep it" is a rating only on its own; "keep it energetic but older" steers.
            let steers = !u.languages.isEmpty || u.has(playVerbs) || u.has(VoiceLexicon.energyUp)
                || u.has(VoiceLexicon.energyDown) || u.has(VoiceLexicon.olderWords) || u.has(VoiceLexicon.newerWords)
            if !(steers && u.has(["keep it"])) { return [.rate(.keep)] }
        }
        return nil
    }

    private static func transport(_ u: Utterance) -> Transport? {
        // "Don't …" never falls back to a control: the interpreter reports it as no action.
        if u.isNegated { return nil }
        if u.has(VoiceLexicon.pause) { return .pause }
        if u.has(VoiceLexicon.restart) { return .restart }
        if u.has(VoiceLexicon.next) { return .next }
        if u.has(VoiceLexicon.previous) { return .previous }
        // A bare "play"/"pettu" resumes, but only when every word is understood: "Amma ki call
        // cheyyi" must not resume music.
        if u.has(VoiceLexicon.resume) || (u.has(playVerbs) && u.unknownShare == 0) { return .resume }
        return nil
    }

    // MARK: Patterns for names

    static let playVerbs = ["play", "put on", "give me", "start", "pettu", "పెట్టు", "cheyyi",
                            "చెయ్యి", "vinipinchu", "వినిపించు", "kavali", "కావాలి"]

    /// "too much Anirudh", "less of DSP", "Anirudh songs ekkuva vaddu", "Anirudh takkuva cheyyi".
    static let downweightPatterns = [
        "(?:^| )([^ ]+(?: [^ ]+)?) (?:ni |vi |songs |paatalu |patalu |పాటలు )?(?:ekkuva|too much|ఎక్కువ) "
            + "(?:[a-z]+(?:aku|akandi)|vaddu|vaddandi|oddu|వద్దు|పెట్టకు|పెట్టకండి|వినిపించకు)",
        "(?:^| )([^ ]+(?: [^ ]+)?) (?:songs |paatalu |patalu |పాటలు )?(?:ekkuva|ఎక్కువ) (?:vaddu|వద్దు)",
        "(?:^| )([^ ]+(?: [^ ]+)?) (?:songs |paatalu |patalu |పాటలు )?(?:takkuva|తక్కువ) (?:cheyyi|pettu|చెయ్యి|పెట్టు)",
        "too many ([^,]+?)(?: songs| music|$)",
        "too much ([^,]+?)(?: songs| music| please|$)",
        "less of ([^,]+?)(?: songs| music|$)",
        "less ([^,]+?)(?: songs| music|$)",
    ]

    /// "don't play Anirudh", "no DSP today", "Anirudh songs వద్దు".
    static let excludePatterns = [
        "dont play ([^,]+?)(?: songs| music| today| now|$)",
        "no more ([^,]+?)(?: songs| music| today|$)",
        "without ([^,]+?)(?: songs| music|$)",
        "(?:^|actually |but )no ([^ ,]+(?: [^ ,]+)?)(?: songs| music)?(?: today| now| please)?$",
        "dont play anything by ([^,]+?)(?: today| now|$)",
        "nothing by ([^,]+?)(?: today| now|$)",
        "(?:^| )([^ ]+(?: [^ ]+){0,2}) (?:songs |పాటలు |paatalu |patalu )?(?:vaddu|వద్దు)",
    ]

    /// "play X" with nothing else understood: used only when the sentence has no other request.
    static let weakPlayPattern = "^play ([^,]+)$"

    /// "play the song X", "X song pettu" (one song, by title).
    static let songPatterns = [
        "^play the song ([^,]+)$",
        "^(?:play )?([^,]+?) (?:song|paata|పాట) (?:pettu|play|vinipinchu|పెట్టు|వినిపించు)$",
    ]

    /// "play the album X", "X album songs".
    static let albumPatterns = [
        "^play (?:the )?album ([^,]+)$",
        "(?:^| )([^ ]+(?: [^ ]+)?) album (?:songs|paatalu|patalu|పాటలు|pettu|play)",
    ]

    /// "play DSP songs", "DSP songs పెట్టు", "songs from Pushpa", "Pushpa movie songs".
    static let playPatterns = [
        "songs from ([^,]+)$",
        "songs of ([^,]+)$",
        "songs by ([^,]+)$",
        "(?:^| )([^ ]+(?: [^ ]+)?) (?:movie|cinema|సినిమా|film) (?:songs|పాటలు|paatalu)",
        "play ([^,]+?) songs",
        "(?:^| )([^ ]+(?: [^ ]+){0,2}) songs (?:pettu|pettandi|petu|పెట్టు|play|vinipinchu|vinipinchandi|వినిపించు)",
        "(?:^| )([^ ]+(?: [^ ]+){0,2}) పాటలు (?:పెట్టు|పెట్టండి|వినిపించు|వినిపించండి)",
        "(?:^| )([^ ]+(?: [^ ]+){0,2}) (?:paatalu|patalu) (?:pettu|pettandi|petu|vinipinchu|vinipinchandi)",
        weakPlayPattern,
        // A name followed by a style word: "Thaman mass beats", "Keeravani melodies".
        "^([^ ]+(?: [^ ]+)?) (?:mass|melody|melodies|dance|party|romantic|love|happy|energetic|calm|beats|hits|numbers)(?: |$)",
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
        // A leading "no," / "kaadu," / "no no" is an interjection before the real request.
        let interjection = #"^(?:(?:no|nah|nope|kaadu|కాదు)\s*,\s*|(?:no no|kaadu kaadu|కాదు కాదు)\b[\s,]*)+"#
        let lowered = raw.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "")
        if let match = lowered.range(of: interjection, options: .regularExpression), match.upperBound < lowered.endIndex {
            text = String(lowered[match.upperBound...])
            text = text.components(separatedBy: separators).joined(separator: " ")
            text = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
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
            Self.isTelugu(phrase) ? VoiceLexicon.teluguContains(text, phrase) : Self.containsWord(padded, phrase)
        }
    }

    /// The request is negated ("don't …", "never …", "… vaddu", "vinipinchaku"), ignoring phrases
    /// that only look negative ("I don't mind", "parledu") and a leading "no," before a request.
    var isNegated: Bool {
        var words = negationScopeText.split(separator: " ").map(String.init)
        if words.first == "no", words.count > 1,
           IntentParser.playVerbs.contains(words[1]) || ["actually", "wait", "i", "lets"].contains(words[1]) {
            words.removeFirst()
        }
        let joined = " " + words.joined(separator: " ") + " "
        if words.contains(where: { VoiceLexicon.negationWords.contains($0) || Self.isNegativeImperative($0) }) {
            return true
        }
        return VoiceLexicon.negationPhrases.contains { phrase in
            Self.isTelugu(phrase) ? joined.contains(phrase) : joined.contains(" " + phrase + " ")
        }
    }

    /// Whether a language is the thing being refused: a negation right before it
    /// ("not English") or right after it ("English vaddu").
    func isNegatedNear(language: MusicLanguage) -> Bool {
        let words = negationScopeText.split(separator: " ").map(String.init)
        guard let names = VoiceLexicon.languages.first(where: { $0.0 == language })?.1 else { return false }
        for (index, word) in words.enumerated() where names.contains(where: { word.hasPrefix($0) || word.contains($0) && Self.isTelugu($0) }) {
            let before = words[max(0, index - 2)..<index]
            let after = words[(index + 1)..<min(words.count, index + 3)].filter { !["songs", "paatalu", "patalu", "పాటలు", "music"].contains($0) }
            if before.contains(where: { ["not", "no", "without", "dont"].contains($0) }) { return true }
            if let next = after.first, VoiceLexicon.refuse.contains(next) || Self.isNegativeImperative(next) { return true }
        }
        return false
    }

    /// The text with phrases that only look negative removed.
    private var negationScopeText: String {
        var scoped = " " + text + " "
        for phrase in VoiceLexicon.notNegations { scoped = scoped.replacingOccurrences(of: " " + phrase + " ", with: " ") }
        return scoped.split(separator: " ").joined(separator: " ")
    }

    /// Romanized negative imperatives: "pettaku", "vinipinchaku", "cheyyakandi".
    static func isNegativeImperative(_ word: String) -> Bool {
        guard word.count >= 6, !VoiceLexicon.notNegativeImperatives.contains(word),
              word.unicodeScalars.allSatisfy({ ("a"..."z").contains(Character($0)) }) else { return false }
        return word.hasSuffix("aku") || word.hasSuffix("akandi") || word.hasSuffix("akunda")
    }

    /// An exact whole word.
    func word(_ word: String) -> Bool { padded.contains(" " + word + " ") }

    /// Earlier words of the phrase match whole words; the last may carry a suffix ("telugulo",
    /// "newer"), unless the word is a different word that merely starts the same ("news").
    private static func containsWord(_ padded: String, _ phrase: String) -> Bool {
        guard padded.contains(" " + phrase) else { return false }
        let tokens = padded.split(separator: " ").map(String.init)
        let parts = phrase.split(separator: " ").map(String.init)
        guard let lastPart = parts.last, tokens.count >= parts.count else { return false }
        for start in 0...(tokens.count - parts.count) {
            guard Array(tokens[start..<(start + parts.count - 1)]) == Array(parts.dropLast()) else { continue }
            let last = tokens[start + parts.count - 1]
            if last == lastPart || (last.hasPrefix(lastPart) && !VoiceLexicon.falsePrefixes.contains(last)) {
                return true
            }
        }
        return false
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
        for (year, words) in VoiceLexicon.decadeWords where has(words) { return year }
        guard let match = text.range(of: #"(?:^| )((?:19|20)?[0-9]0)s(?: |$)"#, options: .regularExpression)
        else { return nil }
        let digits = text[match].filter(\.isNumber)
        guard let value = Int(digits) else { return nil }
        if digits.count == 4 { return value }
        return value >= 30 ? 1900 + value : 2000 + value
    }

    /// How recent "new" means, from the words used.
    var recencyDays: Int {
        if has(["yesterday", "ninna", "నిన్న"]) { return 1 }
        if has(["this week", "ee week", "ఈ వారం"]) { return 7 }
        if has(["this month", "ee month", "ఈ నెల"]) { return 30 }
        if has(["last few months", "few months"]) { return 120 }
        if has(["this year", "ee year", "ee samvatsaram", "ఈ సంవత్సరం"]) { return 365 }
        return 90
    }

    /// Share of words Halo doesn't know at all (a hint the recognizer misheard).
    var unknownShare: Double { unknownShare(knownNames: []) }

    /// Share of unknown words, counting the words of recognized names as known.
    func unknownShare(knownNames: Set<String>) -> Double {
        let words = text.split(separator: " ").map(String.init).filter { !knownNames.contains($0) }
        guard !words.isEmpty else { return 0 }
        let unknown = words.filter { !VoiceLexicon.isKnown($0) && Int($0) == nil }
        return Double(unknown.count) / Double(words.count)
    }

    /// The genre named in the sentence, if any.
    var genre: String? {
        VoiceLexicon.genres.first { has($0.1) }?.0
    }

    /// A title as said (songs, albums): only a leading article is dropped, because titles can
    /// contain any words. Nil when nothing but known command words is left.
    func captureRaw(_ patterns: [String]) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
                  let captured = Range(match.range(at: 1), in: text) else { continue }
            var words = text[captured].split(separator: " ").map(String.init)
            if words.first == "the" || words.first == "a" { words.removeFirst() }
            let meaningful = words.filter { !VoiceLexicon.isKnown($0) && !VoiceLexicon.commonWords.contains($0) }
            if !meaningful.isEmpty { return words.joined(separator: " ") }
        }
        return nil
    }

    /// "90s", "2010s", "2014": times, never names.
    static func isNumberOrDecade(_ word: String) -> Bool {
        word.range(of: #"^[0-9]+s?$"#, options: .regularExpression) != nil
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
                .filter { !VoiceLexicon.isKnown($0) && !VoiceLexicon.commonWords.contains($0)
                    && !Self.isNumberOrDecade($0) }
                .joined(separator: " ")
            if !name.isEmpty { return (name, pattern) }
        }
        return nil
    }
}
