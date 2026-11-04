//
//  CreditStoreTests.swift
//  outboundTests
//

import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import outbound

/// Buying credits against `Outbound.storekit` (simulated App Store purchases, no
/// dialogs), with the server stubbed: a purchase is only finished once the server
/// credits it, and one it didn't is kept to send again.
@MainActor
@Suite(.serialized)
struct CreditStoreTests {
    private let session: SKTestSession

    init() throws {
        // The repo's StoreKit configuration, the one the app's Run scheme uses.
        let config = URL(filePath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Outbound.storekit")
        session = try SKTestSession(contentsOf: config)
        session.disableDialogs = true
        session.clearTransactions()
    }

    private func store(serverCredits: Bool) -> CreditStore {
        StubCreditsProtocol.creditsPurchases = serverCredits
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubCreditsProtocol.self]
        let cache = ResponseCache(directory: URL.temporaryDirectory.appending(path: "CreditStoreTests-\(UUID().uuidString)"))
        let api = APIClient(baseURL: URL(string: "https://stub.test")!, session: URLSession(configuration: config), cache: cache)
        api.token = "token"
        return CreditStore(api: api)
    }

    private func unfinishedProductIDs() async -> [String] {
        var ids: [String] = []
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result { ids.append(transaction.productID) }
        }
        return ids
    }

    @Test func everyAmountOnOfferIsAProduct() async {
        let credits = store(serverCredits: true)
        await credits.loadProducts()

        #expect(Set(credits.products.keys) == Set(PurchasePopup.amountsCents))
        #expect(credits.products[1_500]?.price == 15)
        #expect(credits.products.values.allSatisfy { $0.type == .consumable })
    }

    @Test func aCreditedPurchaseUpdatesTheBalanceAndIsFinished() async {
        let credits = store(serverCredits: true)

        let outcome = await credits.purchase(cents: 1_500, accountId: nil)

        #expect(outcome == .credited)
        #expect(credits.balanceCents == 1_500)
        #expect(credits.entries.first?.title == "Credits purchased")
        #expect(await unfinishedProductIDs().isEmpty)
    }

    @Test func aPurchaseTheServerDidntCreditIsKeptAndSentAgain() async {
        let credits = store(serverCredits: false)

        let outcome = await credits.purchase(cents: 500, accountId: nil)

        #expect(outcome == .awaitingCredit)
        #expect(await unfinishedProductIDs() == ["earth.outbound.credits.500"])

        // The server comes back: the next load sends it again and finishes it.
        StubCreditsProtocol.creditsPurchases = true
        await credits.load()
        #expect(await unfinishedProductIDs().isEmpty)
        #expect(credits.balanceCents == 1_500)
    }
}

/// Answers `/credits` and `/credits/purchases` as the server does, in its snake_case
/// shape; purchases get a 404 (as before the server has the endpoint) unless
/// `creditsPurchases` is set.
private final class StubCreditsProtocol: URLProtocol {
    nonisolated(unsafe) static var creditsPurchases = true

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static let credits = """
    {"balance_cents": 1500, "entries": [{"id": "6f1c1f43-7c55-4c1e-9d0a-0c2f2b7e1a11", "kind": "purchase",
     "amount_cents": 1500, "trip_id": null, "description": null, "created_at": "2026-11-04T10:00:00.123456Z",
     "title": "Credits purchased"}]}
    """

    override func startLoading() {
        guard let url = request.url else { return }
        let ok = url.path() == "/credits" || (url.path() == "/credits/purchases" && Self.creditsPurchases)
        let response = HTTPURLResponse(url: url, statusCode: ok ? 200 : 404, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((ok ? Self.credits : #"{"detail": "Not Found"}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
