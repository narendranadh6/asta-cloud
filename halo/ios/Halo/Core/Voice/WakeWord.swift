import Foundation

/// Spots the wake word in a running transcript. Opt-in, foreground only, on-device recognition
/// only (see `WakeWordListener`); this type only reads text, so it is tested without audio.
///
/// "Halo" alone wakes Halo up to listen for a command; "Halo, play Telugu songs" is the command
/// itself. Plain "hello" never counts (too common in conversation and on the radio), and "halo"
/// must be a whole word.
public struct WakeWordDetector: Sendable {
    public enum Event: Hashable, Sendable {
        /// The wake word on its own: start listening for a command.
        case wake
        /// The wake word followed by a command.
        case command(String)
    }

    /// Longest first, so "hey halo" wins over "halo".
    static let phrases = ["hey halo", "ok halo", "okay halo", "hello halo", "hi halo", "halo", "hallo",
                          "హే హలో", "హలో"]

    /// The event already reported for the current utterance (one per utterance).
    private var fired = false

    public init() {}

    /// Feed the recognizer's latest transcript for the current utterance. Returns an event once
    /// the utterance is final (the recognizer finished or the speaker paused).
    public mutating func feed(_ transcript: String, isFinal: Bool) -> Event? {
        guard isFinal else { return nil }
        defer { fired = false }
        guard !fired, let remainder = Self.afterWakeWord(transcript) else { return nil }
        fired = true
        return remainder.isEmpty ? .wake : .command(remainder)
    }

    /// Whether the transcript so far contains the wake word (to show "Listening…" early).
    public static func heardWakeWord(_ transcript: String) -> Bool {
        afterWakeWord(transcript) != nil
    }

    /// The words after the last wake word, or nil when there is none.
    static func afterWakeWord(_ transcript: String) -> String? {
        let words = normalized(transcript)
        guard !words.isEmpty else { return nil }
        let tokenized = phrases.map { $0.split(separator: " ").map(String.init) }
        var best: (end: Int, start: Int)?
        for phrase in tokenized where phrase.count <= words.count {
            for start in 0...(words.count - phrase.count) where Array(words[start..<(start + phrase.count)]) == phrase {
                let end = start + phrase.count
                if best == nil || start > best!.start || (start == best!.start && end > best!.end) {
                    best = (end, start)
                }
            }
        }
        guard let match = best else { return nil }
        return words[match.end...].joined(separator: " ")
    }

    static func normalized(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(.nonBaseCharacters).inverted)
            .filter { !$0.isEmpty }
    }
}
