//
//  PricingStoreTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// Loading pricing schedules from the server (stubbed): the current one, older ones by
/// key, a saved copy offline, and which schedule a trip is priced under.
@MainActor
@Suite(.serialized)
struct PricingStoreTests {
    private let cache = ResponseCache(directory: URL.temporaryDirectory.appending(path: "PricingStoreTests-\(UUID().uuidString)"))

    private func api(online: Bool = true) -> APIClient {
        StubPricingProtocol.online = online
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubPricingProtocol.self]
        return APIClient(baseURL: URL(string: "https://stub.test")!, session: URLSession(configuration: config), cache: cache)
    }

    @Test func theCurrentScheduleDecodesFromTheServersShape() async {
        let store = PricingStore(api: api())

        await store.loadCurrent()

        #expect(store.currentKey == "2026-11")
        #expect(store.current == .rates2026_11)
        #expect(store.schedule(key: nil) == .rates2026_11)
    }

    @Test func anOlderScheduleLoadsByKeyAlongsideTheCurrentOne() async {
        let store = PricingStore(api: api())
        await store.loadCurrent()

        await store.load(key: "2025-01")

        #expect(store.schedule(key: "2025-01")?.includedMembers == 4)
        #expect(store.schedule(key: "2025-01")?.priceCents(days: 2) == 400)
        #expect(store.current?.key == "2026-11")
    }

    @Test func eachTripUsesTheScheduleItNames() async {
        let store = PricingStore(api: api())
        var old = Trip.sample
        old.priceSchedule = "2025-01"
        var new = Trip.sample
        new.priceSchedule = "2026-11"
        var unnamed = Trip.sample
        unnamed.priceSchedule = nil

        await store.load(for: [old, new, unnamed])

        #expect(store.schedule(for: old)?.key == "2025-01")
        #expect(store.schedule(for: new)?.key == "2026-11")
        // Not assumed to be the current one, which could misprice an older trip.
        #expect(store.schedule(for: unnamed) == nil)
    }

    @Test func anUnknownKeyIsUnavailable() async {
        let store = PricingStore(api: api())

        await store.load(key: "1999-01")

        #expect(store.schedule(key: "1999-01") == nil)
        #expect(store.isUnavailable(key: "1999-01"))
    }

    @Test func savedSchedulesAreUsedOffline() async {
        let online = PricingStore(api: api())
        await online.loadCurrent()
        await online.load(key: "2025-01")

        let offline = PricingStore(api: api(online: false))
        #expect(offline.current == .rates2026_11)
        await offline.loadCurrent()
        await offline.load(key: "2025-01")

        #expect(offline.current == .rates2026_11)
        #expect(offline.schedule(key: "2025-01")?.key == "2025-01")
        #expect(!offline.isUnavailable(key: nil))
    }

    @Test func withNothingSavedOfflineTheCurrentScheduleIsUnavailable() async {
        let store = PricingStore(api: api(online: false))

        await store.loadCurrent()

        #expect(store.current == nil)
        #expect(store.isUnavailable(key: nil))
    }
}

/// Answers `/pricing/schedule` as the server does: the current "2026-11" schedule, or
/// "2025-01" by key; 404 for other keys. Fails every request when not `online`.
private final class StubPricingProtocol: URLProtocol {
    nonisolated(unsafe) static var online = true

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static let current = """
    {"key": "2026-11", "included_members": 5,
     "trip_brackets": [{"first_day": 1, "last_day": 3, "cents_per_day": 160}, {"first_day": 4, "last_day": 9, "cents_per_day": 80},
       {"first_day": 10, "last_day": 16, "cents_per_day": 70}, {"first_day": 17, "last_day": 23, "cents_per_day": 50},
       {"first_day": 24, "last_day": 30, "cents_per_day": 30}, {"first_day": 31, "last_day": null, "cents_per_day": 20}],
     "member_brackets": [{"first_day": 1, "last_day": 10, "cents_per_day": 20}, {"first_day": 11, "last_day": 25, "cents_per_day": 15},
       {"first_day": 26, "last_day": 40, "cents_per_day": 10}, {"first_day": 41, "last_day": null, "cents_per_day": 5}]}
    """

    private static let older = """
    {"key": "2025-01", "included_members": 4,
     "trip_brackets": [{"first_day": 1, "last_day": null, "cents_per_day": 200}],
     "member_brackets": [{"first_day": 1, "last_day": null, "cents_per_day": 25}]}
    """

    override func startLoading() {
        guard let url = request.url else { return }
        guard Self.online else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let key = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "key" }?.value
        let body: String? = switch key {
        case nil, "2026-11": Self.current
        case "2025-01": Self.older
        default: nil
        }
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((body ?? #"{"detail": "No such price schedule"}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
