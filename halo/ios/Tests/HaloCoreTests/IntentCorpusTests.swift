import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// The curated Halo Context evaluation set: one utterance, the operations it should produce
/// after parsing and entity resolution, and its speech form. Expectations describe what the
/// listener means, not what the parser happened to output; misses are measured, not hidden.
/// Results are printed as HALO-METRIC lines and recorded in docs/testing/BENCHMARK_RESULTS.md.
final class IntentCorpusTests: XCTestCase {
    enum Form: String, CaseIterable { case english, romanized, telugu, mixed }

    struct Case {
        var text: String
        var expected: [String]
        var form: Form
    }

    static let corpus: [Case] = [
        // English
        .init(text: "Play energetic Telugu songs", expected: ["play", "set:energy:0.85", "lang:only:te"], form: .english),
        .init(text: "More energetic", expected: ["adjust:energy:+0.20"], form: .english),
        .init(text: "Same vibe", expected: ["lock"], form: .english),
        .init(text: "English only", expected: ["lang:only:en"], form: .english),
        .init(text: "Back to Telugu", expected: ["lang:only:te"], form: .english),
        .init(text: "No sad songs", expected: ["avoid:sad"], form: .english),
        .init(text: "Don't play this singer today", expected: ["exclude:current:today"], form: .english),
        .init(text: "Play older songs", expected: ["older"], form: .english),
        .init(text: "Keep this mood", expected: ["lock"], form: .english),
        .init(text: "Surprise me", expected: ["play:surprise", "adjust:discovery:+0.30"], form: .english),
        .init(text: "Undo", expected: ["undo"], form: .english),
        .init(text: "Newer", expected: ["newer"], form: .english),
        .init(text: "Not too much Anirudh", expected: ["weight:Anirudh Ravichander:-0.60"], form: .english),
        .init(text: "Same vibe but English", expected: ["preserve:vibe", "lang:only:en"], form: .english),
        .init(text: "Make it calmer", expected: ["adjust:energy:-0.20"], form: .english),
        .init(text: "Something calm", expected: ["set:energy:0.20"], form: .english),
        .init(text: "Play something relaxing", expected: ["play", "set:energy:0.20"], form: .english),
        .init(text: "Skip", expected: ["transport:next"], form: .english),
        .init(text: "Next song", expected: ["transport:next"], form: .english),
        .init(text: "Pause", expected: ["transport:pause"], form: .english),
        .init(text: "Resume", expected: ["transport:resume"], form: .english),
        .init(text: "Go back", expected: ["transport:previous"], form: .english),
        .init(text: "Play it from the start", expected: ["transport:restart"], form: .english),
        .init(text: "Who is singing this?", expected: ["ask:whoIsSinging"], form: .english),
        .init(text: "What movie is this from?", expected: ["ask:whatMovie"], form: .english),
        .init(text: "What's next?", expected: ["ask:upNext"], form: .english),
        .init(text: "I like this", expected: ["rate:like"], form: .english),
        .init(text: "I don't like this", expected: ["rate:dislike"], form: .english),
        .init(text: "Never play this again", expected: ["rate:neverAgain"], form: .english),
        .init(text: "Save this for later", expected: ["rate:later"], form: .english),
        .init(text: "This is good", expected: ["rate:keep"], form: .english),
        .init(text: "Play songs from the 90s", expected: ["play", "recency:decade:1990"], form: .english),
        .init(text: "Play 2000s Telugu hits", expected: ["play", "recency:decade:2000", "lang:only:te"], form: .english),
        .init(text: "Something new", expected: ["adjust:discovery:+0.30"], form: .english),
        .init(text: "Play the latest Telugu songs", expected: ["play", "recency:days:90", "lang:only:te"], form: .english),
        .init(text: "Play new songs from this week", expected: ["play", "recency:days:7"], form: .english),
        .init(text: "Play classics", expected: ["play", "recency:classics"], form: .english),
        .init(text: "Play DSP songs", expected: ["play:artist:Devi Sri Prasad"], form: .english),
        .init(text: "Play Thaman songs", expected: ["play:artist:S. Thaman"], form: .english),
        .init(text: "Play songs from Pushpa", expected: ["play:soundtrack:pushpa"], form: .english),
        .init(text: "Don't play Anirudh today", expected: ["exclude:Anirudh Ravichander:today"], form: .english),
        .init(text: "No more Thaman", expected: ["exclude:S. Thaman:session"], form: .english),
        .init(text: "Less of this artist", expected: ["weight:current:-0.60"], form: .english),
        .init(text: "More from this artist", expected: ["weight:current:+0.60"], form: .english),
        .init(text: "Different singer", expected: ["diversify"], form: .english),
        .init(text: "Go deeper", expected: ["seed:deeper"], form: .english),
        .init(text: "Take me somewhere different", expected: ["seed:elsewhere", "adjust:discovery:+0.30"], form: .english),
        .init(text: "More like this", expected: ["play:similar"], form: .english),
        .init(text: "Happier", expected: ["adjust:valence:+0.20"], form: .english),
        .init(text: "Play happy songs", expected: ["play", "set:valence:0.80"], form: .english),
        .init(text: "Romantic songs please", expected: ["play", "set:valence:0.65", "set:energy:0.40"], form: .english),
        .init(text: "Mix Telugu and English", expected: ["lang:mixed:te+en"], form: .english),
        .init(text: "Mostly Telugu with some English", expected: ["lang:mostly:te+en"], form: .english),
        .init(text: "More Telugu", expected: ["favor:te"], form: .english),
        .init(text: "Play Tamil songs", expected: [], form: .english),  // not supported yet: says so
        .init(text: "Slightly more energy", expected: ["adjust:energy:+0.12"], form: .english),
        .init(text: "A bit slower", expected: ["adjust:energy:-0.12"], form: .english),
        .init(text: "Less energy", expected: ["adjust:energy:-0.20"], form: .english),
        .init(text: "Songs I know", expected: ["play", "set:discovery:0.15"], form: .english),
        .init(text: "Keep this vibe", expected: ["lock"], form: .english),
        .init(text: "Remove the next song", expected: ["transport:removeNext"], form: .english),
        .init(text: "Undo that", expected: ["undo"], form: .english),
        .init(text: "Play workout music", expected: ["play", "set:energy:0.85"], form: .english),
        .init(text: "Something for sleep", expected: ["set:energy:0.20"], form: .english),
        .init(text: "Old Telugu melodies", expected: ["recency:classics", "lang:only:te", "set:energy:0.20"], form: .english),
        .init(text: "Play 80s English hits", expected: ["play", "recency:decade:1980", "lang:only:en"], form: .english),
        .init(text: "What album is this?", expected: ["ask:whatAlbum"], form: .english),
        .init(text: "When was this released?", expected: ["ask:whenReleased"], form: .english),
        .init(text: "Stop", expected: ["transport:pause"], form: .english),
        .init(text: "Add this to my favorites", expected: ["rate:like"], form: .english),
        .init(text: "Don't recommend this again", expected: ["rate:neverAgain"], form: .english),
        .init(text: "Same energy but newer", expected: ["preserve:vibe", "newer"], form: .english),
        .init(text: "Play something I haven't heard", expected: ["play", "adjust:discovery:+0.30"], form: .english),
        .init(text: "Play Sid Sriram songs", expected: ["play:artist:Sid Sriram"], form: .english),
        .init(text: "Play SPB songs", expected: ["play:artist:S. P. Balasubrahmanyam"], form: .english),
        .init(text: "Don't play sad songs", expected: ["avoid:sad"], form: .english),
        .init(text: "Play relaxing English songs from the 2010s",
              expected: ["play", "set:energy:0.20", "lang:only:en", "recency:decade:2010"], form: .english),
        .init(text: "uh play um energetic songs", expected: ["play", "set:energy:0.85"], form: .english),
        .init(text: "Energetic", expected: ["set:energy:0.85"], form: .english),
        .init(text: "Play", expected: ["transport:resume"], form: .english),
        .init(text: "Something different please", expected: ["seed:elsewhere", "adjust:discovery:+0.30"], form: .english),
        .init(text: "No more sad songs", expected: ["avoid:sad"], form: .english),

        // Romanized Telugu
        // "konchem" = "a bit": a small step up (Halo Drive starts music if nothing is playing).
        .init(text: "Konchem energetic songs pettu", expected: ["adjust:energy:+0.12"], form: .romanized),
        .init(text: "Kotha Telugu patalu", expected: ["play", "recency:days:90", "lang:only:te"], form: .romanized),
        .init(text: "DSP songs pettu", expected: ["play:artist:Devi Sri Prasad"], form: .romanized),
        .init(text: "Thaman mass beats", expected: ["play:artist:S. Thaman", "set:energy:0.85"], form: .romanized),
        .init(text: "Sad songs vaddu", expected: ["avoid:sad"], form: .romanized),
        .init(text: "Telugu songs matrame", expected: ["play", "lang:only:te"], form: .romanized),
        .init(text: "Inka energy penchu", expected: ["adjust:energy:+0.20"], form: .romanized),
        .init(text: "Skip cheyyi", expected: ["transport:next"], form: .romanized),
        .init(text: "Aapu", expected: ["transport:pause"], form: .romanized),
        .init(text: "Ee singer vaddu", expected: ["exclude:current:session"], form: .romanized),
        .init(text: "Ee singer ivala vaddu", expected: ["exclude:current:today"], form: .romanized),
        .init(text: "Paatha Telugu patalu pettu", expected: ["play", "recency:classics", "lang:only:te"], form: .romanized),
        .init(text: "Prashanthamga emaina pettu", expected: ["play", "set:energy:0.20"], form: .romanized),
        .init(text: "Nachindi", expected: ["rate:like"], form: .romanized),
        .init(text: "Nachaledu", expected: ["rate:dislike"], form: .romanized),
        .init(text: "Malli pettaku", expected: ["rate:neverAgain"], form: .romanized),
        .init(text: "Singer evaru", expected: ["ask:whoIsSinging"], form: .romanized),
        .init(text: "Ilanti songs pettu", expected: ["play:similar"], form: .romanized),
        .init(text: "Vere vibe", expected: ["seed:elsewhere", "adjust:discovery:+0.30"], form: .romanized),
        .init(text: "Ade vibe kani English", expected: ["preserve:vibe", "lang:only:en"], form: .romanized),
        .init(text: "Anirudh vaddu", expected: ["exclude:Anirudh Ravichander:session"], form: .romanized),
        .init(text: "Kothavi pettu", expected: ["newer"], form: .romanized),
        .init(text: "Ilayaraja patalu pettu", expected: ["play:artist:Ilaiyaraaja"], form: .romanized),
        .init(text: "Raja songs pettu", expected: ["play:any:raja"], form: .romanized),  // ambiguous: Halo asks
        .init(text: "Telugu English mix pettu", expected: ["play", "lang:mixed:te+en"], form: .romanized),
        .init(text: "Undo cheyyi", expected: ["undo"], form: .romanized),
        .init(text: "Keeravani songs vinipinchu", expected: ["play:artist:M. M. Keeravani"], form: .romanized),

        // Telugu script
        .init(text: "తెలుగు పాటలు పెట్టు", expected: ["play", "lang:only:te"], form: .telugu),
        .init(text: "ఎనర్జీ పెంచు", expected: ["adjust:energy:+0.20"], form: .telugu),
        .init(text: "పాత పాటలు పెట్టు", expected: ["play", "recency:classics"], form: .telugu),
        .init(text: "కొత్త పాటలు", expected: ["play", "recency:days:90"], form: .telugu),
        .init(text: "ఎవరు పాడారు", expected: ["ask:whoIsSinging"], form: .telugu),
        .init(text: "నచ్చింది", expected: ["rate:like"], form: .telugu),
        .init(text: "తర్వాత", expected: ["transport:next"], form: .telugu),
        .init(text: "ఆపు", expected: ["transport:pause"], form: .telugu),
        .init(text: "ప్రశాంతంగా ఏదైనా పెట్టు", expected: ["play", "set:energy:0.20"], form: .telugu),
        .init(text: "బాధ పాటలు వద్దు", expected: ["avoid:sad"], form: .telugu),
        .init(text: "దేవిశ్రీ పాటలు పెట్టు", expected: ["play:artist:Devi Sri Prasad"], form: .telugu),
        .init(text: "మళ్ళీ పెట్టకు", expected: ["rate:neverAgain"], form: .telugu),
        .init(text: "ఇంగ్లీష్ పాటలు మాత్రమే", expected: ["play", "lang:only:en"], form: .telugu),

        // Mixed Telugu and English
        .init(text: "Telugu lo energetic songs pettu", expected: ["play", "set:energy:0.85", "lang:only:te"], form: .mixed),
        .init(text: "Ee singer songs ekkuva pettu", expected: ["weight:current:+0.60"], form: .mixed),
        .init(text: "ఈ singer వద్దు", expected: ["exclude:current:session"], form: .mixed),
        .init(text: "Same vibe but Telugu", expected: ["preserve:vibe", "lang:only:te"], form: .mixed),
        .init(text: "Hey Halo, play DSP songs", expected: ["play:artist:Devi Sri Prasad"], form: .mixed),
        .init(text: "Halo skip", expected: ["transport:next"], form: .mixed),
        .init(text: "Thaman songs vaddu today", expected: ["exclude:S. Thaman:today"], form: .mixed),
        .init(text: "90s Telugu melodies pettu",
              expected: ["play", "recency:decade:1990", "lang:only:te", "set:energy:0.20"], form: .mixed),
        .init(text: "English songs ఇంకా pettu", expected: ["play", "lang:only:en"], form: .mixed),
        .init(text: "Telugu lo kotha songs pettu", expected: ["play", "recency:days:90", "lang:only:te"], form: .mixed),
        .init(text: "Energy తగ్గించు", expected: ["adjust:energy:-0.20"], form: .mixed),
    ]

    static let resolver = EntityResolver()

    static func run(_ text: String) -> [String] {
        let delta = resolver.resolve(IntentParser.parse(text)).delta
        return delta.operations.map(describe).sorted()
    }

    func testCorpusAccuracyIsMeasured() {
        XCTAssertGreaterThanOrEqual(Self.corpus.count, 100)
        var correct: [Form: Int] = [:]
        var total: [Form: Int] = [:]
        var misses: [String] = []
        for item in Self.corpus {
            total[item.form, default: 0] += 1
            let got = Self.run(item.text)
            if got == item.expected.sorted() {
                correct[item.form, default: 0] += 1
            } else {
                misses.append("\(item.text) → \(got) (expected \(item.expected.sorted()))")
            }
        }
        let right = correct.values.reduce(0, +)
        let accuracy = Double(right) / Double(Self.corpus.count)
        print("HALO-METRIC intent_corpus_size=\(Self.corpus.count)")
        print("HALO-METRIC intent_accuracy=\(String(format: "%.3f", accuracy))")
        for form in Form.allCases {
            let share = Double(correct[form] ?? 0) / Double(max(total[form] ?? 0, 1))
            print("HALO-METRIC intent_accuracy_\(form.rawValue)=\(String(format: "%.3f", share)) n=\(total[form] ?? 0)")
        }
        for miss in misses { print("HALO-MISS \(miss)") }
        // The floor only rises: lower it never; raise it when the measured accuracy does.
        XCTAssertGreaterThanOrEqual(accuracy, Self.accuracyFloor, misses.joined(separator: "\n"))
    }

    static let accuracyFloor = 0.98

    func testParsingIsFast() {
        let texts = Self.corpus.map(\.text)
        let rounds = 20
        let start = DispatchTime.now().uptimeNanoseconds
        for _ in 0..<rounds { for text in texts { _ = Self.run(text) } }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start)
        let perUtterance = elapsed / Double(rounds * texts.count) / 1_000_000
        print("HALO-METRIC intent_parse_ms_per_utterance=\(String(format: "%.3f", perUtterance))")
        XCTAssertLessThan(perUtterance, 50)  // the budget is 500 ms for the whole command
    }

    func testSessionUpdateAndLocalRerankAreFast() {
        var state = SessionState()
        let pool = (0..<200).map { index in
            SessionCandidate(
                track: Track(id: "audius:p\(index)", source: .audius, sourceId: "p\(index)",
                             title: "Song \(index)", artist: "Artist \(index % 40)",
                             releaseDate: "20\(10 + index % 15)-01-01", streamUrl: "https://s.test/\(index)",
                             language: index % 3 == 0 ? "en" : "te", energy: Double(index % 10) / 10,
                             valence: Double(index % 7) / 7,
                             attribution: Attribution(provider: .audius, label: "Audius")),
                score: 0, fit: ["rank": 0.5], source: "intent")
        }
        let deltas = ["Play energetic Telugu songs", "More energy", "Not too much artist 3",
                      "No sad songs", "Same vibe but English", "Newer", "Undo"].map(IntentParser.parse)
        let start = DispatchTime.now().uptimeNanoseconds
        let rounds = 50
        for _ in 0..<rounds {
            for delta in deltas {
                state.apply(delta, current: nil)
                _ = SessionRanker.rank(pool, for: state)
            }
        }
        let perStep = Double(DispatchTime.now().uptimeNanoseconds - start) / Double(rounds * deltas.count) / 1_000_000
        print("HALO-METRIC session_update_plus_rerank_200_ms=\(String(format: "%.3f", perStep))")
        XCTAssertLessThan(perStep, 150)
    }
}

/// The corpus compares operations in their wire form (see `SessionOperation.wire`).
func describe(_ operation: SessionOperation) -> String { operation.wire }
