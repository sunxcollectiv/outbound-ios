//
//  TripPricing.swift
//  outbound
//

import Foundation

/// How trips are priced. The formula is fixed; the rates come from the server as a
/// `PricingSchedule`, versioned so a rate change never reprices a trip that's already
/// paid for: each trip stays on the schedule it was created under.
enum TripPricing {
    /// A run of days charged at one rate (`BracketRead`): trip days, or extra
    /// member-days. `lastDay` is nil for the open-ended bracket at the end.
    struct Bracket: Codable, Equatable {
        let firstDay: Int
        let lastDay: Int?
        let centsPerDay: Int
    }

    /// One bracket's share of a trip's price, for showing the breakdown: the trip days,
    /// or extra member-days, that fell in it. Also how the server's quote lists it
    /// (`BracketLineRead`).
    struct Line: Equatable, Decodable {
        let firstDay: Int
        let lastDay: Int
        let centsPerDay: Int

        var days: Int { lastDay - firstDay + 1 }
        var cents: Int { days * centsPerDay }
    }
}

/// One version of the rates (`PricingScheduleRead`), and the formula applied to them.
///
/// Each trip day is charged at the rate of the bracket it falls in, like tax brackets.
/// That covers up to `includedMembers` people, owner included. People beyond that are
/// on the whole trip and charged by the member-day (one extra person for one day),
/// bracketed the same way over all the trip's extra member-days together: so 3 extra
/// people on a 5-day trip cost the same as 1 on a 15-day trip. Amounts are whole
/// cents. Mirrors the server's `app.services.pricing`.
struct PricingSchedule: Codable, Equatable {
    /// The version, e.g. "2026-11"; what a trip's `priceSchedule` and a quote's
    /// `schedule` name.
    let key: String
    /// How many people the trip's own rate covers, owner included.
    let includedMembers: Int
    let tripBrackets: [TripPricing.Bracket]
    /// Over the extra member-days: people beyond `includedMembers` × trip days.
    let memberBrackets: [TripPricing.Bracket]

    /// The trip brackets a trip of `days` days touches, each cut off at its last day.
    func breakdown(days: Int) -> [TripPricing.Line] {
        Self.lines(of: tripBrackets, days: days)
    }

    /// Extra member-days on a trip of `days` days with `members` people: those beyond
    /// `includedMembers` × days.
    func memberDays(days: Int, members: Int) -> Int {
        max(members - includedMembers, 0) * days
    }

    /// The member brackets `memberDays` extra member-days touch, each cut off at the last.
    func memberBreakdown(memberDays: Int) -> [TripPricing.Line] {
        Self.lines(of: memberBrackets, days: memberDays)
    }

    /// The price of a trip of `days` days for up to `includedMembers` people, in
    /// cents; 0 for no days.
    func priceCents(days: Int) -> Int {
        Self.total(of: breakdown(days: days))
    }

    /// What everyone beyond `includedMembers` adds to a trip of `days` days, together,
    /// in cents.
    func memberCents(days: Int, members: Int) -> Int {
        Self.total(of: memberBreakdown(memberDays: memberDays(days: days, members: members)))
    }

    /// The price of a trip of `days` days with `members` people, in cents.
    func priceCents(days: Int, members: Int) -> Int {
        priceCents(days: days) + memberCents(days: days, members: members)
    }

    /// The longest trip `budgetCents` pays for with `members` people, in days; 0 if it
    /// doesn't cover a single day.
    func maxDays(budgetCents: Int, members: Int) -> Int {
        // The open-ended brackets charge every further day, so this stops. A schedule
        // whose last brackets are free has no longest trip; cap the search.
        var days = 0
        while days < 10_000, priceCents(days: days + 1, members: members) <= budgetCents {
            days += 1
        }
        return days
    }

    private static func lines(of brackets: [TripPricing.Bracket], days: Int) -> [TripPricing.Line] {
        brackets.compactMap { bracket in
            guard days >= bracket.firstDay else { return nil }
            let lastDay = min(days, bracket.lastDay ?? days)
            return TripPricing.Line(firstDay: bracket.firstDay, lastDay: lastDay, centsPerDay: bracket.centsPerDay)
        }
    }

    private static func total(of lines: [TripPricing.Line]) -> Int {
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

    /// What the trip costs for everyone on it under `schedule` (its own, see
    /// `PricingStore.schedule(for:)`), in cents, or nil if its dates don't parse. A
    /// trip whose members haven't loaded is priced as the base trip.
    func priceCents(under schedule: PricingSchedule) -> Int? {
        dayCount.map { schedule.priceCents(days: $0, members: members?.count ?? 0) }
    }
}
