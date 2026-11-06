import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Negation, written by principle (new phrasings, not taken from any holdout). The one rule
/// above all: a negated request must never produce the opposite action, and must never fall
/// back to a player control.
final class NegationTests: XCTestCase {
    private func ops(_ text: String) -> [String] {
        IntentInterpreter.interpret(text).delta.operations.map(\.wire).sorted()
    }

    private func decision(_ text: String) -> IntentDecision { IntentInterpreter.interpret(text) }

    /// Positive operations that would be the opposite of any "don't …" request.
    private func positive(_ op: String) -> Bool {
        op.hasPrefix("weight:") && op.contains(":+") || op == "transport:resume" || op == "rate:like"
            || op == "set:valence:0.25" || op.hasPrefix("play:artist:") || op.hasPrefix("play:any:")
    }

    // 1. English cues, in any position and with intensifiers.
    func testIntensifiedEnglishNegationsAreNegative() {
        XCTAssertEqual(ops("Please don't ever put this artist on again"), ["exclude:current:profile"])
        XCTAssertEqual(ops("Do not play this singer"), ["exclude:current:session"])
        XCTAssertEqual(ops("I never want to hear this singer today"), ["exclude:current:today"])
        XCTAssertEqual(ops("Never, ever put this song on again"), ["rate:neverAgain"])
        XCTAssertEqual(ops("Do not play this track anymore"), ["exclude:currentTrack:session"])
        XCTAssertEqual(ops("Keep the gloomy songs away"), ["avoid:sad"])
        XCTAssertEqual(ops("Avoid sad music"), ["avoid:sad"])
        XCTAssertEqual(ops("Enough of the sad songs"), ["avoid:sad"])
        XCTAssertEqual(ops("Don't play Keeravani"), ["exclude:M. M. Keeravani:session"])
    }

    // 2. Telugu negative imperatives (-aku / -akandi) and polite "don't want".
    func testTeluguNegativeImperatives() {
        XCTAssertEqual(ops("Ee singer ni inka vinipinchaku"), ["exclude:current:session"])
        XCTAssertEqual(ops("Ee artist paatalu pettakandi"), ["exclude:current:session"])
        XCTAssertEqual(ops("Ee paata vaddandi"), ["exclude:currentTrack:session"])
        XCTAssertEqual(ops("Ee track oddu"), ["exclude:currentTrack:session"])
        XCTAssertEqual(ops("ఈ పాట ఇంకెప్పుడూ పెట్టకండి"), ["rate:neverAgain"])
        XCTAssertEqual(ops("ఈ సింగర్ పాటలు వినిపించకు"), ["exclude:current:session"])
        XCTAssertEqual(ops("Sad paatalu asalu pettaku"), ["avoid:sad"])
    }

    // 3. "Less of X" said with a negation keeps the artist, just less often.
    func testTooMuchWithNegationDownweights() {
        XCTAssertEqual(ops("Mani Sharma paatalu ekkuva pettaku"), ["weight:Mani Sharma:-0.60"])
        XCTAssertEqual(ops("Sid Sriram ni too much vinipinchaku"), ["weight:Sid Sriram:-0.60"])
        XCTAssertEqual(ops("Don't play too much Chitra"), ["weight:K. S. Chithra:-0.60"])
    }

    // 4. A negated language picks the other one; it never mixes them.
    func testNegatedLanguages() {
        XCTAssertEqual(ops("Play Telugu songs, not English"), ["lang:only:te", "play"])
        XCTAssertEqual(ops("No English songs please"), ["lang:only:te"])
        XCTAssertEqual(ops("English vaddu, Telugu pettu"), ["lang:only:te", "play"])
    }

    // 5. Things that look negative but aren't.
    func testFalseNegations() {
        // Accepting a mood sets it without starting music (decided 2026-11-06).
        XCTAssertEqual(ops("I don't mind sad songs"), ["set:valence:0.25"])
        XCTAssertEqual(ops("No, play happy songs"), ["play", "set:valence:0.80"])
        XCTAssertEqual(ops("Sad songs parledu"), ["set:valence:0.25"])
        XCTAssertEqual(decision("Don't stop the music").reason, .negatedControl)
        XCTAssertEqual(decision("Next song pettaku").reason, .negatedControl)
    }

    // 6. Safety: a negated sentence never resumes, skips or plays more of what was refused.
    func testNegatedSentencesNeverProduceTheOppositeAction() {
        let refusals = [
            "Don't ever play this singer again", "Never ever play this track", "Ee singer ni malli vinipinchaku",
            "Please do not put this artist on", "Don't you dare play this song again", "Never this singer",
            "Ee paata inkeppudu pettaku", "No more of this artist", "Not this artist please",
            "This singer vaddandi", "Ee singer oddu", "Stop playing this singer", "I don't want this song",
            "ఈ గాయకుడి పాటలు పెట్టకండి", "Don't play sad songs anymore", "Never sad songs",
        ]
        for text in refusals {
            let d = decision(text)
            let wires = d.delta.operations.map(\.wire)
            if d.outcome == .execute {
                XCTAssertFalse(wires.contains(where: positive), "\(text) → \(wires)")
            }
            XCTAssertFalse(wires.contains("transport:resume"), text)
            XCTAssertFalse(wires.contains("transport:next") && !text.lowercased().contains("skip"), text)
        }
    }

    // 7. Negation stays inside its clause.
    func testNegationScope() {
        XCTAssertEqual(ops("Play energetic Telugu songs but no Anirudh"),
                       ["exclude:Anirudh Ravichander:session", "lang:only:te", "play", "set:energy:0.85"])
        XCTAssertEqual(ops("Konchem calm ga pettu, sad songs vaddu"), ["adjust:energy:-0.12", "avoid:sad"])
    }

    // 8. "Skip" aimed at an artist, and "enough" (chalu / చాలు), refuse.
    func testSkipArtistAndEnoughRefuse() {
        XCTAssertEqual(ops("Skip this singer today"), ["exclude:current:today"])
        XCTAssertEqual(ops("Skip that artist"), ["exclude:current:session"])
        XCTAssertEqual(ops("Sad paatalu chalu ika"), ["avoid:sad"])
        XCTAssertEqual(ops("బాధ పాటలు చాలు"), ["avoid:sad"])
        XCTAssertEqual(ops("Skip"), ["transport:next"])  // skipping a song is still a control
    }
}
