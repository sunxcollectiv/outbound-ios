//
//  ResponseCacheTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// How the API client saves responses to show offline: only for endpoints that ask,
/// only on success, and gone once cleared.
@MainActor
struct ResponseCacheTests {
    private struct Payload: Codable, Equatable { let name: String }

    private let cache = ResponseCache(directory: URL.temporaryDirectory.appending(path: "ResponseCacheTests-\(UUID().uuidString)"))

    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubAPIProtocol.self]
        let client = APIClient(baseURL: URL(string: "https://stub.test")!, session: URLSession(configuration: config), cache: cache)
        client.token = "token"
        return client
    }

    @Test func aSuccessfulResponseIsSavedAndReadBack() async throws {
        let endpoint = Endpoint(path: "/ok/\(UUID().uuidString)", cachesResponse: true)
        let api = client()

        #expect(api.cached(endpoint, as: Payload.self) == nil)
        let live = try await api.send(endpoint, as: Payload.self)

        #expect(api.cached(endpoint, as: Payload.self) == live)
        #expect(api.cachedDate(for: endpoint) != nil)
    }

    @Test func endpointsThatDontAskAreNotSaved() async throws {
        let endpoint = Endpoint(path: "/ok/\(UUID().uuidString)")
        let api = client()

        _ = try await api.send(endpoint, as: Payload.self)

        #expect(api.cached(endpoint, as: Payload.self) == nil)
    }

    @Test func aFailedRequestKeepsTheEarlierCopy() async throws {
        let id = UUID().uuidString
        let api = client()
        let saved = Payload(name: "saved")
        api.storeCached(saved, for: Endpoint(path: "/fail/\(id)", cachesResponse: true))

        await #expect(throws: APIError.self) {
            try await api.send(Endpoint(path: "/fail/\(id)", cachesResponse: true), as: Payload.self)
        }

        #expect(api.cached(Endpoint(path: "/fail/\(id)"), as: Payload.self) == saved)
    }

    @Test func clearingRemovesEverything() async throws {
        let endpoint = Endpoint(path: "/ok/\(UUID().uuidString)", cachesResponse: true)
        let api = client()
        _ = try await api.send(endpoint, as: Payload.self)

        cache.removeAll()

        #expect(api.cached(endpoint, as: Payload.self) == nil)
    }
}

/// Answers API requests locally: paths under `/ok/` get a JSON payload, anything else
/// a 500.
private final class StubAPIProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let ok = url.path().hasPrefix("/ok/")
        let response = HTTPURLResponse(url: url, statusCode: ok ? 200 : 500, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((ok ? #"{"name": "live"}"# : #"{"detail": "boom"}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
