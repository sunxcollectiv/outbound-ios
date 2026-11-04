//
//  CreditStore.swift
//  outbound
//

import Foundation
import Observation
import StoreKit

/// The App Store products credits are sold as: one consumable per amount on offer.
/// They're set up in `Outbound.storekit` for local testing, and must match App Store
/// Connect for real purchases.
enum CreditProducts {
    /// Product ids by the credits they buy, in cents.
    static let idsByCents: [Int: String] = [
        500: "earth.outbound.credits.500",
        1_500: "earth.outbound.credits.1500",
        2_500: "earth.outbound.credits.2500",
        5_000: "earth.outbound.credits.5000",
    ]

    static func cents(forProductID id: String) -> Int? {
        idsByCents.first { $0.value == id }?.key
    }
}

/// How buying credits ended, for the popup to react to.
enum CreditPurchaseOutcome: Equatable {
    /// Paid for and credited; the balance is up to date.
    case credited
    /// Paid for, but the server hasn't credited it yet. It's kept and sent again on
    /// the next load, so the credits aren't lost.
    case awaitingCredit
    /// Waiting on approval (e.g. Ask to Buy); it's credited when approved.
    case pending
    case cancelled
    case failed
}

/// Loads and holds the signed-in user's credits, and buys more through the App Store.
///
/// A purchase is only finished with StoreKit once the server has credited it, so one
/// the server didn't get (offline, an error) is sent again from
/// `Transaction.unfinished` until it's credited.
@Observable
final class CreditStore {
    private(set) var credits: CreditsAPI.Credits?
    /// The App Store's products by the credits they buy, once loaded.
    private(set) var products: [Int: Product] = [:]
    /// The amount being bought, while a purchase is underway.
    private(set) var purchasingCents: Int?
    var errorMessage: String?

    private let api: APIClient
    private var isObservingTransactions = false

    init(api: APIClient = .shared) {
        self.api = api
        credits = api.cached(CreditsAPI.read)
    }

    var balanceCents: Int? { credits?.balanceCents }
    var entries: [CreditLedgerEntry] { credits?.entries ?? [] }

    /// Fetches the balance and ledger, after sending any purchase not yet credited.
    func load() async {
        await deliverUnfinished()
        do {
            credits = try await api.send(CreditsAPI.read, as: CreditsAPI.Credits.self)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetches the products from the App Store, unless they're already here.
    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let loaded = try await Product.products(for: Array(CreditProducts.idsByCents.values))
            products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in
                CreditProducts.cents(forProductID: product.id).map { ($0, product) }
            })
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Buys the product for `cents` of credits and has the server credit it.
    func purchase(cents: Int) async -> CreditPurchaseOutcome {
        guard purchasingCents == nil else { return .failed }
        await loadProducts()
        guard let product = products[cents] else {
            errorMessage = "Credits can't be purchased right now. Please try again later."
            return .failed
        }
        purchasingCents = cents
        defer { purchasingCents = nil }
        do {
            switch try await product.purchase() {
            case .success(let result):
                return await deliver(result)
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            errorMessage = error.localizedDescription
            return .failed
        }
    }

    /// Credits purchases that complete outside `purchase(cents:)`, e.g. one approved
    /// later through Ask to Buy, or interrupted by the app closing. Runs for as long as
    /// the calling task does; call it once from a long-lived view.
    func observeTransactions() async {
        guard !isObservingTransactions else { return }
        isObservingTransactions = true
        defer { isObservingTransactions = false }
        await deliverUnfinished()
        for await result in Transaction.updates {
            _ = await deliver(result)
        }
    }

    private func deliverUnfinished() async {
        for await result in Transaction.unfinished {
            _ = await deliver(result)
        }
    }

    /// Sends a purchase to the server and, once it's credited, finishes it.
    private func deliver(_ result: VerificationResult<Transaction>) async -> CreditPurchaseOutcome {
        guard case .verified(let transaction) = result else {
            errorMessage = "The App Store couldn't verify this purchase."
            return .failed
        }
        guard CreditProducts.cents(forProductID: transaction.productID) != nil else { return .failed }
        // Refunded or revoked: nothing to credit. The server learns of refunds from
        // the App Store, not from here.
        if transaction.revocationDate != nil {
            await transaction.finish()
            return .failed
        }
        do {
            let updated = try await api.send(
                CreditsAPI.purchase(signedTransaction: result.jwsRepresentation), as: CreditsAPI.Credits.self
            )
            credits = updated
            api.storeCached(updated, for: CreditsAPI.read)
            await transaction.finish()
            errorMessage = nil
            return .credited
        } catch {
            return .awaitingCredit
        }
    }
}
