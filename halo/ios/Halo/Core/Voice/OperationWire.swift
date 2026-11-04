import Foundation

/// A compact, stable text form of `SessionOperation` ("set:energy:0.85", "exclude:S. Thaman:today").
/// One vocabulary for the evaluation sets, the labelers' specification and the optional AI
/// fallback, whose output is accepted only if every string parses back into an operation.
extension SessionOperation {
    public var wire: String {
        func ref(_ entity: EntityRef) -> String {
            switch entity {
            case .currentArtist: "current"
            case .currentTrack: "currentTrack"
            case .currentAlbum: "currentAlbum"
            case .lastMentioned: "last"
            case let .mention(name, _): name
            }
        }
        func signed(_ value: Double) -> String { String(format: "%+.2f", value) }
        func plain(_ value: Double) -> String { String(format: "%.2f", value) }
        switch self {
        case .play(.vibe): return "play"
        case .play(.surprise): return "play:surprise"
        case .play(.similarToCurrent): return "play:similar"
        case let .play(.entity(.mention(name, kind))): return "play:\(kind.rawValue):\(name)"
        case let .play(.entity(entity)): return "play:\(ref(entity))"
        case let .transport(action): return "transport:\(action.rawValue)"
        case let .setVibe(dimension, value): return "set:\(dimension.rawValue):\(plain(value))"
        case let .adjustVibe(dimension, value): return "adjust:\(dimension.rawValue):\(signed(value))"
        case let .setLanguage(preference):
            let secondary = preference.secondary.map { "+\($0.rawValue)" } ?? ""
            return "lang:\(preference.strategy.rawValue):\(preference.primary.rawValue)\(secondary)"
        case let .favorLanguage(language): return "favor:\(language.rawValue)"
        case let .setRecency(recency):
            switch recency {
            case .any: return "recency:any"
            case let .withinDays(days): return "recency:days:\(days)"
            case let .decade(year): return "recency:decade:\(year)"
            case .classics: return "recency:classics"
            }
        case .newer: return "newer"
        case .older: return "older"
        case let .preserve(kept): return "preserve:" + kept.map(\.rawValue).sorted().joined(separator: "+")
        case .lock: return "lock"
        case .unlock: return "unlock"
        case let .seedMode(mode): return "seed:\(mode.rawValue)"
        case let .weightArtist(entity, weight): return "weight:\(ref(entity)):\(signed(weight))"
        case let .excludeArtist(entity, scope): return "exclude:\(ref(entity)):\(scope.rawValue)"
        case let .excludeTrack(entity, scope): return "exclude:\(ref(entity)):\(scope.rawValue)"
        case .diversifyArtists: return "diversify"
        case let .avoid(mood): return "avoid:\(mood.rawValue)"
        case let .rate(rating): return "rate:\(rating.rawValue)"
        case let .ask(question): return "ask:\(question.rawValue)"
        case .undo: return "undo"
        }
    }

    /// Parses the wire form; nil for anything outside the vocabulary or out of range, so
    /// untrusted text (e.g. a model's output) can never produce an unexpected operation.
    public init?(wire raw: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, text.count <= 120 else { return nil }
        let parts = text.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        func number(_ s: String, signed: Bool) -> Double? {
            guard let value = Double(s), value.isFinite else { return nil }
            if signed { return (-1...1).contains(value) ? value : nil }
            return (0...1).contains(value) ? value : nil
        }
        func entity(_ s: String, kind: EntityRef.Kind = .artist) -> EntityRef? {
            switch s {
            case "current": return .currentArtist
            case "currentTrack": return .currentTrack
            case "currentAlbum": return .currentAlbum
            case "last": return .lastMentioned
            default:
                let name = s.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty, name.count <= 80 else { return nil }
                return .mention(name, kind: kind)
            }
        }
        switch parts[0] {
        case "play":
            if parts.count == 1 { self = .play(.vibe); return }
            switch parts[1] {
            case "surprise" where parts.count == 2: self = .play(.surprise)
            case "similar" where parts.count == 2: self = .play(.similarToCurrent)
            case "current" where parts.count == 2: self = .play(.entity(.currentArtist))
            case "currentAlbum" where parts.count == 2: self = .play(.entity(.currentAlbum))
            default:
                guard parts.count == 3, let kind = EntityRef.Kind(rawValue: parts[1]),
                      let ref = entity(parts[2], kind: kind), case .mention = ref else { return nil }
                self = .play(.entity(ref))
            }
        case "transport":
            guard parts.count == 2, let action = Transport(rawValue: parts[1]) else { return nil }
            self = .transport(action)
        case "set", "adjust":
            guard parts.count == 3, let dimension = VibeDimension(rawValue: parts[1]),
                  let value = number(parts[2], signed: parts[0] == "adjust") else { return nil }
            self = parts[0] == "set" ? .setVibe(dimension, value) : .adjustVibe(dimension, value)
        case "lang":
            guard parts.count == 3, let strategy = LanguagePreference.Strategy(rawValue: parts[1]) else { return nil }
            let codes = parts[2].split(separator: "+").map { MusicLanguage(rawValue: String($0)) }
            guard let primary = codes.first, codes.count <= 2,
                  codes.allSatisfy({ MusicLanguage.supported.contains($0) }) else { return nil }
            if strategy == .only {
                guard codes.count == 1 else { return nil }
                self = .setLanguage(.only(primary))
            } else {
                guard codes.count == 2 else { return nil }
                self = .setLanguage(LanguagePreference(primary: primary, secondary: codes[1], strategy: strategy))
            }
        case "favor":
            let language = MusicLanguage(rawValue: parts.count == 2 ? parts[1] : "")
            guard MusicLanguage.supported.contains(language) else { return nil }
            self = .favorLanguage(language)
        case "recency":
            guard parts.count >= 2 else { return nil }
            switch parts[1] {
            case "any" where parts.count == 2: self = .setRecency(.any)
            case "classics" where parts.count == 2: self = .setRecency(.classics)
            case "days":
                guard parts.count == 3, let days = Int(parts[2]), (1...3650).contains(days) else { return nil }
                self = .setRecency(.withinDays(days))
            case "decade":
                guard parts.count == 3, let year = Int(parts[2]), (1900...2090).contains(year), year % 10 == 0
                else { return nil }
                self = .setRecency(.decade(year))
            default: return nil
            }
        case "newer" where parts.count == 1: self = .newer
        case "older" where parts.count == 1: self = .older
        case "preserve":
            guard parts.count == 2 else { return nil }
            let kept = parts[1].split(separator: "+").compactMap { Preserved(rawValue: String($0)) }
            guard !kept.isEmpty else { return nil }
            self = .preserve(Set(kept))
        case "lock" where parts.count == 1: self = .lock
        case "unlock" where parts.count == 1: self = .unlock
        case "seed":
            guard parts.count == 2, let mode = SeedMode(rawValue: parts[1]) else { return nil }
            self = .seedMode(mode)
        case "weight":
            guard parts.count == 3, let ref = entity(parts[1]), ref != .currentTrack,
                  let weight = number(parts[2], signed: true) else { return nil }
            self = .weightArtist(ref, weight)
        case "exclude":
            guard parts.count == 3, let scope = Scope(rawValue: parts[2]) else { return nil }
            if parts[1] == "currentTrack" {
                self = .excludeTrack(.currentTrack, scope)
            } else {
                guard let ref = entity(parts[1]) else { return nil }
                self = .excludeArtist(ref, scope)
            }
        case "diversify" where parts.count == 1: self = .diversifyArtists
        case "avoid":
            guard parts.count == 2, let mood = MoodTag(rawValue: parts[1]) else { return nil }
            self = .avoid(mood)
        case "rate":
            guard parts.count == 2, let rating = Rating(rawValue: parts[1]) else { return nil }
            self = .rate(rating)
        case "ask":
            guard parts.count == 2, let question = Question(rawValue: parts[1]) else { return nil }
            self = .ask(question)
        case "undo" where parts.count == 1: self = .undo
        default: return nil
        }
    }
}
