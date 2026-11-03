//
//  TripQuote.swift
//  outbound
//

import Foundation

/// `TripQuote` from `POST /trips/quote` and `POST /trips/{id}/quote`: what saving a trip
/// would charge the user, against their credits, and how that price is made up.
struct TripQuote: Decodable, Equatable {
    /// Trip days and people the price is for, and how many of those people are beyond
    /// the included ones.
    let days: Int
    let members: Int
    let extraMembers: Int
    /// What the save would take from the user's credits; 0 when nothing is due (e.g. an
    /// edit that doesn't add days or people). Sent back as `expectedPriceCents`.
    let priceCents: Int
    /// What an edit that lowers the price would give back instead.
    let refundCents: Int
    /// The user's credits now.
    let balanceCents: Int
    /// How much the price is over the balance; 0 when the credits cover it.
    let shortfallCents: Int
    /// The price's breakdown: each trip-day bracket, then each extra-member bracket.
    let tripLines: [TripPricing.Line]
    let memberLines: [TripPricing.Line]

    /// The balance once the price is taken.
    var balanceAfterCents: Int { balanceCents - priceCents }
}
