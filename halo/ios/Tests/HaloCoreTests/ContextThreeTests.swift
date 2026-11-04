import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Development tests for the follow-up fixes after holdout v2 (new phrasings, by principle).
final class ContextThreeTests: XCTestCase {
    private func ops(_ text: String) -> [String] {
        IntentInterpreter.interpret(text).delta.operations.map(\.wire).sorted()
    }

    private func decision(_ text: String) -> IntentDecision { IntentInterpreter.interpret(text) }

    // Recognized names are known words: clean requests don't ask for confirmation.
    func testResolvedNamesAreEvidenceNotDoubt() {
        for text in ["Play Gopi Sundar", "Play some Shreya Ghoshal", "Put on Harris Jayaraj", "Play The Weeknd"] {
            XCTAssertEqual(decision(text).outcome, .execute, text)
        }
        // An unknown name still counts against confidence (but a strong pattern may act).
        XCTAssertLessThan(decision("Play Zorblax Quintrell").evidence, decision("Play Mani Sharma").evidence)
    }

    // Prefix matching: a word that merely starts like a command word isn't that word.
    func testFalsePrefixesDontMatch() {
        XCTAssertEqual(decision("Tell me the news").outcome, .unsupported)
        XCTAssertEqual(ops("Play classical music"), ["play:genre:classical"])
        XCTAssertTrue(ops("A massive party playlist").contains("set:energy:0.85"))
        XCTAssertEqual(ops("Play newer stuff"), ["newer"])  // real suffixes still match
    }

    // Asking what's next is a question, never a skip.
    func testQuestionsAboutNextAreQuestions() {
        for text in ["What's playing next?", "What comes next?", "Which song plays after this?",
                     "Tarvata emi vastundi?", "Next e paata?", "తర్వాత ఏమి వస్తుంది?"] {
            XCTAssertEqual(ops(text), ["ask:upNext"], text)
        }
        XCTAssertEqual(ops("Next song"), ["transport:next"])
    }

    // Telugu forms: adjectives, release verbs and "old" variants are words, not names.
    func testMoreTeluguForms() {
        XCTAssertEqual(ops("హుషారైన పాటలు వినిపించు"), ["play", "set:energy:0.85"])
        XCTAssertEqual(ops("Ee month vachina paatalu pettu"), ["play", "recency:days:30"])
        XCTAssertEqual(ops("ఈ వారం విడుదలైన పాటలు పెట్టు"), ["play", "recency:days:7"])
        XCTAssertEqual(ops("Purana Telugu paatalu vinipinchu"), ["lang:only:te", "play", "recency:classics"])
        XCTAssertEqual(ops("Hushaaruga unna songs pettandi"), ["play", "set:energy:0.85"])
    }

    // Known names are found in any phrasing; shared names always ask.
    func testNamesInAnyPhrasing() {
        XCTAssertEqual(ops("I feel like some Keeravani"), ["play:artist:M. M. Keeravani"])
        XCTAssertEqual(ops("Can I hear Anurag Kulkarni"), ["play:artist:Anurag Kulkarni"])
        XCTAssertEqual(ops("Mickey J Meyer songs pettu"), ["play:artist:Mickey J. Meyer"])
        for text in ["Something by Raja please", "Raja music vinipinchu", "రాజా సంగీతం కావాలి", "Raja vi konni pettu"] {
            let d = decision(text)
            XCTAssertEqual(d.outcome, .clarify, text)
            guard case .ambiguousEntity = d.reason else { return XCTFail("\(text) → \(d.reason)") }
        }
    }

    // Follow-ups without a name point at the artist named last.
    func testNamelessFollowUps() {
        for text in ["Not too many though", "Kaani ekkuva vaddu", "Less of them please", "కానీ ఎక్కువ వద్దు"] {
            XCTAssertEqual(ops(text), ["weight:last:-0.60"], text)
        }
        var state = SessionState()
        for turn in ["Play some Gopi Sundar songs", "Not too many though"] {
            let d = decision(turn)
            if d.outcome == .execute { state.apply(d.delta, current: nil) }
        }
        XCTAssertEqual(state.artistWeights["gopi sundar"], -0.6)
    }

    // Colloquial particles are never names.
    func testParticlesAreNotNames() {
        XCTAssertEqual(ops("Not too much ra"), ["weight:last:-0.60"])
        XCTAssertEqual(ops("Sad songs asalu vaddu"), ["avoid:sad"])
        XCTAssertEqual(ops("Chithra gaari paatalu vinipinchandi"), ["play:artist:K. S. Chithra"])
        XCTAssertEqual(ops("Yuvan paatalu pettandi yaar"), ["play:artist:Yuvan Shankar Raja"])
    }
}
