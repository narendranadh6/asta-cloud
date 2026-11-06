import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Development tests for the weak areas holdout v3 found (new phrasings, by principle; no
/// holdout item is copied here).
final class WeakAreaTests: XCTestCase {
    private func ops(_ text: String) -> [String] {
        IntentInterpreter.interpret(text).delta.operations.map(\.wire).sorted()
    }

    private func decision(_ text: String) -> IntentDecision { IntentInterpreter.interpret(text) }

    // Acceptances and restrictions change the session; bare requests still play.
    func testWhenSongsMeansPlay() {
        XCTAssertEqual(ops("Happy songs are fine too"), ["set:valence:0.80"])
        XCTAssertEqual(ops("Melody songs aina parledu"), ["set:energy:0.20"])
        XCTAssertEqual(ops("English songs matrame"), ["lang:only:en"])
        XCTAssertEqual(ops("Only Telugu from now on"), ["lang:only:te"])
        XCTAssertEqual(ops("Some peaceful Telugu songs"), ["lang:only:te", "play", "set:energy:0.20"])
        XCTAssertEqual(ops("English songs matrame pettu"), ["lang:only:en", "play"])
    }

    // Double negatives and "keep it" acceptances.
    func testDoubleNegativesKeep() {
        XCTAssertEqual(ops("Not bad at all, keep it"), ["rate:keep"])
        XCTAssertEqual(ops("Idi bagane undi"), ["rate:keep"])
        XCTAssertEqual(ops("ఇది బాగానే ఉంది"), ["rate:keep"])
        XCTAssertEqual(ops("I wouldn't mind some old songs"), ["recency:classics"])
    }

    // A leading "no," / "kaadu," is an interjection, not part of the request or a name.
    func testLeadingInterjections() {
        XCTAssertEqual(ops("Kaadu, Gopi Sundar songs pettu"), ["play:artist:Gopi Sundar"])
        XCTAssertEqual(ops("కాదు కాదు, మెలోడీ పాటలు పెట్టు"), ["play", "set:energy:0.20"])
        XCTAssertEqual(ops("Nah, play something energetic"), ["play", "set:energy:0.85"])
        XCTAssertEqual(ops("No no, the previous one"), ["transport:previous"])
    }

    // Incomplete requests ask, even with fillers after them.
    func testIncompleteWithFillers() {
        for (text, slot) in [("Play songs from the movie... hmm", IntentDecision.Slot.film),
                             ("Could you put on, uh", .something),
                             ("Switch the language to... umm", .language),
                             ("Language marchu", .language), ("భాష మార్చండి", .language),
                             ("Vinipinchaku", .artist), ("Don't put on... aa", .artist)] {
            XCTAssertEqual(decision(text).reason, .incomplete(slot), text)
        }
    }

    // "Their" refers to the artist named last; undo has many phrasings.
    func testFollowUpsAndUndo() {
        for text in ["Vaalla songs takkuva cheyyi", "Their songs, not so many", "వాళ్ళ పాటలు ఎక్కువ పెట్టకు",
                     "Vaallavi konchem takkuva pettu"] {
            XCTAssertEqual(ops(text), ["weight:last:-0.60"], text)
        }
        for text in ["Put it back the way it was", "Revert that", "Mundu laaga cheyyi", "Paatha settings ki vellu",
                     "అంతకు ముందు లాగా చెయ్యి", "Take that back"] {
            XCTAssertEqual(ops(text), ["undo"], text)
        }
        XCTAssertEqual(ops("Go back"), ["transport:previous"])  // a bare "go back" is still the previous song
    }

    // Telugu tempo and multi-word Telugu-script names.
    func testTeluguTempoAndNames() {
        XCTAssertEqual(ops("వేగంగా ఉండే బీట్ పాటలు పెట్టు"), ["play", "set:energy:0.85", "set:tempo:0.80"])
        XCTAssertEqual(ops("Beat ekkuvaga unna paatalu vinipinchu"), ["play", "set:energy:0.85", "set:tempo:0.80"])
        XCTAssertEqual(ops("నెమ్మదైన పాటలు పెట్టు"), ["play", "set:energy:0.20"])
        XCTAssertEqual(ops("ఈరోజు దేవి శ్రీ ప్రసాద్ పాటలు వద్దు"), ["exclude:Devi Sri Prasad:today"])
        XCTAssertEqual(ops("Mani Sharma ni inkeppudu pettakandi"), ["exclude:Mani Sharma:profile"])
        XCTAssertEqual(ops("Never put on Sid Sriram again"), ["exclude:Sid Sriram:profile"])
    }
}
