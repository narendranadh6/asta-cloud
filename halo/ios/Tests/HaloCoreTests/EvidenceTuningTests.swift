import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Chooses `EvidenceWeights.current` and `GateThresholds.current` by 5-fold cross-validation on
/// development data only (the corpus and the retired holdouts v1–v4; never an active holdout).
/// For each candidate: fit the calibration table on four folds, gate the fifth, score exact
/// accuracy (outcome + operations) on it. Run with HALO_TUNE=1; skipped otherwise.
final class EvidenceTuningTests: XCTestCase {
    struct Item {
        var decision: IntentDecision
        var labelOutcome: String
        var expected: [String]
        /// Right if executed: the label says execute and the operations match.
        var rightIfExecuted: Bool
    }

    static func pool() -> [Item] {
        var items: [Item] = []
        func add(_ text: String, _ outcome: String, _ expected: [String]) {
            let decision = IntentInterpreter.interpret(text)
            let ops = decision.delta.operations.map(\.wire).sorted()
            let wanted = expected.map(HoldoutV2EvaluationTests.normalize).sorted()
            items.append(Item(decision: decision, labelOutcome: outcome, expected: wanted,
                              rightIfExecuted: outcome == "execute" && ops == wanted))
        }
        for c in IntentCorpusTests.corpus where !c.expected.isEmpty { add(c.text, "execute", c.expected) }
        for c in HoldoutV1.singles where !c.expected.isEmpty { add(c.text, "execute", c.expected) }
        for c in HoldoutV2.singles + HoldoutV3.singles + HoldoutV4.singles { add(c.text, c.outcome, c.expected) }
        return items
    }

    static func exact(_ item: Item, gated: IntentDecision) -> Bool {
        let ops = gated.delta.operations.map(\.wire).sorted()
        return gated.outcome.rawValue == item.labelOutcome && (item.labelOutcome != "execute" || ops == item.expected)
    }

    struct Candidate: CustomStringConvertible {
        var weights: EvidenceWeights
        var thresholds: GateThresholds
        var description: String {
            String(format: "unknown=%.2f unresolved=%.2f conflict=%.2f manyOps=%.2f session=%.2f lasting=%.2f",
                   weights.unknownShare, weights.unresolvedName, weights.conflict, weights.manyOperations,
                   thresholds.session, thresholds.lasting)
        }
    }

    /// Mean and per-fold accuracies of a candidate under 5-fold cross-validation.
    static func crossValidate(_ candidate: Candidate, _ items: [Item], folds: Int = 5) -> (mean: Double, perFold: [Double]) {
        var perFold: [Double] = []
        for fold in 0..<folds {
            let train = items.enumerated().filter { $0.offset % folds != fold }.map(\.element)
            let test = items.enumerated().filter { $0.offset % folds == fold }.map(\.element)
            let samples = train.compactMap { item -> CalibrationTests.Sample? in
                guard let features = item.decision.features else { return nil }
                return CalibrationTests.Sample(evidence: candidate.weights.score(features), correct: item.rightIfExecuted)
            }
            let table = CalibrationTests.fit(samples).table
            let right = test.filter { item in
                exact(item, gated: IntentInterpreter.gate(item.decision, weights: candidate.weights, table: table,
                                                          thresholds: candidate.thresholds))
            }.count
            perFold.append(Double(right) / Double(test.count))
        }
        return (perFold.reduce(0, +) / Double(folds), perFold)
    }

    func testTuneEvidenceWeights() throws {
        guard ProcessInfo.processInfo.environment["HALO_TUNE"] == "1" else { throw XCTSkip("set HALO_TUNE=1 to tune") }
        // A fixed shuffle so folds mix sources.
        var generator = SplitMix(seed: 20261106)
        let items = Self.pool().shuffled(using: &generator)
        let baseline = Candidate(weights: .current, thresholds: .current)
        let base = Self.crossValidate(baseline, items)
        var report = ["HALO-TUNE items=\(items.count) gated=\(items.filter { $0.decision.features != nil }.count)",
                      String(format: "HALO-TUNE baseline cv=%.4f folds=%@ %@", base.mean,
                             base.perFold.map { String(format: "%.3f", $0) }.joined(separator: ","), baseline.description)]
        var results: [(Candidate, Double, [Double])] = []
        for unknown in [0.3, 0.45, 0.6, 0.8, 1.0] {
            for unresolved in [0.0, 0.06, 0.12, 0.2, 0.3] {
                for conflict in [0.0, 0.1, 0.2, 0.3] {
                    for many in [0.0, 0.1] {
                        for session in [0.5, 0.55, 0.6, 0.65, 0.7, 0.75] {
                            for lasting in [0.85, 0.9] {
                                let c = Candidate(weights: EvidenceWeights(unknownShare: unknown, unresolvedName: unresolved,
                                                                           conflict: conflict, manyOperations: many,
                                                                           recognizer: 0.5),
                                                  thresholds: GateThresholds(low: 0.5, session: session, lasting: lasting))
                                let r = Self.crossValidate(c, items)
                                results.append((c, r.mean, r.perFold))
                            }
                        }
                    }
                }
            }
        }
        results.sort { $0.1 > $1.1 }
        for (c, mean, folds) in results.prefix(8) {
            report.append(String(format: "HALO-TUNE cv=%.4f folds=%@ %@", mean,
                                 folds.map { String(format: "%.3f", $0) }.joined(separator: ","), c.description))
        }
        let best = results[0]
        let gains = zip(best.2, base.perFold).map { $0 - $1 }
        report.append(String(format: "HALO-TUNE best-minus-baseline per fold=%@ mean=%.4f",
                             gains.map { String(format: "%+.3f", $0) }.joined(separator: ","),
                             gains.reduce(0, +) / Double(gains.count)))
        report.forEach { print($0) }
        HoldoutV2EvaluationTests.save(report, as: "HALO-TUNE-evidence")
    }
}

/// Deterministic generator for reproducible folds.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
