import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

final class WakeWordTests: XCTestCase {
    private func event(_ text: String) -> WakeWordDetector.Event? {
        var detector = WakeWordDetector()
        return detector.feed(text, isFinal: true)
    }

    func testTheWakeWordAloneWakesHalo() {
        XCTAssertEqual(event("Halo"), .wake)
        XCTAssertEqual(event("Hey Halo"), .wake)
        XCTAssertEqual(event("హలో"), .wake)
        XCTAssertEqual(event("um, okay halo"), .wake)
    }

    func testTheWakeWordWithACommandIsTheCommand() {
        XCTAssertEqual(event("Halo play some Telugu songs"), .command("play some telugu songs"))
        XCTAssertEqual(event("hey halo, skip"), .command("skip"))
        XCTAssertEqual(event("హలో తెలుగు పాటలు పెట్టు"), .command("తెలుగు పాటలు పెట్టు"))
        // The last wake word starts the command ("Halo… no wait, Halo next").
        XCTAssertEqual(event("halo no wait halo next"), .command("next"))
    }

    func testOrdinaryTalkNeverWakesHalo() {
        XCTAssertNil(event("hello how are you"))
        XCTAssertNil(event("the halogen lamp"))
        XCTAssertNil(event("play some telugu songs"))
        XCTAssertNil(event(""))
    }

    func testOnlyFinalTranscriptsFireAndOnlyOnce() {
        var detector = WakeWordDetector()
        XCTAssertNil(detector.feed("halo play", isFinal: false))
        XCTAssertTrue(WakeWordDetector.heardWakeWord("halo play"))
        XCTAssertEqual(detector.feed("halo play telugu songs", isFinal: true), .command("play telugu songs"))
        XCTAssertEqual(detector.feed("halo", isFinal: true), .wake)  // the next utterance is new
    }
}
