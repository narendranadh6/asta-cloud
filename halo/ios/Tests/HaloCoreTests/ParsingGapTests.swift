import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Development tests for the parsing gaps holdout v4 found (new phrasings, by principle).
final class ParsingGapTests: XCTestCase {
    private func ops(_ text: String) -> [String] {
        IntentInterpreter.interpret(text).delta.operations.map(\.wire).sorted()
    }

    private func decision(_ text: String) -> IntentDecision { IntentInterpreter.interpret(text) }

    // Preferring a language without "only" favors it; a refused one in a two-language sentence
    // leaves the other.
    func testLanguagePreferences() {
        XCTAssertEqual(ops("I'd prefer Telugu songs"), ["favor:te"])
        XCTAssertEqual(ops("Give English some priority"), ["favor:en"])
        XCTAssertEqual(ops("Telugu ki ekkuva priority ivvu"), ["favor:te"])
        XCTAssertEqual(ops("Telugu lo kaadu, English songs pettu"), ["lang:only:en", "play"])
        XCTAssertEqual(ops("English chalu, Telugu songs vinipinchu"), ["lang:only:te", "play"])
    }

    // Relative dates: "releases" are songs, praise words aren't names, "came out" isn't a question.
    func testRelativeDates() {
        XCTAssertEqual(ops("New releases from this week please"), ["play", "recency:days:7"])
        XCTAssertEqual(ops("Play the top tracks of this month"), ["play", "recency:days:30"])
        XCTAssertEqual(ops("Ee nela vachina hit paatalu pettu"), ["play", "recency:days:30"])
        XCTAssertEqual(ops("Put on what came out yesterday"), ["play", "recency:days:1"])
        XCTAssertEqual(ops("When did this come out?"), ["ask:whenReleased"])
    }

    // Transport phrasings.
    func testTransportPhrasings() {
        XCTAssertEqual(ops("Play this one again from the top"), ["transport:restart"])
        XCTAssertEqual(ops("Start the track over"), ["transport:restart"])
        XCTAssertEqual(ops("Modati nunchi vinipinchu"), ["transport:restart"])
        XCTAssertEqual(ops("Take the upcoming one off the queue"), ["transport:removeNext"])
        XCTAssertEqual(ops("Mundu paata malli pettu"), ["transport:previous"])
        XCTAssertEqual(ops("The song before this, please"), ["transport:previous"])
    }

    // "Malli eppudu … -aku" / "మళ్ళీ ఎప్పుడూ … పెట్టకు" is never.
    func testTeluguNever() {
        XCTAssertEqual(ops("Ee track malli eppudu pettakandi"), ["rate:neverAgain"])
        XCTAssertEqual(ops("ఈ పాటను ఎప్పుడూ వినిపించకు"), ["rate:neverAgain"])
        XCTAssertEqual(ops("Ee singer ni eppudu pettaku"), ["exclude:current:profile"])
        XCTAssertEqual(ops("Ee paata eppudu vachindi?"), ["ask:whenReleased"])  // "eppudu" = when
    }

    // Incomplete requests made of fillers, a verb and nothing else.
    func testIncompleteFillers() {
        for (text, slot) in [("Adi... ante... pettu", IntentDecision.Slot.something),
                             ("Play cheyyi... umm... adi", .something),
                             ("Could I hear some", .something),
                             ("Language ni... adi... ki marchu", .language),
                             ("That movie songs, name gurthu ledu", .film),
                             ("ఆ సినిమా పాటలు... పేరు గుర్తు లేదు", .film),
                             ("Don't play, ante...", .artist)] {
            XCTAssertEqual(decision(text).reason, .incomplete(slot), text)
        }
        XCTAssertEqual(ops("Play"), ["transport:resume"])  // a bare "play" still resumes
    }
}
