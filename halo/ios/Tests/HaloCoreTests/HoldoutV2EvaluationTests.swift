import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Final measurement on holdout v2 (docs/testing/holdout-v2.json), labeled by a separate agent
/// from the specification only and frozen before evaluation. Report only: no floor, and the
/// parser must not be changed by looking at these results (retire the set if it is).
final class HoldoutV2EvaluationTests: XCTestCase {
    static func normalize(_ label: String) -> String {
        switch label {
        case "recency:newer": "newer"
        case "recency:older": "older"
        default: label
        }
    }

    static func entities(of decision: IntentDecision) -> Set<String> {
        var found = Set<String>()
        func add(_ type: String, _ name: String) { found.insert(type + "|" + SessionState.key(name)) }
        for operation in decision.delta.operations {
            switch operation {
            case let .play(.entity(.mention(name, kind))):
                add(kind == .soundtrack ? "film" : kind == .any ? "artist" : kind.rawValue, name)
            case let .weightArtist(.mention(name, _), _), let .excludeArtist(.mention(name, _), _):
                add("artist", name)
            case let .setLanguage(preference):
                add("language", preference.primary.rawValue)
                if let secondary = preference.secondary { add("language", secondary.rawValue) }
            case let .favorLanguage(language):
                add("language", language.rawValue)
            default: break
            }
        }
        for language in decision.delta.unsupportedLanguages { add("language", language.rawValue) }
        if case let .ambiguousEntity(said, _) = decision.reason { add("artist", said) }
        return found
    }

    struct Tally {
        var right = 0, total = 0
        mutating func add(_ ok: Bool) { total += 1; if ok { right += 1 } }
        var share: String { String(format: "%.3f", Double(right) / Double(max(total, 1))) }
    }

    func testHoldoutV2Singles() { Self.runSingles(HoldoutV2.singles, tag: "HALO-V2") }
    func testHoldoutV2Sequences() { Self.runSequences(HoldoutV2.sequences, tag: "HALO-V2") }
    /// Holdout v3: frozen 2026-11-04 (sha256 4f22e18d…7c3b9a), evaluated once, report only.
    func testHoldoutV3Singles() { Self.runSingles(HoldoutV3.singles, tag: "HALO-V3") }
    func testHoldoutV3Sequences() { Self.runSequences(HoldoutV3.sequences, tag: "HALO-V3") }

    static func runSingles(_ singles: [HoldoutV2.Single], tag: String) {
        var report: [String] = []
        func print(_ line: String) { report.append(line); Swift.print(line) }
        defer { save(report, as: tag + "-singles") }
        var exact = Tally(), outcomeTally = Tally(), entityTally = Tally(), negation = Tally()
        var byForm: [String: Tally] = [:], byCategory: [String: Tally] = [:]
        var confusion: [String: Int] = [:]
        var falseActions = Tally()  // labeled unsupported/no_action that Halo executed
        var clarifyTP = 0, clarifyFP = 0, clarifyFN = 0
        var reliability: [(confidence: Double, correct: Bool)] = []
        let started = DispatchTime.now().uptimeNanoseconds
        for item in singles {
            let decision = IntentInterpreter.interpret(item.text)
            let got = decision.outcome.rawValue
            let ops = decision.delta.operations.map(\.wire).sorted()
            let expected = item.expected.map(Self.normalize).sorted()
            let outcomeOK = got == item.outcome
            let ok = outcomeOK && (item.outcome != "execute" || ops == expected)
            exact.add(ok)
            outcomeTally.add(outcomeOK)
            byForm[item.form, default: Tally()].add(ok)
            byCategory[item.category, default: Tally()].add(ok)
            confusion["\(item.outcome)→\(got)", default: 0] += 1
            if !item.entities.isEmpty {
                let labeled = Set(item.entities.map { $0.type + "|" + SessionState.key($0.name) })
                entityTally.add(labeled == Self.entities(of: decision))
            }
            if item.category == "negative" { negation.add(ok) }
            if item.outcome == "unsupported" || item.outcome == "no_action" { falseActions.add(got == "execute") }
            if got == "clarify" && item.outcome == "clarify" { clarifyTP += 1 }
            if got == "clarify" && item.outcome != "clarify" { clarifyFP += 1 }
            if got != "clarify" && item.outcome == "clarify" { clarifyFN += 1 }
            if got == "execute", let confidence = decision.calibratedConfidence {
                reliability.append((confidence, ok))
            }
            if !ok {
                print("\(tag)-MISS [\(item.form)/\(item.category)] \(item.text) → \(got) \(ops) "
                      + "(expected \(item.outcome) \(expected))")
            }
        }
        let perUtterance = Double(DispatchTime.now().uptimeNanoseconds - started) / Double(singles.count) / 1e6
        print("\(tag) singles=\(exact.total) exact=\(exact.share) outcome=\(outcomeTally.share) "
              + "entities=\(entityTally.share) (n=\(entityTally.total)) negation=\(negation.share) (n=\(negation.total))")
        print("\(tag) false_action_rate=\(falseActions.share) (\(falseActions.right) of \(falseActions.total) "
              + "unsupported/no_action executed)")
        let precision = Double(clarifyTP) / Double(max(clarifyTP + clarifyFP, 1))
        let recall = Double(clarifyTP) / Double(max(clarifyTP + clarifyFN, 1))
        print("\(tag) " + String(format: "clarify precision=%.3f recall=%.3f (tp=%d fp=%d fn=%d)",
                     precision, recall, clarifyTP, clarifyFP, clarifyFN))
        for (form, tally) in byForm.sorted(by: { $0.key < $1.key }) {
            print("\(tag) form=\(form) exact=\(tally.share) n=\(tally.total)")
        }
        for (category, tally) in byCategory.sorted(by: { $0.key < $1.key }) {
            print("\(tag) category=\(category) exact=\(tally.share) n=\(tally.total)")
        }
        for (cell, count) in confusion.sorted(by: { $0.key < $1.key }) { print("\(tag) outcome \(cell) \(count)") }
        // Calibration reliability on executed commands: confidence vs. observed accuracy.
        var ece = 0.0
        for value in Set(reliability.map(\.confidence)).sorted() {
            let bin = reliability.filter { $0.confidence == value }
            let accuracy = Double(bin.filter(\.correct).count) / Double(bin.count)
            ece += Double(bin.count) / Double(max(reliability.count, 1)) * abs(accuracy - value)
            print("\(tag) " + String(format: "calibration confidence=%.2f observed=%.3f n=%d", value, accuracy, bin.count))
        }
        print("\(tag) " + String(format: "calibration ECE=%.3f", ece))
        print("\(tag) " + String(format: "latency_ms_per_utterance=%.3f", perUtterance))
        XCTAssertGreaterThanOrEqual(exact.total, 220)
    }

    static func runSequences(_ sequences: [HoldoutV2.Sequence], tag: String) {
        var report: [String] = []
        func print(_ line: String) { report.append(line); Swift.print(line) }
        defer { save(report, as: tag + "-sequences") }
        var tally = Tally()
        var byForm: [String: Tally] = [:]
        for sequence in sequences {
            var state = SessionState(startedAt: Date(timeIntervalSince1970: 1_793_000_000))
            let current = sequence.nowPlaying.map { NowPlayingContext(trackID: "audius:now", artist: $0) }
            for turn in sequence.turns {
                let decision = IntentInterpreter.interpret(turn)
                if decision.outcome == .execute {
                    state.apply(decision.delta, current: current, now: Date(timeIntervalSince1970: 1_793_000_000),
                                timeZone: TimeZone(identifier: "Asia/Kolkata")!)
                }
            }
            let got = Self.summary(state)
            let expected = sequence.expected.mapValues(Self.canonical)
            let ok = got == expected
            tally.add(ok)
            byForm[sequence.form, default: Tally()].add(ok)
            if !ok { print("\(tag)-SEQ-MISS [\(sequence.form)] \(sequence.turns) → \(got) (expected \(expected))") }
        }
        print("\(tag) sequences=\(tally.total) state_accuracy=\(tally.share)")
        for (form, t) in byForm.sorted(by: { $0.key < $1.key }) { print("\(tag) seq_form=\(form) accuracy=\(t.share) n=\(t.total)") }
        XCTAssertGreaterThanOrEqual(tally.total, 30)
    }

    /// Also written to .build/holdout-reports (console output on Linux can drop long runs).
    static func save(_ lines: [String], as name: String) {
        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/holdout-reports")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: directory.appendingPathComponent(name + ".txt"),
                                                  atomically: true, encoding: .utf8)
    }

    static func summary(_ state: SessionState) -> [String: String] {
        var out: [String: String] = [:]
        if let language = state.language {
            let secondary = language.secondary.map { "+\($0.rawValue)" } ?? ""
            out["language"] = "\(language.strategy.rawValue):\(language.primary.rawValue)\(secondary)"
        }
        for (key, dimension) in [("energy", VibeDimension.energy), ("valence", .valence), ("tempo", .tempo)] {
            if let value = state.vibe[dimension]?.value { out[key] = String(format: "%.2f", value) }
        }
        switch state.recency {
        case .any: break
        case let .decade(year): out["recency"] = "decade:\(year)"
        case .classics: out["recency"] = "classics"
        case let .withinDays(days): out["recency"] = "days:\(days)"
        }
        if state.locked { out["locked"] = "true" }
        if !state.excludedArtists.isEmpty {
            out["excludedArtists"] = state.excludedArtists.map { "\(SessionState.key($0.key))=\($0.value.rawValue)" }
                .sorted().joined(separator: ",")
        }
        let weights = state.artistWeights.filter { $0.value != 0 }
        if !weights.isEmpty {
            out["artistWeights"] = weights.map { "\(SessionState.key($0.key))=" + String(format: "%.2f", $0.value) }
                .sorted().joined(separator: ",")
        }
        if !state.avoidedMoods.isEmpty { out["avoid"] = state.avoidedMoods.map(\.rawValue).sorted().joined(separator: ",") }
        return out
    }

    /// A label value (JSON text) in the same canonical form as `summary`.
    static func canonical(_ json: String) -> String {
        if json == "true" || json == "false" { return json }
        guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        else { return json }
        switch value {
        case let text as String: return text
        case let number as NSNumber: return String(format: "%.2f", number.doubleValue)
        case let list as [Any]: return list.map { "\($0)" }.sorted().joined(separator: ",")
        case let map as [String: Any]:
            return map.map { key, value -> String in
                let rendered: String
                if let number = value as? NSNumber, !(value is String) {
                    rendered = String(format: "%.2f", number.doubleValue)
                } else {
                    rendered = "\(value)"
                }
                return "\(SessionState.key(key))=\(rendered)"
            }.sorted().joined(separator: ",")
        default: return json
        }
    }
}
