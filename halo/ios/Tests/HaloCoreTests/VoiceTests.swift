import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Halo Drive's phase-1 test matrix: English, Telugu script, romanized Telugu and mixed speech,
/// asking for Telugu or English music, with follow-ups.
final class IntentParserTests: XCTestCase {
    private func ops(_ text: String) -> [SessionOperation] { IntentParser.parse(text).operations }

    private func assertHas(_ text: String, _ expected: SessionOperation..., file: StaticString = #filePath,
                           line: UInt = #line) {
        let parsed = ops(text)
        for op in expected {
            XCTAssertTrue(parsed.contains(op), "\"\(text)\" → \(parsed), missing \(op)", file: file, line: line)
        }
    }

    // MARK: English

    func testEnglishRequestsForTeluguMusic() {
        assertHas("Halo, play some energetic Telugu songs.",
                  .play(.vibe), .setVibe(.energy, 0.85), .setLanguage(.only(.telugu)))
        assertHas("Play new Telugu songs.", .play(.vibe), .setLanguage(.only(.telugu)),
                  .setRecency(.withinDays(90)))
        assertHas("Give me some old Telugu hits.", .setRecency(.classics), .setLanguage(.only(.telugu)))
        assertHas("Relaxing Telugu songs.", .play(.vibe), .setVibe(.energy, 0.2))
        assertHas("Play some energetic Telugu songs from the last few months but don't give me too much Anirudh",
                  .play(.vibe), .setVibe(.energy, 0.85), .setLanguage(.only(.telugu)),
                  .setRecency(.withinDays(120)), .weightArtist(.mention("anirudh", kind: .artist), -0.6))
    }

    func testEnglishMoodAndVibe() {
        assertHas("Play something relaxing.", .play(.vibe), .setVibe(.energy, 0.2))
        assertHas("Make it more energetic.", .adjustVibe(.energy, 0.2))
        assertHas("Something happier.", .adjustVibe(.valence, 0.2))
        assertHas("Don't play sad songs right now.", .setVibe(.valence, 0.65))
        assertHas("I'm stressed, play something relaxing", .setVibe(.energy, 0.2))
        assertHas("Okay, wake me up. Give me something energetic.", .play(.vibe))
        assertHas("Happy English songs.", .setVibe(.valence, 0.8), .setLanguage(.only(.english)))
        assertHas("Calmer.", .adjustVibe(.energy, -0.2))
        XCTAssertFalse(ops("Make it more energetic.").contains(.play(.vibe)))  // a change, not a restart
    }

    func testFollowUpsAreRelative() {
        XCTAssertEqual(ops("Newer."), [.newer])
        XCTAssertEqual(ops("Older music."), [.older])
        XCTAssertEqual(ops("Telugu."), [.setLanguage(.only(.telugu))])
        XCTAssertEqual(ops("Back to Telugu."), [.setLanguage(.only(.telugu))])
        assertHas("Same vibe but English.", .preserve([.vibe]), .setLanguage(.only(.english)))
        XCTAssertFalse(ops("Same vibe but English.").contains(.play(.vibe)))
        assertHas("More like this but slightly calmer.", .play(.similarToCurrent), .adjustVibe(.energy, -0.12))
        assertHas("Keep the same vibe but give me more discovery.", .adjustVibe(.discovery, 0.3))
        XCTAssertFalse(ops("Keep the same vibe but give me more discovery.").contains(.lock))
        assertHas("Keep it energetic but give me older Telugu songs.", .older, .setLanguage(.only(.telugu)))
        assertHas("90s songs.", .setRecency(.decade(1990)))
        assertHas("Songs from this week.", .setRecency(.withinDays(7)))
    }

    func testDiscoveryAndDirection() {
        assertHas("Play something new.", .play(.vibe), .adjustVibe(.discovery, 0.3))
        XCTAssertFalse(ops("Play something new.").contains(.setRecency(.withinDays(90))))
        assertHas("Play something I've never heard.", .adjustVibe(.discovery, 0.3))
        assertHas("Surprise me.", .play(.surprise))
        assertHas("More songs like this.", .play(.similarToCurrent))
        assertHas("Take me somewhere different.", .seedMode(.elsewhere))
        assertHas("Go deeper.", .seedMode(.deeper))
        XCTAssertEqual(ops("Perfect. Keep this vibe."), [.lock])
    }

    func testArtistsAndRatings() {
        XCTAssertEqual(ops("Not this singer."), [.excludeArtist(.currentArtist, .session)])
        XCTAssertEqual(ops("Don't play this artist today."), [.excludeArtist(.currentArtist, .today)])
        assertHas("More from this artist.", .weightArtist(.currentArtist, 0.6))
        assertHas("Less of this artist.", .weightArtist(.currentArtist, -0.6))
        assertHas("Explore this artist.", .play(.entity(.currentArtist)))
        assertHas("Different singer.", .diversifyArtists)
        assertHas("Don't play Anirudh today", .excludeArtist(.mention("anirudh", kind: .artist), .today))
        XCTAssertEqual(ops("I like this."), [.rate(.like)])
        XCTAssertEqual(ops("Add this to my favorites."), [.rate(.like)])
        XCTAssertEqual(ops("Keep this one."), [.rate(.keep)])
        XCTAssertEqual(ops("Yeah, this is good."), [.rate(.keep)])
        XCTAssertEqual(ops("Less like this."), [.rate(.dislike)])
        XCTAssertEqual(ops("Don't recommend this again."), [.rate(.neverAgain)])
        XCTAssertEqual(ops("Play this again later."), [.rate(.later)])
    }

    func testTransportAndQuestions() {
        XCTAssertEqual(ops("Skip."), [.transport(.next)])
        XCTAssertEqual(ops("Go back."), [.transport(.previous)])
        XCTAssertEqual(ops("Pause."), [.transport(.pause)])
        XCTAssertEqual(ops("Play."), [.transport(.resume)])
        XCTAssertEqual(ops("Restart this."), [.transport(.restart)])
        XCTAssertEqual(ops("Remove the next song."), [.transport(.removeNext)])
        XCTAssertEqual(ops("Who is singing this?"), [.ask(.whoIsSinging)])
        XCTAssertEqual(ops("What movie is this from?"), [.ask(.whatMovie)])
        XCTAssertEqual(ops("What album is this?"), [.ask(.whatAlbum)])
        XCTAssertEqual(ops("When was this released?"), [.ask(.whenReleased)])
        XCTAssertEqual(ops("What's coming next?"), [.ask(.upNext)])
        XCTAssertEqual(ops("Undo that."), [.undo])
    }

    // MARK: Telugu, romanized Telugu, mixed

    func testTeluguScriptRomanizedAndMixedMeanTheSame() {
        let forms = ["కొత్త తెలుగు పాటలు పెట్టు", "kotha telugu patalu pettu",
                     "kotha Telugu songs play cheyyi", "New Telugu songs పెట్టు"]
        for form in forms {
            assertHas(form, .play(.vibe), .setLanguage(.only(.telugu)), .setRecency(.withinDays(90)))
        }
        XCTAssertEqual(IntentParser.parse(forms[0]).speech, .telugu)
        XCTAssertEqual(IntentParser.parse(forms[1]).speech, .mixed)
        XCTAssertEqual(IntentParser.parse(forms[3]).speech, .mixed)
        XCTAssertEqual(IntentParser.parse("Play new Telugu songs").speech, .english)
    }

    func testCodeSwitchedCommands() {
        assertHas("HALO, కొత్త songs ఏమైనా play చెయ్యి.", .play(.vibe), .setRecency(.withinDays(90)))
        assertHas("Something energetic పెట్టు.", .play(.vibe), .setVibe(.energy, 0.85))
        XCTAssertEqual(ops("ఈ song నాకు నచ్చలేదు."), [.rate(.dislike)])
        XCTAssertEqual(ops("Next song పెట్టు."), [.transport(.next)])
        XCTAssertEqual(ops("Same vibe maintain చెయ్యి."), [.lock])
        assertHas("కొంచెం slow songs పెట్టు.", .adjustVibe(.energy, -0.12))
        assertHas("Anirudh songs వద్దు.", .excludeArtist(.mention("anirudh", kind: .artist), .session))
        assertHas("English లో similar songs play చెయ్యి.", .setLanguage(.only(.english)), .play(.similarToCurrent))
        assertHas("ఈ movie songs పెట్టు.", .play(.entity(.currentAlbum)))
        assertHas("Yesterday release అయిన Telugu songs ఏమైనా ఉన్నాయా?",
                  .setLanguage(.only(.telugu)), .setRecency(.withinDays(7)))
        assertHas("Gym కి మంచి Telugu playlist పెట్టు.", .play(.vibe), .setVibe(.energy, 0.85),
                  .setLanguage(.only(.telugu)))
        XCTAssertEqual(ops("ఈ singer వద్దు."), [.excludeArtist(.currentArtist, .session)])
        assertHas("కొంచెం energetic songs పెట్టు కానీ Anirudh వద్దు.", .adjustVibe(.energy, 0.12),
                  .excludeArtist(.mention("anirudh", kind: .artist), .session))
        XCTAssertEqual(ops("Telugu ఎక్కువ పెట్టు."), [.favorLanguage(.telugu)])
        XCTAssertEqual(ops("కొంచెం కొత్తవి."), [.newer])
        XCTAssertEqual(ops("English try చేద్దాం."), [.setLanguage(.only(.english))])
        assertHas("నాకు peaceful songs కావాలి", .setVibe(.energy, 0.2))
        assertHas("కొంచెం energy కావాలి", .adjustVibe(.energy, 0.12))
        assertHas("mood change చేద్దాం", .seedMode(.elsewhere))
    }

    func testNamesBecomeMentionsNotGuesses() {
        assertHas("DSP songs పెట్టు.", .play(.entity(.mention("dsp", kind: .any))))
        assertHas("Play songs from Pushpa", .play(.entity(.mention("pushpa", kind: .soundtrack))))
        assertHas("Play Jersey songs.", .play(.entity(.mention("jersey", kind: .any))))
        assertHas("Play songs from this movie.", .play(.entity(.currentAlbum)))
        // Known words never become names.
        XCTAssertFalse(ops("Play energetic Telugu songs").contains { if case .play(.entity) = $0 { true } else { false } })
    }

    func testLanguageMixesAndUnsupportedLanguages() {
        assertHas("Mix Telugu and English.",
                  .setLanguage(LanguagePreference(primary: .telugu, secondary: .english, strategy: .mixed)))
        assertHas("Mostly Telugu but some English.",
                  .setLanguage(LanguagePreference(primary: .telugu, secondary: .english, strategy: .mostly)))
        assertHas("Alternate Telugu and English.",
                  .setLanguage(LanguagePreference(primary: .telugu, secondary: .english, strategy: .alternating)))
        assertHas("Give me Telugu workout songs with a few English tracks.",
                  .setLanguage(LanguagePreference(primary: .telugu, secondary: .english, strategy: .mostly)),
                  .setVibe(.energy, 0.85))
        let tamil = IntentParser.parse("Actually Tamil.")
        XCTAssertTrue(tamil.isEmpty)
        XCTAssertEqual(tamil.unsupportedLanguages, [.tamil])
        XCTAssertEqual(VoiceReply.text(for: tamil), "Tamil is coming soon.")
    }

    func testNonsenseIsNotActedOn() {
        let delta = IntentParser.parse("blorp the wibble")
        XCTAssertTrue(delta.isEmpty)
        XCTAssertEqual(delta.confidence, 0)
        XCTAssertEqual(VoiceReply.text(for: delta), "Didn't catch that.")
    }
}

final class SessionStateTests: XCTestCase {
    private let song = NowPlayingContext(trackID: "audius:t1", artist: "Sid Sriram", album: "Hits")

    private func say(_ text: String, _ state: inout SessionState,
                     current: NowPlayingContext? = nil) -> [SessionEffect] {
        state.apply(IntentParser.parse(text), current: current ?? song)
    }

    /// The example drive from the brief: every change builds on the last.
    func testADriveChangesOneThingAtATime() {
        var state = SessionState()
        XCTAssertEqual(say("Halo, give me something energetic.", &state).first, .startPlaying(.vibe))
        XCTAssertEqual(state.vibe[.energy]?.value, 0.85)

        XCTAssertEqual(say("Telugu.", &state), [.rerank])
        XCTAssertEqual(state.language, .only(.telugu))
        XCTAssertEqual(state.vibe[.energy]?.value, 0.85)  // kept

        _ = say("Newer.", &state)
        XCTAssertEqual(state.recency, .withinDays(365))
        _ = say("Newer.", &state)
        XCTAssertEqual(state.recency, .withinDays(121))

        let effects = say("Not this singer.", &state)
        XCTAssertTrue(effects.contains(.skipCurrent))
        XCTAssertEqual(state.excludedArtists["sid sriram"], .session)

        _ = say("Keep this one.", &state)
        XCTAssertEqual(state.keeps, ["audius:t1"])

        _ = say("More like this but slightly calmer.", &state)
        XCTAssertEqual(state.vibe[.energy]?.value ?? 0, 0.73, accuracy: 0.001)
        XCTAssertEqual(state.language, .only(.telugu))  // still Telugu

        _ = say("Perfect. Keep this vibe.", &state)
        XCTAssertTrue(state.locked)
    }

    func testLanguageSwitchesKeepEverythingElse() {
        var state = SessionState()
        _ = say("Play energetic Telugu songs.", &state)
        _ = say("Make it more energetic.", &state)
        _ = say("Same vibe but English.", &state)
        XCTAssertEqual(state.language, .only(.english))
        XCTAssertEqual(state.vibe[.energy]?.value ?? 0, 1.0, accuracy: 0.001)
        _ = say("Back to Telugu.", &state)
        XCTAssertEqual(state.language, .only(.telugu))
        XCTAssertEqual(state.vibe[.energy]?.value ?? 0, 1.0, accuracy: 0.001)
        _ = say("English try చేద్దాం.", &state)
        _ = say("Telugu ఎక్కువ పెట్టు.", &state)
        XCTAssertEqual(state.language,
                       LanguagePreference(primary: .telugu, secondary: .english, strategy: .mostly))
    }

    func testUndoAndProfileScopedFeedback() {
        var state = SessionState()
        _ = say("Play relaxing Telugu songs.", &state)
        _ = say("Same vibe but English.", &state)
        _ = say("Undo.", &state)
        XCTAssertEqual(state.language, .only(.telugu))
        XCTAssertEqual(state.vibe[.energy]?.value, 0.2)

        let liked = say("I like this.", &state)
        XCTAssertEqual(liked, [.feedback(.like, trackID: "audius:t1")])
        let never = say("Don't recommend this again.", &state)
        XCTAssertTrue(never.contains(.feedback(.neverAgain, trackID: "audius:t1")))
        XCTAssertEqual(state.excludedTracks["audius:t1"], .profile)
        // Session changes never become feedback.
        let session = say("Make it more energetic.", &state)
        XCTAssertFalse(session.contains { if case .feedback = $0 { true } else { false } })
    }

    func testSkipsAreWeakSignalsAndLockStopsDrift() {
        var state = SessionState()
        state.recordSkip(song)
        XCTAssertEqual(state.artistWeights["sid sriram"] ?? 0, -0.1, accuracy: 0.001)
        state.locked = true
        state.recordSkip(song)
        XCTAssertEqual(state.artistWeights["sid sriram"] ?? 0, -0.1, accuracy: 0.001)
        XCTAssertEqual(SessionState.key("S. Thaman"), "s thaman")
    }
}

final class VoiceReplyTests: XCTestCase {
    func testRepliesAreShortAndMatchTheListenersStyle() {
        func reply(_ text: String) -> String? { VoiceReply.text(for: IntentParser.parse(text)) }
        XCTAssertNil(reply("Skip."))
        XCTAssertNil(reply("Not this singer."))
        XCTAssertEqual(reply("Newer."), "Going newer.")
        XCTAssertEqual(reply("Keep this vibe."), "Keeping this vibe.")
        XCTAssertEqual(reply("Same vibe but English."), "Switching to English.")
        XCTAssertEqual(reply("కొంచెం energetic songs పెట్టు"), "Okay, energy పెంచుతున్నా.")
        XCTAssertEqual(reply("kotha telugu patalu pettu"), "Telugu songs పెడుతున్నా.")
        for text in ["Play energetic Telugu songs", "More like this", "Surprise me", "Go deeper"] {
            let words = reply(text)?.split(separator: " ").count ?? 0
            XCTAssertLessThanOrEqual(words, 4, text)
        }
    }

    func testLowConfidenceLastingChangesAreConfirmed() {
        var delta = IntentParser.parse("Don't recommend this again.")
        delta.confidence = 0.45
        XCTAssertTrue(delta.needsConfirmation)
        XCTAssertEqual(VoiceReply.text(for: delta), "Never play this again?")
        var harmless = IntentParser.parse("More energy.")
        harmless.confidence = 0.45
        XCTAssertFalse(harmless.needsConfirmation)  // harmless: just do it
    }
}
