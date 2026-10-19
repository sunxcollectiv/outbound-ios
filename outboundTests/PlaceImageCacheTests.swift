//
//  PlaceImageCacheTests.swift
//  outboundTests
//

import Foundation
import Testing
import UIKit
@testable import outbound

/// How the in-memory cover photo cache saves repeat requests (each one a billed Google
/// Place Photo load) without remembering failures.
@MainActor
struct PlaceImageCacheTests {

    @Test func aLoadedImageIsServedFromMemory() async throws {
        let url = StubImageProtocol.url(status: 200)
        let cache = PlaceImageCache(protocolClasses: [StubImageProtocol.self])

        #expect(cache.cachedImage(for: url) == nil)
        #expect(await cache.image(for: url) != nil)
        #expect(await cache.image(for: url) != nil)

        #expect(cache.cachedImage(for: url) != nil)
        #expect(StubImageProtocol.requestCount(for: url) == 1)
    }

    @Test func concurrentLoadsShareOneRequest() async throws {
        let url = StubImageProtocol.url(status: 200)
        let cache = PlaceImageCache(protocolClasses: [StubImageProtocol.self])

        async let first = cache.image(for: url)
        async let second = cache.image(for: url)
        let images = await [first, second]

        #expect(images.allSatisfy { $0 != nil })
        #expect(StubImageProtocol.requestCount(for: url) == 1)
    }

    @Test func aFailedLoadIsRetriedNextTime() async throws {
        let url = StubImageProtocol.url(status: 403)
        let cache = PlaceImageCache(protocolClasses: [StubImageProtocol.self])

        #expect(await cache.image(for: url) == nil)
        #expect(await cache.image(for: url) == nil)

        #expect(cache.cachedImage(for: url) == nil)
        #expect(StubImageProtocol.requestCount(for: url) == 2)
    }
}

/// Answers image requests locally: a 1×1 PNG with the status code named in the URL's
/// `status` query item. Counts requests per URL; each test uses its own URL, so the
/// counts stay apart when tests run in parallel.
private final class StubImageProtocol: URLProtocol {
    nonisolated(unsafe) private static var counts: [URL: Int] = [:]
    private static let lock = NSLock()

    static func url(status: Int) -> URL {
        URL(string: "https://stub.test/\(UUID().uuidString)/media?status=\(status)")!
    }

    static func requestCount(for url: URL) -> Int {
        lock.withLock { counts[url, default: 0] }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.lock.withLock { Self.counts[url, default: 0] += 1 }

        let status = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "status" }?.value.flatMap(Int.init) ?? 200
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: status == 200 ? Self.pixel : Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static let pixel = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
    }
}
