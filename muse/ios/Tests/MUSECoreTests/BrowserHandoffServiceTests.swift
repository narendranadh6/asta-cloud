import Foundation
import XCTest
#if canImport(MUSECore)
@testable import MUSECore
#else
@testable import MUSE
#endif

@MainActor
final class BrowserHandoffServiceTests: XCTestCase {
    private var opener: FakeURLOpener!
    private var preference: BrowserDestination = .brave

    override func setUp() async throws {
        opener = FakeURLOpener()
        preference = .brave
    }

    private func makeService() -> BraveBrowserHandoffService {
        BraveBrowserHandoffService(opener: opener, preference: { [unowned self] in self.preference })
    }

    func testOpensBraveWhenInstalled() async throws {
        opener.installedSchemes = ["brave"]
        let result = try await makeService().openYouTubeVideo(id: "dQw4w9WgXcQ")
        XCTAssertEqual(result.openedWith, .brave)
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(opener.opened.map(\.scheme), ["brave"])
        XCTAssertTrue(opener.opened[0].absoluteString.hasPrefix("brave://open-url?url=https%3A%2F%2F"))
    }

    func testFallsBackToHTTPSWhenBraveMissing() async throws {
        let result = try await makeService().openYouTubeVideo(id: "dQw4w9WgXcQ")
        XCTAssertEqual(result.openedWith, .systemDefault)
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(opener.opened.map(\.absoluteString),
                       ["https://www.youtube.com/watch?v=dQw4w9WgXcQ"])
    }

    func testFallsBackWhenBraveOpenFails() async throws {
        opener.installedSchemes = ["brave"]
        opener.failingSchemes = ["brave"]
        let result = try await makeService().openYouTubeVideo(id: "dQw4w9WgXcQ")
        XCTAssertEqual(result.openedWith, .systemDefault)
        XCTAssertTrue(result.usedFallback)
        XCTAssertEqual(opener.opened.map(\.scheme), ["brave", "https"])
    }

    func testDefaultBrowserPreferenceSkipsBrave() async throws {
        opener.installedSchemes = ["brave"]
        preference = .systemDefault
        let result = try await makeService().openYouTubeVideo(id: "dQw4w9WgXcQ")
        XCTAssertEqual(result.openedWith, .systemDefault)
        XCTAssertFalse(result.usedFallback)
        XCTAssertEqual(opener.opened.map(\.scheme), ["https"])
    }

    func testThrowsWhenNothingOpens() async {
        opener.failingSchemes = ["https"]
        do {
            _ = try await makeService().openYouTubeVideo(id: "dQw4w9WgXcQ")
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? HandoffError, .openFailed)
        }
    }

    func testRejectsInvalidIdentifiersWithoutOpeningAnything() async {
        for id in ["", "bad&id=evil", "javascript:x"] {
            do {
                _ = try await makeService().openYouTubeVideo(id: id)
                XCTFail("expected failure for \(id)")
            } catch {
                XCTAssertEqual(error as? HandoffError, .invalidVideoID)
            }
        }
        do {
            _ = try await makeService().openYouTubePlaylist(id: "nope")
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error as? HandoffError, .invalidPlaylistID)
        }
        XCTAssertTrue(opener.opened.isEmpty)
    }

    func testOpensPlaylist() async throws {
        opener.installedSchemes = ["brave"]
        let result = try await makeService().openYouTubePlaylist(id: "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
        XCTAssertEqual(result.openedWith, .brave)
        XCTAssertTrue(result.url.absoluteString.contains("playlist%3Flist%3DPLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"))
    }

    func testDestinationDescription() async {
        XCTAssertTrue(makeService().destinationDescription().contains("Brave not detected"))
        opener.installedSchemes = ["brave"]
        XCTAssertEqual(makeService().destinationDescription(), "Opens in Brave")
        preference = .systemDefault
        XCTAssertEqual(makeService().destinationDescription(), "Opens in your default browser")
    }
}
