import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

final class YouTubeIdentifierTests: XCTestCase {
    func testValidVideoIDs() {
        for id in ["dQw4w9WgXcQ", "abc-DEF_123", "___________"] {
            XCTAssertTrue(YouTubeIdentifier.isValidVideoID(id), id)
        }
    }

    func testInvalidVideoIDs() {
        for id in ["", "short", "dQw4w9WgXcQQ", "dQw4w9WgXc!", "dQw4w9WgXc ", "dQw4w9WgX&c",
                   "dQw4w9%67Xc", "dQw4w9WgXcé", "../../etc/p"] {
            XCTAssertFalse(YouTubeIdentifier.isValidVideoID(id), id)
        }
    }

    func testWatchURLIsCanonical() {
        XCTAssertEqual(
            YouTubeIdentifier.watchURL(videoID: "dQw4w9WgXcQ")?.absoluteString,
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertNil(YouTubeIdentifier.watchURL(videoID: "bad&id=evil"))
    }

    func testPlaylistIDs() {
        XCTAssertTrue(YouTubeIdentifier.isValidPlaylistID("PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"))
        XCTAssertTrue(YouTubeIdentifier.isValidPlaylistID("OLAK5uy_kq5dpzbd1yBpVq5YlXP7sOq3g6mXf8dvY"))
        XCTAssertFalse(YouTubeIdentifier.isValidPlaylistID("XX1234567890"))
        XCTAssertFalse(YouTubeIdentifier.isValidPlaylistID("PLshort"))
        XCTAssertFalse(YouTubeIdentifier.isValidPlaylistID("PL<script>alert(1)</script>"))
        XCTAssertEqual(
            YouTubeIdentifier.playlistURL(playlistID: "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")?
                .absoluteString,
            "https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
    }

    func testExtractVideoIDFromLinks() {
        let cases: [(String, String?)] = [
            ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=PL1", "dQw4w9WgXcQ"),
            ("https://youtu.be/dQw4w9WgXcQ?t=10", "dQw4w9WgXcQ"),
            ("https://www.youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
            ("https://evil.example/watch?v=dQw4w9WgXcQ", nil),
            ("https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ", nil),
            ("javascript:alert(1)", nil),
            ("https://www.youtube.com/watch?v=short", nil),
        ]
        for (input, expected) in cases {
            XCTAssertEqual(YouTubeIdentifier.videoID(fromURLString: input), expected, input)
        }
    }
}
