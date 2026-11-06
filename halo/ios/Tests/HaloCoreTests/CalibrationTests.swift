import Foundation
import XCTest
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

/// Fits `IntentCalibration.table` on labeled development data only: the development corpus and
/// holdout v1 (retired to development data after its misses were read). Holdout v2 is never
/// used here. The stored table must equal the fit, so it can't silently drift from the data.
final class CalibrationTests: XCTestCase {
    struct Sample { var evidence: Double; var correct: Bool }

    /// Every development command that reached the confidence step (the same pool the evidence
    /// weights are tuned on): right means the label says execute and the operations match.
    static func devSamples() -> [Sample] {
        EvidenceTuningTests.pool().compactMap { item in
            guard item.decision.features != nil else { return nil }
            return Sample(evidence: item.decision.evidence, correct: item.rightIfExecuted)
        }
    }

    /// Per-bin (correct + 1) / (total + 2), then pool-adjacent-violators so it never decreases.
    static func fit(_ samples: [Sample]) -> (table: [Double], counts: [Int]) {
        let bins = IntentCalibration.binEdges.count
        var correct = Array(repeating: 0.0, count: bins), total = Array(repeating: 0.0, count: bins)
        for sample in samples {
            let bin = IntentCalibration.bin(forEvidence: sample.evidence)
            total[bin] += 1
            if sample.correct { correct[bin] += 1 }
        }
        var blocks: [(value: Double, weight: Double, size: Int)] = []
        for bin in 0..<bins {
            // No data in a bin means no evidence Halo is right there: 0, so it always asks.
            let value: Double = total[bin] == 0 ? 0 : (correct[bin] + 1) / (total[bin] + 2)
            let weight: Double = total[bin] + 2
            blocks.append((value: value, weight: weight, size: 1))
        }
        var i = 0
        while i < blocks.count - 1 {
            if blocks[i].value > blocks[i + 1].value {
                let weight = blocks[i].weight + blocks[i + 1].weight
                let left: Double = blocks[i].value * blocks[i].weight
                let right: Double = blocks[i + 1].value * blocks[i + 1].weight
                let value: Double = (left + right) / weight
                blocks[i] = (value, weight, blocks[i].size + blocks[i + 1].size)
                blocks.remove(at: i + 1)
                i = max(i - 1, 0)
            } else {
                i += 1
            }
        }
        let table = blocks.flatMap { Array(repeating: ($0.value * 100).rounded() / 100, count: $0.size) }
        return (table, total.map { Int($0) })
    }

    func testCalibrationTableMatchesDevData() {
        let samples = Self.devSamples()
        let (table, counts) = Self.fit(samples)
        print("HALO-CALIBRATION samples=\(samples.count) counts=\(counts) table=\(table)")
        XCTAssertEqual(IntentCalibration.table, table, "refit: paste the printed table into IntentCalibration")
        for (a, b) in zip(table, table.dropFirst()) { XCTAssertLessThanOrEqual(a, b) }
    }
}
