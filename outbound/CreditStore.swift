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
    /// Paid for, but the server refused to credit it (`errorMessage` says why).
    case refused
    case failed
}

/// Loads and holds the signed-in user's credits, and buys more through the App Store.
///
/// A purchase is only finished with StoreKit once the server has credited it, so one
/// the server didn't get (offline, an error) is sent again from
/// `Transaction.unfinished` until it's credited. One the server refuses isn't sent
/// again on every load (see `deliver`).
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
    /// Purchases the server refused but that may yet be credited (see `deliver`): left
    /// unfinished, but not sent again until the next launch or sign-in, which starts a
    /// new store.
    private var heldTransactionIDs: Set<UInt64> = []

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
    /// `accountId` (the signed-in user's id) tags the purchase as theirs, so the
    /// server won't credit it to anyone else.
    func purchase(cents: Int, accountId: String?) async -> CreditPurchaseOutcome {
        guard purchasingCents == nil else { return .failed }
        await loadProducts()
        guard let product = products[cents] else {
            errorMessage = "Credits can't be purchased right now. Please try again later."
            return .failed
        }
        purchasingCents = cents
        defer { purchasingCents = nil }
        do {
            let options: Set<Product.PurchaseOption> = accountId
                .flatMap(UUID.init(uuidString:))
                .map { [.appAccountToken($0)] } ?? []
            switch try await product.purchase(options: options) {
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
            guard !heldTransactionIDs.contains(result.unsafePayloadValue.id) else { continue }
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
        } catch let error as APIError {
            return await handleRefusal(error, of: transaction)
        } catch {
            return .awaitingCredit
        }
    }

    /// What to do with a purchase the server didn't credit, by why. Only a purchase that
    /// can never be credited here is finished; finishing one that could be would lose
    /// what the user paid for.
    private func handleRefusal(_ error: APIError, of transaction: Transaction) async -> CreditPurchaseOutcome {
        guard case .server(let status, let message) = error else { return .awaitingCredit }
        switch status {
        case 409:
            // Already credited to another account: done, and sending it again changes
            // nothing.
            await transaction.finish()
            errorMessage = "These credits were already added to another account."
            return .refused
        case 403, 422:
            // 403: bought for another account, whose owner may sign in here later.
            // 422: couldn't be verified, which a misconfigured server can cause too.
            // Kept unfinished, but not sent again until the next launch or sign-in.
            heldTransactionIDs.insert(transaction.id)
            errorMessage = message ?? "Your purchase couldn't be added to this account."
            return .refused
        default:
            // Unreachable, unauthorized or a server error: worth trying again.
            return .awaitingCredit
        }
    }
}
