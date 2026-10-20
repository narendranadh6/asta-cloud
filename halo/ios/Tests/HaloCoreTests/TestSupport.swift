import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(HaloCore)
@testable import HaloCore
#else
@testable import Halo
#endif

private final class BundleToken {}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: BundleToken.self)
        #endif
        let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
            ?? bundle.url(forResource: name, withExtension: "json")
        guard let url else { throw XCTSkip("Missing fixture \(name).json") }
        return try Data(contentsOf: url)
    }
}

/// Scripted HTTP transport: each request is answered by the next queued responder.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    typealias Responder = @Sendable (URLRequest) throws -> (Int, Data, [String: String])

    private let lock = NSLock()
    private var responders: [Responder] = []
    private(set) var requests: [URLRequest] = []

    func enqueue(_ responder: @escaping Responder) {
        lock.lock(); defer { lock.unlock() }
        responders.append(responder)
    }

    func enqueue(status: Int, json: String, headers: [String: String] = [:]) {
        enqueue { _ in (status, Data(json.utf8), headers) }
    }

    func enqueue(status: Int, data: Data) {
        enqueue { _ in (status, data, [:]) }
    }

    func enqueue(error: Error) {
        enqueue { _ in throw error }
    }

    var recorded: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    private func nextResponder(for request: URLRequest) -> Responder? {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        return responders.isEmpty ? nil : responders.removeFirst()
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let responder = nextResponder(for: request) else {
            throw URLError(.badServerResponse)
        }
        let (status, data, headers) = try responder(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: headers)!
        return (data, response)
    }
}
