import Foundation

/// Maps the deterministic evidence score to an estimated chance the interpretation is right.
/// The table is fitted on labeled development data (see `testCalibrationTableMatchesDevData`),
/// with isotonic smoothing so higher evidence never means lower confidence. Because it comes
/// from development data it is optimistic; its reliability is measured on the holdout.
public enum IntentCalibration {
    /// Upper bounds of the evidence bins (the last bin ends at 1.0).
    public static let binEdges: [Double] = [0.5, 0.7, 0.85, 0.95, 1.0001]
    /// P(correct) per bin, refitted 2026-11-04 after the negation and evidence fixes on 301
    /// development decisions (bin sizes 1, 6, 19, 31, 244): Laplace-smoothed, isotonic. The two
    /// lowest bins have almost no data, so their value is mostly the prior: treat as "unknown",
    /// which is why Halo asks there. Holdout v2 showed the previous table was overconfident.
    public static let table: [Double] = [0.45, 0.45, 0.71, 0.91, 0.96]
    public static let provenance = "dev corpus + retired holdout v1, refit 2026-11-04 (negation, evidence)"

    public static func confidence(forEvidence evidence: Double) -> Double {
        let index = binEdges.firstIndex { evidence < $0 } ?? (binEdges.count - 1)
        return table[index]
    }

    public static func bin(forEvidence evidence: Double) -> Int {
        binEdges.firstIndex { evidence < $0 } ?? (binEdges.count - 1)
    }
}
