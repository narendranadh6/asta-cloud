import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Development tests for Context 2.0 (written from the milestone's examples and from the
/// failure principles; the frozen holdout-v2 set is not used here).
final class ContextTwoParsingTests: XCTestCase {
    private func ops(_ text: String) -> [String] {
        IntentInterpreter.interpret(text).delta.operations.map(\.wire).sorted()
    }

    private func outcome(_ text: String) -> IntentDecision.Outcome {
        IntentInterpreter.interpret(text).outcome
    }

    func testMilestoneExamples() {
        XCTAssertEqual(ops("Ee song vaddu"), ["exclude:currentTrack:session"])
        XCTAssertEqual(ops("Konchem energetic songs pettu"), ["adjust:energy:+0.12"])
        XCTAssertEqual(ops("Anirudh songs ekkuva vaddu"), ["weight:Anirudh Ravichander:-0.60"])
        XCTAssertEqual(ops("Sad songs vaddu"), ["avoid:sad"])
        XCTAssertEqual(ops("Kotha Telugu songs pettu"), ["lang:only:te", "play", "recency:days:90"])
        XCTAssertEqual(ops("Same vibe lo vere songs"), ["play", "preserve:vibe"])
        XCTAssertEqual(ops("Fast beat unna songs kavali"), ["play", "set:energy:0.85", "set:tempo:0.80"])
        XCTAssertEqual(ops("Ee artist malli vaddu"), ["exclude:current:session"])
        XCTAssertEqual(ops("Oka manchi melody pettu"), ["play", "set:energy:0.20"])
        XCTAssertEqual(ops("Ninna release aina songs"), ["play", "recency:days:1"])
    }

    func testUnrelatedRequestsNeverTouchTheMusic() {
        for text in ["Call my friend", "Set an alarm for 6", "What's the weather?", "Open WhatsApp",
                     "Amma ki call cheyyi", "Alarm pettu 7 ki", "Office ki route chupinchu",
                     "ఈరోజు వాతావరణం ఎలా ఉంది", "Show me the lyrics", "Send a message to Ravi"] {
            let decision = IntentInterpreter.interpret(text)
            XCTAssertEqual(decision.outcome, .unsupported, text)
            XCTAssertTrue(decision.delta.isEmpty, text)
        }
        XCTAssertEqual(outcome("Play Tamil songs"), .unsupported)
    }

    func testNothingToDo() {
        for text in ["uh", "hmm okay", "never mind", "forget it", "Don't skip", "skip cheyyaku",
                     "aapakandi", "ఏమీ లేదు", "no"] {
            XCTAssertEqual(outcome(text), .noAction, text)
        }
        XCTAssertEqual(IntentInterpreter.interpret("Don't skip").reason, .negatedControl)
        XCTAssertEqual(IntentInterpreter.interpret("qwerty zxcv").reason, .notUnderstood)
    }

    func testIncompleteAndAmbiguousRequestsAsk() {
        XCTAssertEqual(IntentInterpreter.interpret("Play songs by").reason, .incomplete(.artist))
        XCTAssertEqual(IntentInterpreter.interpret("Set the language to").reason, .incomplete(.language))
        XCTAssertEqual(IntentInterpreter.interpret("Don't play").reason, .incomplete(.artist))
        let raja = IntentInterpreter.interpret("Raja songs pettu")
        XCTAssertEqual(raja.outcome, .clarify)
        XCTAssertEqual(raja.reason, .ambiguousEntity(said: "raja", options: ["Ilaiyaraaja", "Yuvan Shankar Raja"]))
    }

    func testCommonWordsNeverBecomeNames() {
        XCTAssertEqual(ops("Play romantic songs for the drive"), ["play", "set:energy:0.40", "set:valence:0.65"])
        XCTAssertEqual(ops("Play the latest releases"), ["play", "recency:days:90"])
        XCTAssertEqual(ops("Too much Thaman lately"), ["weight:S. Thaman:-0.60"])
        XCTAssertEqual(ops("Devisri kuda vaddu"), ["exclude:Devi Sri Prasad:session"])
        XCTAssertEqual(ops("No Anirudh today"), ["exclude:Anirudh Ravichander:today"])
        XCTAssertEqual(ops("Actually, no Thaman today"), ["exclude:S. Thaman:today"])
    }

    func testTeluguScriptVocabulary() {
        XCTAssertEqual(ops("ప్రశాంతమైన పాటలు పెట్టు"), ["play", "set:energy:0.20"])
        XCTAssertEqual(ops("సంతోషంగా ఉండే పాటలు పెట్టు"), ["play", "set:valence:0.80"])
        XCTAssertEqual(ops("తొంభైల పాటలు పెట్టు"), ["play", "recency:decade:1990"])
        XCTAssertEqual(ops("ఈ గాయకుడు వద్దు"), ["exclude:current:session"])
        XCTAssertEqual(ops("విషాద పాటలు వద్దు"), ["avoid:sad"])
        XCTAssertEqual(ops("ఈ పాట ఎప్పుడు విడుదలైంది"), ["ask:whenReleased"])
        XCTAssertEqual(ops("నిన్న విడుదలైన పాటలు"), ["play", "recency:days:1"])
    }

    func testQuestionsInOtherWords() {
        XCTAssertEqual(ops("When did this song come out?"), ["ask:whenReleased"])
        XCTAssertEqual(ops("What's coming up next?"), ["ask:upNext"])
        XCTAssertEqual(ops("Ee song evaru paadaru"), ["ask:whoIsSinging"])
        XCTAssertEqual(ops("Ee song e album lodi"), ["ask:whatAlbum"])
    }

    func testEntitiesOfEveryKind() {
        XCTAssertEqual(ops("Play some jazz"), ["play:genre:jazz"])
        XCTAssertEqual(ops("Devotional songs pettu"), ["play:genre:devotional"])
        XCTAssertEqual(ops("Play the song Samajavaragamana"), ["play:song:samajavaragamana"])
        XCTAssertEqual(ops("Play the album Folklore"), ["play:album:folklore"])
        XCTAssertEqual(ops("RRR songs pettu"), ["play:soundtrack:RRR"])
        XCTAssertEqual(ops("Songs from Pushpa"), ["play:soundtrack:Pushpa"])
    }

    func testNegationScopes() {
        XCTAssertEqual(ops("Never play this artist again"), ["exclude:current:profile"])
        XCTAssertEqual(ops("Not this song"), ["exclude:currentTrack:session"])
        XCTAssertEqual(ops("Don't play this singer today"), ["exclude:current:today"])
        // Lasting changes need high confidence; a garbled one asks first.
        let lasting = IntentInterpreter.interpret("Never play this artist again", recognizerConfidence: 0.4)
        XCTAssertEqual(lasting.outcome, .clarify)
        XCTAssertEqual(lasting.reason, .lowConfidence)
    }

    func testWireFormRoundTripsAndRejectsUnknownText() {
        for wire in ["play", "play:artist:S. Thaman", "set:energy:0.85", "adjust:valence:-0.20",
                     "lang:mostly:te+en", "recency:days:1", "exclude:currentTrack:session",
                     "weight:last:-0.60", "avoid:sad", "ask:upNext", "undo", "play:genre:jazz"] {
            XCTAssertEqual(SessionOperation(wire: wire)?.wire, wire, wire)
        }
        for bad in ["play:artist:", "set:energy:3", "lang:only:ta", "delete:everything", "transport:format",
                    "recency:decade:1995", "exclude:x:forever", String(repeating: "a", count: 200)] {
            XCTAssertNil(SessionOperation(wire: bad), bad)
        }
    }
}

/// Multi-turn context: follow-ups change only what they name; clarifications don't lose state.
final class ContextTwoConversationTests: XCTestCase {
    private func run(_ turns: [String], current: NowPlayingContext? = nil,
                     now: Date = Date(timeIntervalSince1970: 1_793_000_000),
                     timeZone: TimeZone = TimeZone(identifier: "Asia/Kolkata")!) -> SessionState {
        var state = SessionState(startedAt: now)
        for turn in turns {
            let decision = IntentInterpreter.interpret(turn)
            if decision.outcome == .execute { state.apply(decision.delta, current: current, now: now, timeZone: timeZone) }
        }
        return state
    }

    func testTheMilestoneConversation() {
        let state = run(["Play energetic Telugu songs", "Make them newer", "Less Anirudh",
                         "Same vibe, but English", "Actually, go back to Telugu", "No sad songs"])
        XCTAssertEqual(state.language, .only(.telugu))
        XCTAssertEqual(state.vibe[.energy]?.value, 0.85)
        XCTAssertEqual(state.recency, Recency.any.newer)
        XCTAssertEqual(state.artistWeights["anirudh ravichander"], -0.6)
        XCTAssertEqual(state.avoidedMoods, [.sad])
        var undone = state
        XCTAssertTrue(undone.undo())
        XCTAssertTrue(undone.avoidedMoods.isEmpty)
        XCTAssertEqual(undone.language, .only(.telugu))
    }

    func testThamanNotTooMuchThenNotTodayThenUndo() {
        let turns = ["Play some Thaman songs", "Not too much", "Actually, no Thaman today"]
        let state = run(turns)
        XCTAssertEqual(state.artistWeights["s thaman"], -0.6)  // reduced, not excluded, by "not too much"
        XCTAssertEqual(state.excludedArtists["s thaman"], .today)
        XCTAssertNotNil(state.todayExpiry["s thaman"])
        var undone = state
        XCTAssertTrue(undone.undo())
        XCTAssertNil(undone.excludedArtists["s thaman"])
        XCTAssertEqual(undone.artistWeights["s thaman"], -0.6)
    }

    func testClarificationsAndUnsupportedTurnsChangeNothing() {
        let before = run(["Play calm Telugu songs"])
        let after = run(["Play calm Telugu songs", "Raja songs pettu", "Call my friend", "uh", "Play songs by"])
        XCTAssertEqual(after, before)
    }

    func testRepeatedCommandsAccumulateAndClamp() {
        let state = run(Array(repeating: "More energy", count: 6))
        XCTAssertEqual(state.vibe[.energy]?.value, 1.0)
    }
}

final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_793_000_000)
}

@MainActor
final class DriveDecisionTests: XCTestCase {
    private func makeDrive(clock: TestClock = TestClock()) -> (DriveSession, PlayerController, FakeEngine, RecordingSpeaker) {
        let engine = FakeEngine()
        let player = PlayerController(engine: engine)
        let speaker = RecordingSpeaker()
        let drive = DriveSession(api: FakeMusicAPI(), player: player, speaker: speaker,
                                 now: { clock.now }, timeZone: { TimeZone(identifier: "Asia/Kolkata")! })
        drive.start()
        return (drive, player, engine, speaker)
    }

    func testUnsupportedRequestsChangeNothingAndSaySo() async {
        let (drive, player, engine, speaker) = makeDrive()
        await drive.handle("Play energetic Telugu songs")
        engine.startPlaying()
        let before = (drive.state, player.currentTrack?.id, engine.calls.count)
        await drive.handle("Call my friend")
        XCTAssertEqual(drive.lastDecision?.outcome, .unsupported)
        XCTAssertEqual(speaker.said.last, "I can only help with music.")
        XCTAssertEqual(drive.state, before.0)
        XCTAssertEqual(player.currentTrack?.id, before.1)
        XCTAssertEqual(engine.calls.count, before.2)  // no resume, no pause, nothing
        await drive.handle("Don't skip")
        XCTAssertEqual(player.currentTrack?.id, before.1)
    }

    func testIncompleteRequestsAreCompletedByTheAnswer() async {
        let (drive, _, _, speaker) = makeDrive()
        await drive.handle("Don't play")
        XCTAssertEqual(speaker.said.last, "Which artist?")
        await drive.handle("Thaman")
        XCTAssertEqual(drive.state.excludedArtists["s thaman"], .session)
    }

    func testLowConfidenceSessionChangesAskAndKeepTheSession() async {
        let (drive, _, _, speaker) = makeDrive()
        await drive.handle("Play calm Telugu songs")
        let before = drive.state
        await drive.handle("More energy", confidence: 0.1)  // the recognizer barely heard it
        XCTAssertEqual(drive.lastDecision?.outcome, .clarify)
        XCTAssertEqual(speaker.said.last, "More energy?")
        XCTAssertEqual(drive.state, before)
        await drive.handle("yes")
        XCTAssertEqual(drive.state.vibe[.energy]?.value ?? 0, 0.4, accuracy: 0.001)
    }

    func testRecognitionFailureSaysSoAndChangesNothing() async {
        let (drive, _, _, speaker) = makeDrive()
        await drive.handle("Play calm Telugu songs")
        let before = drive.state
        await drive.recognitionFailed()
        XCTAssertEqual(drive.lastDecision?.reason, .recognitionFailed)
        XCTAssertEqual(speaker.said.last, "Didn't catch that.")
        XCTAssertEqual(drive.state, before)
        await drive.handleTyped("No sad songs")  // typing works the same as speaking
        XCTAssertEqual(drive.state.avoidedMoods, [.sad])
    }

    func testIdleSessionsExpireButTodayExclusionsStay() async {
        let clock = TestClock()
        let (drive, _, _, _) = makeDrive(clock: clock)
        await drive.handle("Play energetic Telugu songs")
        await drive.handle("No Thaman today")
        clock.now = clock.now.addingTimeInterval(3 * 3600)  // still before Kolkata midnight
        await drive.handle("Newer")
        XCTAssertNil(drive.state.language)  // the old steering expired
        XCTAssertEqual(drive.state.excludedArtists["s thaman"], .today)
    }
}

@MainActor
final class DriveFallbackTests: XCTestCase {
    private func makeDrive(api: FakeMusicAPI, allowed: Bool) -> (DriveSession, RecordingSpeaker) {
        let speaker = RecordingSpeaker()
        let drive = DriveSession(api: api, player: PlayerController(engine: FakeEngine()), speaker: speaker)
        drive.fallbackAllowed = { allowed }
        drive.start()
        return (drive, speaker)
    }

    func testWithoutConsentNothingIsSent() async {
        let api = FakeMusicAPI()
        await api.setFallbackReply(IntentFallbackResponse(outcome: "execute", operations: ["avoid:sad"],
                                                          provider: "fake", latencyMs: 10))
        let (drive, _) = makeDrive(api: api, allowed: false)
        await drive.handle("qwerty zxcv")
        let sent = await api.fallbackRequests.count
        XCTAssertEqual(sent, 0)
        XCTAssertEqual(drive.lastDecision?.outcome, .noAction)
    }

    func testValidatedSessionChangesApplyThroughTheReducer() async {
        let api = FakeMusicAPI()
        await api.setFallbackReply(IntentFallbackResponse(outcome: "execute", operations: ["avoid:sad"],
                                                          provider: "fake", latencyMs: 10))
        let (drive, _) = makeDrive(api: api, allowed: true)
        await drive.handle("dukhapu paatalu oddhu")
        XCTAssertEqual(drive.state.avoidedMoods, [.sad])
        let sent = await api.fallbackRequests
        XCTAssertEqual(sent.first?.transcript, "dukhapu paatalu oddhu")
        XCTAssertEqual(sent.first?.consent, true)
        var state = drive.state
        XCTAssertTrue(state.undo())  // undo works for fallback changes too
    }

    func testInvalidOrLastingFallbackResultsDoNotActOnTheirOwn() async {
        let api = FakeMusicAPI()
        await api.setFallbackReply(IntentFallbackResponse(outcome: "execute", operations: ["avoid:sad", "format:disk"],
                                                          provider: "fake", latencyMs: 10))
        let (drive, _) = makeDrive(api: api, allowed: true)
        let before = drive.state
        await drive.handle("qwerty zxcv")
        XCTAssertEqual(drive.state, before)  // one invalid string: the whole answer is ignored
        await api.setFallbackReply(IntentFallbackResponse(outcome: "execute", operations: ["exclude:current:profile"],
                                                          provider: "fake", latencyMs: 10))
        await drive.handle("qwerty zxcv")
        XCTAssertEqual(drive.lastDecision?.outcome, .clarify)  // lasting: asks first
        XCTAssertEqual(drive.state, before)
    }

    func testAnUnreachableServerLeavesTheSessionAlone() async {
        let api = FakeMusicAPI()
        await api.setFailure(.offline)
        let (drive, speaker) = makeDrive(api: api, allowed: true)
        await drive.handle("qwerty zxcv")
        XCTAssertEqual(drive.lastDecision?.reason, .notUnderstood)
        XCTAssertEqual(speaker.said.last, "Didn't catch that.")
    }
}
