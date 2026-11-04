//
//  CreditsAPI.swift
//  outbound
//

import Foundation

/// The signed-in user's credits: their balance and ledger, and crediting a store purchase.
enum CreditsAPI {
    /// `CreditsRead`: the balance, and the ledger behind it, newest first.
    struct Credits: Codable, Equatable {
        let balanceCents: Int
        let entries: [CreditLedgerEntry]
    }

    /// `CreditPurchaseCreate`: a completed App Store purchase, as StoreKit signed it
    /// (`VerificationResult.jwsRepresentation`). The server checks the signature and
    /// credits the purchase once, keyed by its transaction id.
    struct PurchaseRequest: Encodable {
        let signedTransaction: String
    }

    static let read = Endpoint(path: "/credits", cachesResponse: true)

    /// Credits a purchase and returns the credits after it. Sending one that's already
    /// credited returns the credits unchanged, so a retry is safe.
    static func purchase(signedTransaction: String) -> Endpoint {
        Endpoint(path: "/credits/purchases", method: .post, body: PurchaseRequest(signedTransaction: signedTransaction))
    }
}
