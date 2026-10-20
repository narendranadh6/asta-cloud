import Foundation

/// Validation for YouTube identifiers. Mirrors backend `app/services/youtube/ids.py`.
/// Only identifiers that pass these checks are ever turned into URLs.
public enum YouTubeIdentifier {
    private static let idCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
    private static let playlistPrefixes = ["OLAK5uy_", "PL", "OL", "UU", "FL", "LL", "RD"]
    private static let youtubeHosts: Set<String> = [
        "youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com",
    ]

    private static func onlyIDCharacters(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { idCharacters.contains($0) }
    }

    public static func isValidVideoID(_ value: String) -> Bool {
        value.unicodeScalars.count == 11 && onlyIDCharacters(value)
    }

    public static func isValidPlaylistID(_ value: String) -> Bool {
        guard let prefix = playlistPrefixes.first(where: { value.hasPrefix($0) }) else {
            return false
        }
        let rest = value.dropFirst(prefix.count)
        return (10...64).contains(rest.count) && onlyIDCharacters(String(rest))
    }

    /// Canonical watch URL for a validated video id.
    public static func watchURL(videoID: String) -> URL? {
        guard isValidVideoID(videoID) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/watch"
        components.queryItems = [URLQueryItem(name: "v", value: videoID)]
        return components.url
    }

    public static func playlistURL(playlistID: String) -> URL? {
        guard isValidPlaylistID(playlistID) else { return nil }
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = "/playlist"
        components.queryItems = [URLQueryItem(name: "list", value: playlistID)]
        return components.url
    }

    /// Extracts a video id from a pasted YouTube link. Returns nil for anything else.
    public static func videoID(fromURLString string: String) -> String? {
        guard let components = URLComponents(
                string: string.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased()
        else { return nil }
        var candidate: String?
        if host == "youtu.be" {
            candidate = components.path.split(separator: "/").first.map(String.init)
        } else if youtubeHosts.contains(host) {
            if components.path == "/watch" {
                candidate = components.queryItems?.first(where: { $0.name == "v" })?.value
            } else {
                let parts = components.path.split(separator: "/").map(String.init)
                if parts.count >= 2, ["embed", "shorts", "live", "v"].contains(parts[0]) {
                    candidate = parts[1]
                }
            }
        }
        guard let candidate, isValidVideoID(candidate) else { return nil }
        return candidate
    }
}
