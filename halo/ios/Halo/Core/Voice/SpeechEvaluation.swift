import Foundation

/// Recording-based evaluation on a real iPhone: the tester reads prompts aloud, Halo keeps only
/// the recognizer's text (never audio), and the results are scored for word error rate and
/// whether the command was understood the same as the typed prompt. Results stay on the device
/// until the tester exports them.
public struct SpeechEvaluationPrompt: Hashable, Sendable, Codable {
    public var id: String
    public var text: String
    public var localeID: String
    public var form: String

    public init(id: String, text: String, localeID: String, form: String) {
        self.id = id
        self.text = text
        self.localeID = localeID
        self.form = form
    }

    /// A small built-in prompt sheet (commands only, no lyrics). Testers can use their own.
    public static let starterSheet: [SpeechEvaluationPrompt] = [
        .init(id: "en-1", text: "Play energetic Telugu songs", localeID: "en-IN", form: "english"),
        .init(id: "en-2", text: "Make it a little calmer", localeID: "en-IN", form: "english"),
        .init(id: "en-3", text: "No sad songs today", localeID: "en-IN", form: "english"),
        .init(id: "en-4", text: "Who is singing this", localeID: "en-IN", form: "english"),
        .init(id: "ro-1", text: "Kotha Telugu songs pettu", localeID: "en-IN", form: "romanized"),
        .init(id: "ro-2", text: "Ee song vaddu", localeID: "en-IN", form: "romanized"),
        .init(id: "ro-3", text: "Anirudh songs ekkuva vaddu", localeID: "en-IN", form: "romanized"),
        .init(id: "ro-4", text: "Konchem energy penchu", localeID: "en-IN", form: "romanized"),
        .init(id: "te-1", text: "తెలుగు పాటలు పెట్టు", localeID: "te-IN", form: "telugu"),
        .init(id: "te-2", text: "ప్రశాంతమైన పాటలు పెట్టు", localeID: "te-IN", form: "telugu"),
        .init(id: "mx-1", text: "Same vibe lo English songs pettu", localeID: "en-IN", form: "mixed"),
        .init(id: "mx-2", text: "DSP songs పెట్టు", localeID: "te-IN", form: "mixed"),
    ]
}

public struct SpeechEvaluationResult: Hashable, Sendable, Codable {
    public var promptID: String
    public var localeID: String
    public var route: String
    public var transcript: String
    public var wordErrorRate: Double
    /// The spoken command was understood exactly as the typed prompt.
    public var intentMatches: Bool
    public var latencyMs: Int
}

public enum SpeechEvaluation {
    /// Word error rate: word-level edit distance / reference words (case and punctuation ignored).
    public static func wordErrorRate(reference: String, hypothesis: String) -> Double {
        let ref = words(reference), hyp = words(hypothesis)
        guard !ref.isEmpty else { return hyp.isEmpty ? 0 : 1 }
        var row = Array(0...hyp.count)
        for (i, r) in ref.enumerated() {
            var previous = row[0]
            row[0] = i + 1
            for (j, h) in hyp.enumerated() {
                let substitution = previous + (r == h ? 0 : 1)
                previous = row[j + 1]
                row[j + 1] = min(substitution, row[j] + 1, row[j + 1] + 1)
            }
        }
        return Double(row[hyp.count]) / Double(ref.count)
    }

    public static func score(prompt: SpeechEvaluationPrompt, transcript: String, route: SpeechRoute,
                             latencyMs: Int) -> SpeechEvaluationResult {
        let expected = IntentInterpreter.interpret(prompt.text)
        let heard = IntentInterpreter.interpret(transcript)
        let matches = expected.outcome == heard.outcome
            && expected.delta.operations.map(\.wire).sorted() == heard.delta.operations.map(\.wire).sorted()
        return SpeechEvaluationResult(
            promptID: prompt.id, localeID: prompt.localeID, route: describe(route), transcript: transcript,
            wordErrorRate: wordErrorRate(reference: prompt.text, hypothesis: transcript),
            intentMatches: matches, latencyMs: latencyMs)
    }

    public static func describe(_ route: SpeechRoute) -> String {
        switch route {
        case .onDevice: "on-device"
        case .appleServer: "apple-server"
        case .haloServer: "halo-server"
        case .textInput: "typed"
        }
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.nonBaseCharacters).inverted)
            .filter { !$0.isEmpty }
    }
}
