//
//  TripPricing.swift
//  outbound
//

import Foundation

/// What a trip costs to unlock, by its length and size. Each day is charged at the rate
/// of the bracket it falls in, like tax brackets: the first 3 days at $1.60, the next 6
/// at $0.80, and so on, down to $0.20 a day after day 30. That covers up to
/// `includedMembers` people; each one beyond adds their own daily rate, from $0.20
/// down to $0.05. Amounts are whole cents.
enum TripPricing {
    /// A run of trip days charged at one rate. `lastDay` is nil for the open-ended
    /// bracket at the end.
    struct Bracket: Equatable {
        let firstDay: Int
        let lastDay: Int?
        let centsPerDay: Int
    }

    /// One bracket's share of a trip's price, for showing the breakdown. Also how the
    /// server's quote lists it (`BracketLineRead`).
    struct Line: Equatable, Decodable {
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

    /// How many people the trip's own rate covers, owner included.
    static let includedMembers = 5

    /// What each member beyond `includedMembers` adds, per trip day.
    ///
    /// A member is added to the whole trip (there's no joining for only some days), so
    /// each extra member is charged for every day of it. See `priceCents(days:members:)`.
    static let memberBrackets: [Bracket] = [
        Bracket(firstDay: 1, lastDay: 7, centsPerDay: 20),
        Bracket(firstDay: 8, lastDay: 14, centsPerDay: 15),
        Bracket(firstDay: 15, lastDay: 30, centsPerDay: 10),
        Bracket(firstDay: 31, lastDay: nil, centsPerDay: 5),
    ]

    /// The trip brackets a trip of `days` days touches, each cut off at its last day.
    static func breakdown(days: Int) -> [Line] {
        lines(of: brackets, days: days)
    }

    /// The member brackets a trip of `days` days touches, for one extra member.
    static func memberBreakdown(days: Int) -> [Line] {
        lines(of: memberBrackets, days: days)
    }

    /// The price of a trip of `days` days for up to `includedMembers` people, in
    /// cents; 0 for no days.
    static func priceCents(days: Int) -> Int {
        total(of: breakdown(days: days))
    }

    /// What one member beyond `includedMembers` adds to a trip of `days` days, in cents.
    static func extraMemberCents(days: Int) -> Int {
        total(of: memberBreakdown(days: days))
    }

    /// The price of a trip of `days` days with `members` people, in cents: every extra
    /// member is on the whole trip, so each is charged for every day.
    static func priceCents(days: Int, members: Int) -> Int {
        priceCents(days: days) + max(members - includedMembers, 0) * extraMemberCents(days: days)
    }

    /// The longest trip `budgetCents` pays for with `members` people, in days; 0 if it
    /// doesn't cover a single day.
    static func maxDays(budgetCents: Int, members: Int = includedMembers) -> Int {
        // Every day costs at least the last brackets' rates, so this stops.
        var days = 0
        while priceCents(days: days + 1, members: members) <= budgetCents {
            days += 1
        }
        return days
    }

    private static func lines(of brackets: [Bracket], days: Int) -> [Line] {
        brackets.compactMap { bracket in
            guard days >= bracket.firstDay else { return nil }
            let lastDay = min(days, bracket.lastDay ?? days)
            return Line(firstDay: bracket.firstDay, lastDay: lastDay, centsPerDay: bracket.centsPerDay)
        }
    }

    private static func total(of lines: [Line]) -> Int {
        lines.reduce(0) { $0 + $1.cents }
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

    /// What unlocking the trip costs for everyone on it, in cents, or nil if its dates
    /// don't parse. A trip whose members haven't loaded is priced as the base trip.
    var priceCents: Int? {
        dayCount.map { TripPricing.priceCents(days: $0, members: members?.count ?? 0) }
    }
}
