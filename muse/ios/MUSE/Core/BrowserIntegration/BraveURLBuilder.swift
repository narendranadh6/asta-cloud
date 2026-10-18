import Foundation

/// Builds Brave deep links.
///
/// Verified against Brave's open-source iOS client (brave/brave-core,
/// `ios/brave-ios/Sources/Brave/Frontend/Browser/NavigationRouter.swift`, checked
/// 2026-10-18): the release app registers the `brave` scheme (`BRAVE_URL_SCHEME` in
/// `Base.xcconfig`; Beta/Nightly use `brave-beta`/`brave-nightly`) and routes
/// `brave://open-url?url=<url>` by reading the `url` query value and opening it in a tab.
/// Brave's own share extension (`OpenInBraveViewController.swift`) builds the same form.
///
/// This is a public deep link, not a private API. Behaviour still has to be verified on a
/// real iPhone with Brave installed (see docs/brave-integration.md).
public enum BraveURLBuilder {
    public static let scheme = "brave"
    public static let host = "open-url"

    /// RFC 3986 unreserved characters only. Everything else, including `&`, `=`, `?`, `/`
    /// and `#`, is percent-encoded so the nested URL survives as a single query value.
    /// (`URLQueryItem` would leave `&`/`=` unescaped, which would truncate nested URLs.)
    static let strictQueryValueAllowed: CharacterSet = {
        var set = CharacterSet()
        set.insert(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return set
    }()

    public static func percentEncodeQueryValue(_ value: String) -> String? {
        value.addingPercentEncoding(withAllowedCharacters: strictQueryValueAllowed)
    }

    /// `brave://open-url?url=<strictly percent-encoded https URL>`
    /// Only HTTPS URLs on YouTube hosts are accepted.
    public static func openURL(for target: URL) -> URL? {
        guard target.scheme?.lowercased() == "https",
              let host = target.host?.lowercased(),
              host == "www.youtube.com" || host == "youtube.com" || host == "m.youtube.com"
                || host == "music.youtube.com",
              let encoded = percentEncodeQueryValue(target.absoluteString)
        else { return nil }
        return URL(string: "\(scheme)://\(Self.host)?url=\(encoded)")
    }

    /// URL used with `canOpenURL` to detect Brave. Requires `brave` in
    /// `LSApplicationQueriesSchemes` (Info.plist).
    public static var detectionURL: URL { URL(string: "\(scheme)://")! }
}
