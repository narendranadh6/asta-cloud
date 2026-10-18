import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Body shape of every backend error: {"error": {"code", "message", "details", "request_id"}}
struct APIErrorEnvelope: Decodable {
    struct Payload: Decodable {
        var code: String
        var message: String
        var requestId: String?
    }

    var error: Payload
}

public enum APIError: Error, Equatable, Sendable, LocalizedError {
    /// Device is offline or the connection dropped.
    case offline
    case timedOut
    case transport(message: String)
    /// Server returned a structured error.
    case server(status: Int, code: String, message: String, retryAfter: TimeInterval?)
    case decoding(message: String)
    case notConfigured

    public var errorDescription: String? {
        switch self {
        case .offline: "You're offline. Saved music is still available."
        case .timedOut: "The request took too long. Please try again."
        case .transport: "Couldn't reach MUSE. Please try again."
        case let .server(_, _, message, _): message
        case .decoding: "MUSE received an unexpected response."
        case .notConfigured: "The MUSE server address isn't configured."
        }
    }

    public var code: String? {
        if case let .server(_, code, _, _) = self { return code }
        return nil
    }

    public var status: Int? {
        if case let .server(status, _, _, _) = self { return status }
        return nil
    }

    /// Whether automatically retrying the same request could succeed.
    public var isTransient: Bool {
        switch self {
        case .offline, .timedOut, .transport: true
        case let .server(status, _, _, _): status == 502 || status == 503 || status == 504
        case .decoding, .notConfigured: false
        }
    }

    public var requiresReauthentication: Bool {
        guard case let .server(status, code, _, _) = self, status == 401 else { return false }
        return ["invalid_token", "token_expired", "account_deleted", "unauthenticated"]
            .contains(code)
    }

    static func from(urlError: URLError) -> APIError {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed,
             .internationalRoamingOff:
            .offline
        case .timedOut:
            .timedOut
        default:
            .transport(message: urlError.localizedDescription)
        }
    }

    static func from(status: Int, data: Data, headers: [AnyHashable: Any]) -> APIError {
        let retryAfter = (headers["Retry-After"] as? String).flatMap(TimeInterval.init)
            ?? (headers["retry-after"] as? String).flatMap(TimeInterval.init)
        if let envelope = try? JSONDecoder.muse.decode(APIErrorEnvelope.self, from: data) {
            return .server(
                status: status, code: envelope.error.code, message: envelope.error.message,
                retryAfter: retryAfter)
        }
        return .server(
            status: status, code: "http_\(status)",
            message: "Something went wrong (\(status)). Please try again.", retryAfter: retryAfter)
    }
}
