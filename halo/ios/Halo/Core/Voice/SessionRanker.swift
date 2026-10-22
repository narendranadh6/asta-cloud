import Foundation

/// Re-ranks the songs Halo already has against the current session, instantly and offline.
/// Mirrors the server's `session-v1` features and weights (backend/app/services/
/// recommendations/session.py), so a voice change reorders the pool before any network call.
public enum SessionRanker {
    public static let version = "session-v1"
    static let weights: [String: Double] = [
        "rank": 0.6, "energy": 1.0, "tempo": 0.4, "language": 1.2, "recency": 0.8,
        "discovery": 0.5, "seed": 0.6, "artist": 1.0,
    ]
    static let unknown = 0.5
    static let artistCap = 2

    /// Ranked tracks from `pool` that the session still allows.
    public static func rank(_ pool: [SessionCandidate], for state: SessionState,
                            excluding played: Set<String> = [], today: Date = .now) -> [Track] {
        let scored = pool.compactMap { candidate -> (Track, Double)? in
            let track = candidate.track
            guard !played.contains(track.id), state.excludedTracks[track.id] == nil,
                  state.excludedArtists[SessionState.key(track.artist)] == nil,
                  !violatesLanguage(track, state) else { return nil }
            return (track, score(candidate, state, today: today))
        }
        var perArtist: [String: Int] = [:]
        return scored.sorted { $0.1 > $1.1 }.compactMap { track, _ in
            let artist = SessionState.key(track.artist)
            guard perArtist[artist, default: 0] < artistCap else { return nil }
            perArtist[artist, default: 0] += 1
            return track
        }
    }

    static func score(_ candidate: SessionCandidate, _ state: SessionState, today: Date) -> Double {
        let track = candidate.track
        var fit = candidate.fit  // server values for what the phone can't recompute (rank, seed)
        fit["energy"] = closeness(state.vibe[.energy]?.value, track.energy)
        fit["tempo"] = closeness(state.vibe[.tempo]?.value, track.tempo)
        fit["language"] = languageFit(track, state)
        fit["recency"] = recencyFit(track, state, today: today)
        if let discovery = state.vibe[.discovery]?.value {
            let popularity = min(log10(Double(track.playCount ?? 0) + 1) / 7, 1)
            fit["discovery"] = 1 - abs(discovery - (1 - popularity))
        }
        fit["artist"] = max(min(state.artistWeights[SessionState.key(track.artist)] ?? 0, 1), -1)
        return weights.reduce(0) { total, entry in total + entry.value * (fit[entry.key] ?? unknown) }
    }

    private static func closeness(_ target: Double?, _ value: Double?) -> Double {
        guard let target else { return unknown }
        guard let value else { return unknown }
        return 1 - abs(target - value)
    }

    private static func violatesLanguage(_ track: Track, _ state: SessionState) -> Bool {
        guard let language = state.language, language.strategy == .only,
              let code = track.language else { return false }
        return code != language.primary.rawValue
    }

    private static func languageFit(_ track: Track, _ state: SessionState) -> Double {
        guard let language = state.language else { return unknown }
        guard let code = track.language else { return 0.4 }
        if code == language.primary.rawValue { return 1 }
        if code == language.secondary?.rawValue {
            switch language.strategy {
            case .mostly: return 0.6
            case .mixed: return 0.9
            case .alternating: return 0.95
            case .only: return 0.2
            }
        }
        return 0
    }

    private static func recencyFit(_ track: Track, _ state: SessionState, today: Date) -> Double {
        guard state.recency != .any else { return unknown }
        guard let released = track.releaseDate.flatMap(releaseDate) else { return 0.4 }
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: released)
        switch state.recency {
        case .any:
            return unknown
        case let .withinDays(days):
            let age = Double(calendar.dateComponents([.day], from: released, to: today).day ?? 0)
            let limit = Double(days)
            return age <= limit ? 1 : max(0, 1 - (age - limit) / (limit * 4))
        case let .decade(start):
            if (start..<(start + 10)).contains(year) { return 1 }
            let distance = Double(min(abs(year - start), abs(year - start - 9)))
            return max(0, 1 - distance / 15)
        case .classics:
            return calendar.component(.year, from: today) - year >= 10 ? 1 : 0.2
        }
    }

    private static func releaseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: String(value.prefix(10))) { return date }
        formatter.dateFormat = "yyyy"
        return formatter.date(from: String(value.prefix(4)))
    }
}
