import Foundation

/// Maps the deterministic evidence score to an estimated chance the interpretation is right.
/// The table is fitted on labeled development data (see `testCalibrationTableMatchesDevData`),
/// with isotonic smoothing so higher evidence never means lower confidence. Because it comes
/// from development data it is optimistic; its reliability is measured on the holdout.
public enum IntentCalibration {
    /// Upper bounds of the evidence bins (the last bin ends at 1.0).
    public static let binEdges: [Double] = [0.5, 0.7, 0.85, 0.95, 1.0001]
    /// P(correct) per bin, refitted 2026-11-06 with the cross-validated evidence weights on 1,106
    /// development decisions (corpus + retired holdouts v1–v4; bin sizes 0, 16, 73, 194, 823):
    /// Laplace-smoothed, isotonic; an empty bin is 0, so Halo always asks there.
    public static let table: [Double] = [0.0, 0.56, 0.64, 0.91, 0.95]
    public static let provenance = "corpus + retired holdouts v1-v4, 2026-11-06 (tuned weights)"

    public static func confidence(forEvidence evidence: Double, table: [Double] = table) -> Double {
        let index = binEdges.firstIndex { evidence < $0 } ?? (binEdges.count - 1)
        return table[index]
    }

    public static func bin(forEvidence evidence: Double) -> Int {
        binEdges.firstIndex { evidence < $0 } ?? (binEdges.count - 1)
    }
}
