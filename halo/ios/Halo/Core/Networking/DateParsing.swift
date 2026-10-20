import Foundation

/// Parses the RFC 3339 timestamps the backend emits, including Python's microsecond
/// precision ("2026-10-18T08:01:02.123456Z") and numeric offsets ("+00:00").
public enum HaloDateParser {
    public static func parse(_ string: String) -> Date? {
        var text = string.trimmingCharacters(in: .whitespaces)
        var fraction: Double = 0
        if let dot = text.firstIndex(of: ".") {
            let afterDot = text.index(after: dot)
            let digitsEnd = text[afterDot...].firstIndex { !$0.isNumber } ?? text.endIndex
            let digits = String(text[afterDot..<digitsEnd])
            if !digits.isEmpty, let value = Double("0." + digits) {
                fraction = value
            }
            text.removeSubrange(dot..<digitsEnd)
        }
        if !text.hasSuffix("Z"), !text.contains("+"), text.split(separator: "-").count <= 3 {
            text += "Z"  // naive timestamps are UTC by backend convention
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: text) else { return nil }
        return date.addingTimeInterval(fraction)
    }
}

extension JSONDecoder {
    public static var halo: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = HaloDateParser.parse(raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unrecognised date: \(raw)")
            }
            return date
        }
        return decoder
    }
}

extension JSONEncoder {
    public static var halo: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
