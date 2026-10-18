import Foundation
import XCTest
#if canImport(MUSECore)
@testable import MUSECore
#else
@testable import MUSE
#endif

final class BraveURLBuilderTests: XCTestCase {
    func testOpenURLForVideo() throws {
        let watch = try XCTUnwrap(YouTubeIdentifier.watchURL(videoID: "dQw4w9WgXcQ"))
        let brave = try XCTUnwrap(BraveURLBuilder.openURL(for: watch))
        XCTAssertEqual(
            brave.absoluteString,
            "brave://open-url?url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DdQw4w9WgXcQ")
    }

    func testNestedQueryCharactersAreEncoded() throws {
        let target = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&t=1#x"))
        let brave = try XCTUnwrap(BraveURLBuilder.openURL(for: target))
        let query = try XCTUnwrap(brave.query)
        XCTAssertFalse(query.dropFirst("url=".count).contains("&"))
        XCTAssertFalse(query.dropFirst("url=".count).contains("="))
        XCTAssertFalse(brave.absoluteString.contains("#"))
    }

    /// Brave reads the value with URLComponents (`components.valueForQuery("url")`), so the
    /// decoded value must round-trip exactly to the original HTTPS URL.
    func testRoundTripsThroughURLComponentsLikeBrave() throws {
        let originals = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf",
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123&index=2",
        ]
        for original in originals {
            let brave = try XCTUnwrap(BraveURLBuilder.openURL(for: URL(string: original)!))
            let components = try XCTUnwrap(URLComponents(url: brave, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.scheme, "brave")
            XCTAssertEqual(components.host, "open-url")
            XCTAssertEqual(components.queryItems?.count, 1)
            XCTAssertEqual(components.queryItems?.first?.value, original)
        }
    }

    func testRejectsNonYouTubeAndNonHTTPS() {
        XCTAssertNil(BraveURLBuilder.openURL(for: URL(string: "http://www.youtube.com/watch?v=dQw4w9WgXcQ")!))
        XCTAssertNil(BraveURLBuilder.openURL(for: URL(string: "https://evil.example/watch?v=dQw4w9WgXcQ")!))
        XCTAssertNil(BraveURLBuilder.openURL(for: URL(string: "javascript:alert(1)")!))
    }

    func testStrictEncodingKeepsOnlyUnreserved() {
        XCTAssertEqual(BraveURLBuilder.percentEncodeQueryValue("a b&c=d/e?f#g~h.i-j_k"),
                       "a%20b%26c%3Dd%2Fe%3Ff%23g~h.i-j_k")
    }
}
