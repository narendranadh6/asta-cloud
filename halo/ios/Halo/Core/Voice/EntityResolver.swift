import Foundation

/// Turns the names listeners say ("DSP", "Thaman", "ilayaraja", "కీరవాణి") into canonical
/// artist names before they reach the session or the catalog. A small, hand-checked alias
/// table plus a spelling-tolerant key; it never guesses: a name that matches more than one
/// artist is reported as ambiguous so Halo can ask, and an unknown name passes through as said.
public struct EntityResolver: Sendable {
    public struct Entity: Hashable, Sendable {
        public enum Kind: String, Hashable, Sendable { case composer, singer, artist }
        public var name: String
        public var kind: Kind
        public var aliases: [String]
    }

    public enum Resolution: Hashable, Sendable {
        case known(Entity)
        case ambiguous([Entity])
        /// Not in the table: search the catalog with the words as said.
        case unknown(String)
    }

    private let byKey: [String: [Entity]]

    public init(entities: [Entity] = EntityResolver.musicians) {
        var table: [String: [Entity]] = [:]
        for entity in entities {
            for alias in Set(entity.aliases + [entity.name]).map(Self.matchKey) where !alias.isEmpty {
                if !(table[alias]?.contains(entity) ?? false) { table[alias, default: []].append(entity) }
            }
        }
        byKey = table
    }

    public func resolve(_ said: String) -> Resolution {
        let key = Self.matchKey(said)
        guard let found = byKey[key], !found.isEmpty else { return .unknown(said) }
        return found.count == 1 ? .known(found[0]) : .ambiguous(found)
    }

    /// The name to use for searching and matching: canonical when known, else as said.
    public func canonicalName(_ said: String) -> String? {
        if case let .known(entity) = resolve(said) { return entity.name }
        return nil
    }

    /// Rewrites artist mentions in a delta to canonical names. Ambiguous names are returned
    /// so the caller can ask which one was meant; they stay as said in the delta.
    public func resolve(_ delta: IntentDelta) -> (delta: IntentDelta, ambiguous: [String: [Entity]]) {
        var ambiguous: [String: [Entity]] = [:]
        func canonical(_ ref: EntityRef) -> EntityRef {
            guard case let .mention(name, kind) = ref, kind != .soundtrack else { return ref }
            switch resolve(name) {
            case let .known(entity): return .mention(entity.name, kind: .artist)
            case let .ambiguous(options):
                ambiguous[name] = options
                return ref
            case .unknown: return ref
            }
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
        return (resolved, ambiguous)
    }

    /// A spelling-tolerant key: lowercase letters and digits only, common romanization
    /// variants folded ("aa"→"a", "th"→"t", "ee"→"i", doubled letters collapsed). Telugu script
    /// is kept as written, without spaces.
    static func matchKey(_ name: String) -> String {
        let lowered = name.lowercased()
        let isTelugu = lowered.unicodeScalars.contains { (0x0C00...0x0C7F).contains($0.value) }
        if isTelugu {
            return String(lowered.unicodeScalars.filter {
                (0x0C00...0x0C7F).contains($0.value)
            }.map(Character.init))
        }
        var key = String(lowered.unicodeScalars.filter {
            CharacterSet.lowercaseLetters.contains($0) || CharacterSet.decimalDigits.contains($0)
        }.map(Character.init))
        for (from, to) in [("aa", "a"), ("ee", "i"), ("ii", "i"), ("oo", "u"), ("uu", "u"),
                           ("ai", "a"), ("th", "t"), ("dh", "d"), ("bh", "b"), ("kh", "k"),
                           ("sh", "s"), ("ph", "f"), ("y", "i")] {
            key = key.replacingOccurrences(of: from, with: to)
        }
        var collapsed = ""
        for character in key where character != collapsed.last { collapsed.append(character) }
        return collapsed
    }
}

extension EntityResolver {
    /// Well-known names for Telugu and English listening. Canonical names follow their common
    /// credited spelling; aliases are nicknames and common romanizations. Names shared by
    /// several artists ("raja") are listed on each, which makes them ambiguous on purpose.
    public static let musicians: [Entity] = [
        Entity(name: "Devi Sri Prasad", kind: .composer,
               aliases: ["dsp", "devisri", "devi sri", "devisri prasad", "దేవిశ్రీ", "దేవి శ్రీ ప్రసాద్"]),
        Entity(name: "S. Thaman", kind: .composer,
               aliases: ["thaman", "ss thaman", "thaman s", "taman", "తమన్"]),
        Entity(name: "M. M. Keeravani", kind: .composer,
               aliases: ["keeravani", "mm keeravani", "mmk", "keeravaani", "కీరవాణి"]),
        Entity(name: "Ilaiyaraaja", kind: .composer,
               aliases: ["ilayaraja", "ilaiyaraja", "ilayaraaja", "raja sir", "raja", "ఇళయరాజా"]),
        Entity(name: "Yuvan Shankar Raja", kind: .composer,
               aliases: ["yuvan", "u1", "raja"]),
        Entity(name: "A. R. Rahman", kind: .composer,
               aliases: ["arr", "ar rahman", "rahman", "రెహమాన్"]),
        Entity(name: "Anirudh Ravichander", kind: .composer,
               aliases: ["anirudh", "ani", "అనిరుధ్"]),
        Entity(name: "Mickey J. Meyer", kind: .composer, aliases: ["mickey j meyer", "mickey"]),
        Entity(name: "Mani Sharma", kind: .composer, aliases: ["manisharma", "మణిశర్మ"]),
        Entity(name: "Gopi Sundar", kind: .composer, aliases: ["gopi sundar"]),
        Entity(name: "Harris Jayaraj", kind: .composer, aliases: ["harris"]),
        Entity(name: "Hesham Abdul Wahab", kind: .composer, aliases: ["hesham"]),
        Entity(name: "Bheems Ceciroleo", kind: .composer, aliases: ["bheems"]),
        Entity(name: "S. P. Balasubrahmanyam", kind: .singer,
               aliases: ["spb", "sp balu", "balu", "sp balasubrahmanyam", "బాలు", "ఎస్పీబీ"]),
        Entity(name: "S. P. Charan", kind: .singer, aliases: ["sp charan"]),
        Entity(name: "K. S. Chithra", kind: .singer, aliases: ["chitra", "chithra", "ks chitra", "చిత్ర"]),
        Entity(name: "Sid Sriram", kind: .singer, aliases: ["sid sriram", "సిద్ శ్రీరామ్"]),
        Entity(name: "Shreya Ghoshal", kind: .singer, aliases: ["shreya", "shreya ghoshal"]),
        Entity(name: "Anurag Kulkarni", kind: .singer, aliases: ["anurag kulkarni"]),
        Entity(name: "Sunitha Upadrashta", kind: .singer, aliases: ["sunitha", "సునీత"]),
        Entity(name: "Ghantasala", kind: .singer, aliases: ["ghantasala", "ఘంటసాల"]),
        Entity(name: "Arijit Singh", kind: .singer, aliases: ["arijit"]),
        Entity(name: "Taylor Swift", kind: .artist, aliases: ["taylor swift"]),
        Entity(name: "The Weeknd", kind: .artist, aliases: ["weeknd", "the weekend"]),
    ]
}

/// Whether a spoken or normalized artist name refers to a track's artist credit: the name's
/// words appear, in order and as whole words, in the credit ("anirudh" ↔ "Anirudh Ravichander,
/// Arijit Singh"). One- and two-letter names must match the whole credit. Same rule as the
/// server's `artist_matches`.
public enum ArtistMatch {
    public static func matches(_ trackArtist: String, _ nameKey: String) -> Bool {
        let words = SessionState.key(trackArtist).split(separator: " ")
        let wanted = SessionState.key(nameKey).split(separator: " ")
        guard !wanted.isEmpty else { return false }
        if wanted.joined(separator: " ").count < 3 { return words == wanted }
        guard words.count >= wanted.count else { return false }
        return (0...(words.count - wanted.count)).contains { Array(words[$0..<($0 + wanted.count)]) == wanted }
    }

    /// The strongest weight among the names that match `trackArtist`.
    public static func weight(_ trackArtist: String, in weights: [String: Double]) -> Double {
        weights.filter { matches(trackArtist, $0.key) }.map(\.value).max { abs($0) < abs($1) } ?? 0
    }
}
