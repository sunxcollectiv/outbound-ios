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
/// credits it or can never credit it; one it might yet credit is kept.
///
/// The purchase tests are opt-in: they make real StoreKit test purchases, and where the
/// test session can't turn off the purchase sheet (e.g. `xcodebuild` on the command
/// line) the sheet opens and waits for a tap that never comes. Turn them on with
/// `RUN_STOREKIT_TESTS=1` in the test environment: in the scheme's Test action from
/// Xcode, or `TEST_RUNNER_RUN_STOREKIT_TESTS=1 xcodebuild test …` on the command line.
/// The product check needs no sheet and always runs (skipped if StoreKit testing isn't
/// up at all).
@MainActor
@Suite(.serialized)
struct CreditStoreTests {
    /// Whether the purchase tests were asked for (see above).
    nonisolated static let purchasesOptedIn = ProcessInfo.processInfo.environment["RUN_STOREKIT_TESTS"] == "1"

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

    /// A store whose server answers purchases with `purchaseStatus`, after checking
    /// StoreKit testing is up; skips the test if it isn't.
    private func store(purchaseStatus: Int = 200) async throws -> CreditStore {
        StubCreditsProtocol.purchaseStatus = purchaseStatus
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubCreditsProtocol.self]
        let cache = ResponseCache(directory: URL.temporaryDirectory.appending(path: "CreditStoreTests-\(UUID().uuidString)"))
        let api = APIClient(baseURL: URL(string: "https://stub.test")!, session: URLSession(configuration: config), cache: cache)
        api.token = "token"
        let credits = CreditStore(api: api)
        await credits.loadProducts()
        if credits.products.isEmpty {
            try Test.cancel("StoreKit testing isn't running; run these from Xcode (⌘U).")
        }
        return credits
    }

    private func unfinishedProductIDs() async -> [String] {
        var ids: [String] = []
        for await result in Transaction.unfinished {
            if case .verified(let transaction) = result { ids.append(transaction.productID) }
        }
        return ids
    }

    @Test func everyAmountOnOfferIsAProduct() async throws {
        let credits = try await store()

        #expect(Set(credits.products.keys) == Set(PurchasePopup.amountsCents))
        #expect(credits.products[1_500]?.price == 15)
        #expect(credits.products.values.allSatisfy { $0.type == .consumable })
    }

    @Test(.enabled(if: CreditStoreTests.purchasesOptedIn, "Opt-in: set RUN_STOREKIT_TESTS=1 (opens StoreKit purchase sheets)"))
    func aCreditedPurchaseUpdatesTheBalanceAndIsFinished() async throws {
        let credits = try await store()

        let outcome = await credits.purchase(cents: 1_500, accountId: nil)

        #expect(outcome == .credited)
        #expect(credits.balanceCents == 1_500)
        #expect(credits.entries.first?.title == "Credits purchased")
        #expect(await unfinishedProductIDs().isEmpty)
    }

    @Test(.enabled(if: CreditStoreTests.purchasesOptedIn, "Opt-in: set RUN_STOREKIT_TESTS=1 (opens StoreKit purchase sheets)"))
    func aPurchaseTheServerDidntGetIsKeptAndSentAgain() async throws {
        let credits = try await store(purchaseStatus: 503)

        let outcome = await credits.purchase(cents: 500, accountId: nil)

        #expect(outcome == .awaitingCredit)
        #expect(await unfinishedProductIDs() == ["earth.outbound.credits.500"])

        // The server comes back: the next load sends it again and finishes it.
        StubCreditsProtocol.purchaseStatus = 200
        await credits.load()
        #expect(await unfinishedProductIDs().isEmpty)
        #expect(credits.balanceCents == 1_500)
    }

    @Test(.enabled(if: CreditStoreTests.purchasesOptedIn, "Opt-in: set RUN_STOREKIT_TESTS=1 (opens StoreKit purchase sheets)"))
    func aPurchaseCreditedToAnotherAccountIsFinished() async throws {
        let credits = try await store(purchaseStatus: 409)

        let outcome = await credits.purchase(cents: 500, accountId: nil)

        #expect(outcome == .refused)
        #expect(credits.errorMessage != nil)
        #expect(await unfinishedProductIDs().isEmpty)
    }

    @Test(.enabled(if: CreditStoreTests.purchasesOptedIn, "Opt-in: set RUN_STOREKIT_TESTS=1 (opens StoreKit purchase sheets)"), arguments: [403, 422])
    func aPurchaseThatMayYetBeCreditedIsKeptButNotResentEveryLoad(status: Int) async throws {
        let credits = try await store(purchaseStatus: status)

        let outcome = await credits.purchase(cents: 500, accountId: nil)

        #expect(outcome == .refused)
        #expect(await unfinishedProductIDs() == ["earth.outbound.credits.500"])

        // Loading again doesn't send it again in this session.
        StubCreditsProtocol.purchaseRequests = 0
        await credits.load()
        #expect(StubCreditsProtocol.purchaseRequests == 0)

        // A new session (next launch or sign-in) tries it again.
        StubCreditsProtocol.purchaseStatus = 200
        let next = try await store()
        await next.load()
        #expect(await unfinishedProductIDs().isEmpty)
    }
}

/// Answers `/credits` as the server does, in its snake_case shape, and
/// `/credits/purchases` with `purchaseStatus` (the credits on success, an error
/// otherwise), counting purchase requests.
private final class StubCreditsProtocol: URLProtocol {
    nonisolated(unsafe) static var purchaseStatus = 200
    nonisolated(unsafe) static var purchaseRequests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static let credits = """
    {"balance_cents": 1500, "entries": [{"id": "6f1c1f43-7c55-4c1e-9d0a-0c2f2b7e1a11", "kind": "purchase",
     "amount_cents": 1500, "trip_id": null, "description": null, "created_at": "2026-11-04T10:00:00.123456Z",
     "title": "Credits purchased"}]}
    """

    override func startLoading() {
        guard let url = request.url else { return }
        let isPurchase = url.path() == "/credits/purchases"
        if isPurchase { Self.purchaseRequests += 1 }
        let status = isPurchase ? Self.purchaseStatus : 200
        let ok = (200..<300).contains(status)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((ok ? Self.credits : #"{"detail": "Refused"}"#).utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
