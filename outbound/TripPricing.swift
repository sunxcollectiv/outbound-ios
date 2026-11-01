//
//  TripPricing.swift
//  outbound
//

import Foundation

/// What a trip costs to unlock, by its length. Each day is charged at the rate of the
/// bracket it falls in, like tax brackets: the first 3 days at $1.60, the next 6 at
/// $0.80, and so on, down to $0.20 a day after day 30. Amounts are whole cents.
enum TripPricing {
    /// A run of trip days charged at one rate. `lastDay` is nil for the open-ended
    /// bracket at the end.
    struct Bracket: Equatable {
        let firstDay: Int
        let lastDay: Int?
        let centsPerDay: Int
    }

    /// One bracket's share of a trip's price, for showing the breakdown.
    struct Line: Equatable {
        let firstDay: Int
        let lastDay: Int
        let centsPerDay: Int

        var days: Int { lastDay - firstDay + 1 }
        var cents: Int { days * centsPerDay }
    }

    static let brackets: [Bracket] = [
        Bracket(firstDay: 1, lastDay: 3, centsPerDay: 160),
        Bracket(firstDay: 4, lastDay: 9, centsPerDay: 80),
        Bracket(firstDay: 10, lastDay: 16, centsPerDay: 70),
        Bracket(firstDay: 17, lastDay: 23, centsPerDay: 50),
        Bracket(firstDay: 24, lastDay: 30, centsPerDay: 30),
        Bracket(firstDay: 31, lastDay: nil, centsPerDay: 20),
    ]

    /// The brackets a trip of `days` days touches, each cut off at the trip's last day.
    static func breakdown(days: Int) -> [Line] {
        brackets.compactMap { bracket in
            guard days >= bracket.firstDay else { return nil }
            let lastDay = min(days, bracket.lastDay ?? days)
            return Line(firstDay: bracket.firstDay, lastDay: lastDay, centsPerDay: bracket.centsPerDay)
        }
    }

    /// The price of a trip of `days` days, in cents; 0 for no days.
    static func priceCents(days: Int) -> Int {
        breakdown(days: days).reduce(0) { $0 + $1.cents }
    }
}

extension Trip {
    /// How many days the trip spans, counting both its first and last day, or nil if
    /// its dates don't parse.
    var dayCount: Int? {
        guard let range = dateRange else { return nil }
        let days = Calendar(identifier: .gregorian)
            .dateComponents([.day], from: range.lowerBound, to: range.upperBound).day ?? 0
        return days + 1
    }

    /// What unlocking the trip costs, in cents, or nil if its dates don't parse.
    var priceCents: Int? {
        dayCount.map { TripPricing.priceCents(days: $0) }
    }
}
