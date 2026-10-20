import Foundation

/// Halo track ids: "<source>:<id at that source>", e.g. "audius:D7KyD". Ids come from the
/// backend; the app validates them before putting one in a URL path.
public enum TrackID {
    private static let sources: Set<String> = ["audius", "jamendo", "itunes"]
    private static let allowed = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")

    public static func isValid(_ value: String) -> Bool {
        let parts = value.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, sources.contains(String(parts[0])) else { return false }
        let id = parts[1]
        return (1...40).contains(id.count)
            && id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
