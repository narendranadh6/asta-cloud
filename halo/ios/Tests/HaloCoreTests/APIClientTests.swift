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

final class APIClientTests: XCTestCase {
    private let base = URL(string: "https://api.halo.test")!

    private func makeClient(_ transport: FakeTransport, token: String? = "tok",
                            retries: Int = 2) -> (APIClient, InMemoryTokenStore) {
        let store = InMemoryTokenStore(token: token)
        let client = APIClient(
            configuration: .init(baseURL: base, maxRetries: retries, retryBaseDelay: 0.001),
            transport: transport, tokens: store)
        return (client, store)
    }

    func testRegistersOnFirstUseAndStoresToken() async throws {
        let transport = FakeTransport()
        transport.enqueue(status: 201, data: try Fixture.data("token"))
        transport.enqueue(status: 200, data: try Fixture.data("search"))
        let (client, store) = makeClient(transport, token: nil)
        _ = try await client.search(query: "telugu", kind: .song, pageToken: nil, limit: 3)
        XCTAssertEqual(store.readToken(), "test-access-token")
        let requests = transport.recorded
        XCTAssertEqual(requests[0].url?.path, "/api/v1/auth/register")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"),
                       "Bearer test-access-token")
    }

    func testSearchEncodesQueryAndPagination() async throws {
        let transport = FakeTransport()
        transport.enqueue(status: 200, data: try Fixture.data("search"))
        let (client, _) = makeClient(transport)
        let response = try await client.search(
            query: "tum hi ho & more", kind: .remix, pageToken: "PAGE2", limit: 10)
        XCTAssertEqual(response.items.count, 3)
        let components = URLComponents(url: transport.recorded[0].url!, resolvingAgainstBaseURL: false)!
        let query = Dictionary(uniqueKeysWithValues: components.queryItems!.map { ($0.name, $0.value!) })
        XCTAssertEqual(query["q"], "tum hi ho & more")
        XCTAssertEqual(query["kind"], "remix")
        XCTAssertEqual(query["page_token"], "PAGE2")
        XCTAssertEqual(query["limit"], "10")
    }

    func testStructuredServerErrorsAreDecoded() async throws {
        let transport = FakeTransport()
        transport.enqueue(status: 404, data: try Fixture.data("error"))
        let (client, _) = makeClient(transport)
        do {
            _ = try await client.video(id: "AAAAAAAAAAA")
            XCTFail("expected error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "video_unavailable")
            XCTAssertEqual(error.status, 404)
            XCTAssertEqual(error.errorDescription,
                           "This video is unavailable, private, or region-blocked")
        }
    }

    func testInvalidVideoIDNeverHitsNetwork() async {
        let transport = FakeTransport()
        let (client, _) = makeClient(transport)
        do {
            _ = try await client.video(id: "../etc")
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(transport.recorded.isEmpty)
        }
    }

    func testRetriesTransientFailuresForGET() async throws {
        let transport = FakeTransport()
        transport.enqueue(error: URLError(.networkConnectionLost))
        transport.enqueue(status: 503, json: #"{"error":{"code":"search_unavailable","message":"x"}}"#,
                          headers: ["Retry-After": "0"])
        transport.enqueue(status: 200, data: try Fixture.data("search"))
        let (client, _) = makeClient(transport)
        let response = try await client.search(query: "x", kind: .song, pageToken: nil, limit: 3)
        XCTAssertEqual(response.items.count, 3)
        XCTAssertEqual(transport.recorded.count, 3)
    }

    func testDoesNotRetryNonIdempotentPOST() async throws {
        let transport = FakeTransport()
        transport.enqueue(status: 503, json: #"{"error":{"code":"search_unavailable","message":"x"}}"#)
        let (client, _) = makeClient(transport)
        do {
            _ = try await client.aiChat(AIChatRequest(message: "hi"))
            XCTFail("expected error")
        } catch let error as APIError {
            XCTAssertTrue(error.isTransient)
        }
        XCTAssertEqual(transport.recorded.count, 1)
    }

    func testOfflineIsReportedAfterRetries() async {
        let transport = FakeTransport()
        for _ in 0..<3 { transport.enqueue(error: URLError(.notConnectedToInternet)) }
        let (client, _) = makeClient(transport)
        do {
            _ = try await client.preferences()
            XCTFail("expected error")
        } catch let error as APIError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("unexpected \(error)")
        }
        XCTAssertEqual(transport.recorded.count, 3)
    }

    func testReauthenticatesOnceWhenTokenRejected() async throws {
        let transport = FakeTransport()
        transport.enqueue(status: 401, json: #"{"error":{"code":"token_expired","message":"expired"}}"#)
        transport.enqueue(status: 201, data: try Fixture.data("token"))
        transport.enqueue(status: 200, data: try Fixture.data("preferences"))
        let (client, store) = makeClient(transport, token: "old")
        let prefs = try await client.preferences()
        XCTAssertEqual(prefs.languages, ["Telugu"])
        XCTAssertEqual(store.readToken(), "test-access-token")
        XCTAssertEqual(transport.recorded.map(\.url!.path),
                       ["/api/v1/preferences", "/api/v1/auth/register", "/api/v1/preferences"])
    }

    func testRateLimitIsSurfacedNotRetried() async throws {
        let transport = FakeTransport()
        transport.enqueue(status: 429, json: #"{"error":{"code":"rate_limited","message":"Too many requests."}}"#,
                          headers: ["Retry-After": "30"])
        let (client, _) = makeClient(transport)
        do {
            _ = try await client.search(query: "x", kind: .song, pageToken: nil, limit: 3)
            XCTFail("expected error")
        } catch let error as APIError {
            XCTAssertEqual(error.code, "rate_limited")
            XCTAssertFalse(error.isTransient)
        }
        XCTAssertEqual(transport.recorded.count, 1)
    }

    func testRequestBodiesUseSnakeCase() async throws {
        let transport = FakeTransport()
        transport.enqueue(status: 201, data: try Fixture.data("playlist"))
        let (client, _) = makeClient(transport)
        _ = try await client.createPlaylist(PlaylistCreateRequest(
            name: "Evening", isAiGenerated: true, videoIds: ["dQw4w9WgXcQ"]))
        let body = try XCTUnwrap(transport.recorded[0].httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["video_ids"] as? [String], ["dQw4w9WgXcQ"])
        XCTAssertEqual(json["is_ai_generated"] as? Bool, true)
        XCTAssertEqual(transport.recorded[0].value(forHTTPHeaderField: "Content-Type"),
                       "application/json")
    }
}

extension APIClientTests {
    func testTrendingEndpoint() async throws {
        let transport = FakeTransport()
        transport.enqueue(status: 200, json: #"{"items":[],"next_page_token":"T2","prev_page_token":null,"provider":"youtube","cached":false,"source":"YouTube most popular music chart"}"#)
        let (client, _) = makeClient(transport)
        let response = try await client.trending(pageToken: nil, limit: 12)
        XCTAssertEqual(response.nextPageToken, "T2")
        XCTAssertEqual(response.provider, .youtube)
        XCTAssertEqual(transport.recorded[0].url?.path, "/api/v1/discover/trending")
    }
}

extension APIClientTests {
    func testUpNextAndRadioEndpoints() async throws {
        let transport = FakeTransport()
        transport.enqueue(status: 200, data: try Fixture.data("upnext"))
        transport.enqueue(status: 200, json: "[]")
        let (client, _) = makeClient(transport)
        _ = try await client.upNext(videoID: "dQw4w9WgXcQ", limit: 5)
        _ = try await client.radioStations(tag: "jazz", language: nil, query: "", limit: 20)
        let first = URLComponents(url: transport.recorded[0].url!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(first.path, "/api/v1/recommendations/next")
        XCTAssertEqual(first.queryItems?.first(where: { $0.name == "video_id" })?.value, "dQw4w9WgXcQ")
        let second = URLComponents(url: transport.recorded[1].url!, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(second.path, "/api/v1/radio/stations")
        XCTAssertEqual(Set(second.queryItems!.map(\.name)), ["limit", "tag"])  // empty q omitted
        do {
            _ = try await client.upNext(videoID: "bad", limit: 5)
            XCTFail("expected validation error")
        } catch {
            XCTAssertEqual(transport.recorded.count, 2)
        }
    }
}
