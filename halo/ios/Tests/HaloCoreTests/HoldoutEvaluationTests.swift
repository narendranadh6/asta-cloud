import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Measures Halo Context on the frozen holdout set (docs/testing/holdout-v1.json), labeled
/// independently of the parser. Report only: there is no accuracy floor to tune toward, and
/// parser changes must never be made by looking at these misses.
final class HoldoutEvaluationTests: XCTestCase {
    /// The labeler wrote relative era as "recency:newer" / "recency:older"; the schema's
    /// strings are "newer" / "older". Only the spelling is mapped, never a meaning.
    static func normalize(_ label: String) -> String {
        switch label {
        case "recency:newer": "newer"
        case "recency:older": "older"
        default: label
        }
    }

    enum ErrorKind: String, CaseIterable {
        case missedEverything = "understood nothing"
        case actedOnNothing = "acted when it should not"
        case missingOperation = "missed an operation"
        case extraOperation = "added an operation"
        case wrongValue = "wrong value or target"
    }

    static func classify(expected: [String], got: [String]) -> ErrorKind {
        if got.isEmpty { return .missedEverything }
        if expected.isEmpty { return .actedOnNothing }
        let e = Set(expected), g = Set(got)
        let kinds = { (set: Set<String>) in Set(set.map { $0.split(separator: ":").prefix(2).joined(separator: ":") }) }
        if kinds(e) == kinds(g) { return .wrongValue }
        if g.isSubset(of: e) || kinds(g).isSubset(of: kinds(e)) { return .missingOperation }
        if e.isSubset(of: g) || kinds(e).isSubset(of: kinds(g)) { return .extraOperation }
        return .wrongValue
    }

    func testHoldoutSingles() {
        var byForm: [String: (Int, Int)] = [:]
        var byCategory: [String: (Int, Int)] = [:]
        var errors: [ErrorKind: Int] = [:]
        var right = 0
        for item in HoldoutV1.singles {
            let expected = item.expected.map(Self.normalize).sorted()
            let got = IntentCorpusTests.run(item.text)
            let ok = got == expected
            if ok { right += 1 } else {
                errors[Self.classify(expected: expected, got: got), default: 0] += 1
                print("HALO-HOLDOUT-MISS [\(item.form)/\(item.category)] \(item.text) → \(got) (expected \(expected))")
            }
            byForm[item.form, default: (0, 0)].0 += ok ? 1 : 0
            byForm[item.form, default: (0, 0)].1 += 1
            byCategory[item.category, default: (0, 0)].0 += ok ? 1 : 0
            byCategory[item.category, default: (0, 0)].1 += 1
        }
        let total = HoldoutV1.singles.count
        print("HALO-HOLDOUT singles=\(total) accuracy=\(Self.share(right, total))")
        for (form, (ok, n)) in byForm.sorted(by: { $0.key < $1.key }) {
            print("HALO-HOLDOUT form=\(form) accuracy=\(Self.share(ok, n)) n=\(n)")
        }
        for (category, (ok, n)) in byCategory.sorted(by: { $0.key < $1.key }) {
            print("HALO-HOLDOUT category=\(category) accuracy=\(Self.share(ok, n)) n=\(n)")
        }
        for kind in ErrorKind.allCases where errors[kind] != nil {
            print("HALO-HOLDOUT error=\"\(kind.rawValue)\" count=\(errors[kind]!)")
        }
        XCTAssertGreaterThanOrEqual(total, 140)
    }

    func testHoldoutSequences() {
        var right = 0
        var byForm: [String: (Int, Int)] = [:]
        for sequence in HoldoutV1.sequences {
            var state = SessionState()
            for turn in sequence.turns {
                state.apply(IntentCorpusTests.resolver.resolve(IntentParser.parse(turn)).delta, current: nil)
            }
            let got = Self.summary(state)
            let expected = sequence.expected.mapValues(Self.canonicalJSON)
            let ok = got == expected
            if ok { right += 1 } else {
                print("HALO-HOLDOUT-SEQ-MISS [\(sequence.form)] \(sequence.turns) → \(got) (expected \(expected))")
            }
            byForm[sequence.form, default: (0, 0)].0 += ok ? 1 : 0
            byForm[sequence.form, default: (0, 0)].1 += 1
        }
        print("HALO-HOLDOUT sequences=\(HoldoutV1.sequences.count) accuracy=\(Self.share(right, HoldoutV1.sequences.count))")
        for (form, (ok, n)) in byForm.sorted(by: { $0.key < $1.key }) {
            print("HALO-HOLDOUT seq_form=\(form) accuracy=\(Self.share(ok, n)) n=\(n)")
        }
        XCTAssertGreaterThanOrEqual(HoldoutV1.sequences.count, 20)
    }

    /// The final state in the labels' vocabulary; unset fields are left out.
    static func summary(_ state: SessionState) -> [String: String] {
        var out: [String: String] = [:]
        if let language = state.language {
            let secondary = language.secondary.map { "+\($0.rawValue)" } ?? ""
            out["language"] = "\"\(language.strategy.rawValue):\(language.primary.rawValue)\(secondary)\""
        }
        if let energy = state.vibe[.energy]?.value { out["energy"] = number(energy) }
        if let valence = state.vibe[.valence]?.value { out["valence"] = number(valence) }
        switch state.recency {
        case .any: break
        case let .decade(year): out["recency"] = "\"decade:\(year)\""
        case .classics: out["recency"] = "\"classics\""
        case let .withinDays(days): out["recency"] = "\"days:\(days)\""
        }
        if state.locked { out["locked"] = "true" }
        let excluded = state.excludedArtists.keys.sorted()
        if !excluded.isEmpty { out["excludedArtists"] = list(excluded) }
        if !state.avoidedMoods.isEmpty { out["avoid"] = list(state.avoidedMoods.map(\.rawValue).sorted()) }
        return out
    }

    /// Labels written as JSON, in the same canonical text as `summary` (names normalized).
    static func canonicalJSON(_ json: String) -> String {
        if json == "true" || json == "false" { return json }
        guard let value = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)
        else { return json }
        switch value {
        case let names as [String]: return list(names.map(SessionState.key).sorted())
        case let number as NSNumber: return Self.number(number.doubleValue)
        case let text as String: return "\"\(text)\""
        default: return json
        }
    }

    static func number(_ value: Double) -> String { String(format: "%.2f", value) }
    static func list(_ items: [String]) -> String { "[" + items.map { "\"\($0)\"" }.joined(separator: ",") + "]" }
    static func share(_ ok: Int, _ total: Int) -> String {
        String(format: "%.3f", Double(ok) / Double(max(total, 1)))
    }
}
