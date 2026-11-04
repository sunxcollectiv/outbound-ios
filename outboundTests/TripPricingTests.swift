//
//  TripPricingTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// The formula, on a copy of the server's "2026-11" rates (the schedules themselves
/// come from the server). Expected prices match the server's `app.services.pricing`.
struct TripPricingTests {
    private let rates = PricingSchedule.rates2026_11

    @Test(arguments: [
        (0, 0), (1, 160), (3, 480), (4, 560), (7, 800), (9, 960), (10, 1030),
        (14, 1310), (16, 1450), (17, 1500), (21, 1700), (23, 1800), (24, 1830),
        (30, 2010), (31, 2030), (45, 2310), (60, 2610), (90, 3210),
    ])
    func priceForLength(days: Int, cents: Int) {
        #expect(rates.priceCents(days: days) == cents)
    }

    @Test func eachExtraDayNeverCostsMoreThanTheOneBefore() {
        let perDay = (1...60).map { rates.priceCents(days: $0) - rates.priceCents(days: $0 - 1) }
        #expect(zip(perDay, perDay.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test func bracketsRunBackToBack() {
        let brackets = rates.tripBrackets
        #expect(brackets.first?.firstDay == 1)
        #expect(brackets.last?.lastDay == nil)
        for (bracket, next) in zip(brackets, brackets.dropFirst()) {
            #expect(bracket.lastDay.map { $0 + 1 } == next.firstDay)
        }
    }

    @Test func breakdownCutsOffAtTheLastDay() {
        #expect(rates.breakdown(days: 5) == [
            .init(firstDay: 1, lastDay: 3, centsPerDay: 160),
            .init(firstDay: 4, lastDay: 5, centsPerDay: 80),
        ])
        #expect(rates.breakdown(days: 35).last == .init(firstDay: 31, lastDay: 35, centsPerDay: 20))
    }

    @Test(arguments: [
        // (days, members, cents)
        (3, 5, 480), (3, 6, 540), (3, 10, 755),
        (7, 8, 1165), (9, 6, 1140), (10, 10, 1655),
        (14, 7, 1765), (16, 9, 2145), (30, 10, 3135),
        (45, 6, 2910), (90, 10, 5835),
    ])
    func priceWithMembers(days: Int, members: Int, cents: Int) {
        #expect(rates.priceCents(days: days, members: members) == cents)
    }

    @Test func membersUpToTheIncludedCountCostNothingExtra() {
        for members in 0...rates.includedMembers {
            #expect(rates.priceCents(days: 12, members: members) == rates.priceCents(days: 12))
        }
    }

    @Test(arguments: [
        // (extra people, days, cents): bracketed over extra people × days together.
        (1, 1, 20), (1, 10, 200), (2, 5, 200), (3, 5, 275), (1, 15, 275), (1, 40, 575), (5, 9, 600),
    ])
    func extraMembersAreChargedByTheMemberDay(extra: Int, days: Int, cents: Int) {
        #expect(rates.memberCents(days: days, members: rates.includedMembers + extra) == cents)
        #expect(rates.memberDays(days: days, members: rates.includedMembers + extra) == extra * days)
    }

    @Test func theSameMemberDaysCostTheSame() {
        let five = rates.includedMembers
        // 3 extra people for 5 days, or 1 for 15: 15 member-days either way.
        #expect(rates.memberCents(days: 5, members: five + 3) == rates.memberCents(days: 15, members: five + 1))
        // 1 extra person for 10 days, or 2 for 5.
        #expect(rates.memberCents(days: 10, members: five + 1) == rates.memberCents(days: 5, members: five + 2))
    }

    @Test func memberBreakdownRunsOverTheMemberDays() {
        #expect(rates.memberBreakdown(memberDays: 15) == [
            .init(firstDay: 1, lastDay: 10, centsPerDay: 20),
            .init(firstDay: 11, lastDay: 15, centsPerDay: 15),
        ])
        #expect(rates.memberBreakdown(memberDays: 0).isEmpty)
    }

    @Test(arguments: [
        // (budget, members, days)
        (0, 5, 0), (159, 5, 0), (160, 5, 1), (500, 5, 3),
        (1_500, 5, 17), (2_500, 5, 54), (5_000, 5, 179), (1_500, 10, 8),
    ])
    func maxDaysForBudget(budgetCents: Int, members: Int, days: Int) {
        #expect(rates.maxDays(budgetCents: budgetCents, members: members) == days)
    }

    @Test func maxDaysIsTheLongestTripTheBudgetCovers() {
        for budget in stride(from: 160, through: 5_000, by: 35) {
            let days = rates.maxDays(budgetCents: budget, members: 5)
            #expect(rates.priceCents(days: days, members: 5) <= budget)
            #expect(rates.priceCents(days: days + 1, members: 5) > budget)
        }
    }

    @Test func purchasePopupSaysWhatAnAmountPaysFor() {
        #expect(PurchasePopup.usableText(cents: 1_500, members: 5, schedule: rates) == "Usable for a 17-day trip with up to 5 members")
        #expect(PurchasePopup.usableText(cents: 500, members: 5, schedule: rates) == "Usable for a 3-day trip with up to 5 members")
        #expect(PurchasePopup.usableText(cents: 100, members: 5, schedule: rates) == "Not enough for a 1-day trip with 5 members")
        #expect(PurchasePopup.usableText(cents: 2_500, members: 5, schedule: rates) == "Usable for 3 separate 7-day trips with up to 5 members")
        #expect(PurchasePopup.usableText(cents: 5_000, members: 5, schedule: rates) == "Usable for 6 separate 7-day trips with up to 5 members")
    }

    @Test func memberBracketsRunBackToBack() {
        let brackets = rates.memberBrackets
        #expect(brackets.first?.firstDay == 1)
        #expect(brackets.last?.lastDay == nil)
        for (bracket, next) in zip(brackets, brackets.dropFirst()) {
            #expect(bracket.lastDay.map { $0 + 1 } == next.firstDay)
        }
    }

    @Test func tripPriceCountsItsMembers() {
        var trip = Trip.sample
        trip.startDate = "2026-11-01"
        trip.endDate = "2026-11-07"
        #expect(trip.priceCents(under: rates) == 800)

        trip.members = (1...8).map {
            TripMember(id: "m\($0)", email: "m\($0)@example.com", user: nil, role: $0 == 1 ? .organizer : .member)
        }
        // 3 extra people × 7 days = 21 member-days: 10 × $0.20 + 11 × $0.15.
        #expect(trip.priceCents(under: rates) == 1165)
    }

    @Test func tripDayCountIncludesBothEnds() {
        var trip = Trip.sample
        trip.startDate = "2026-11-01"
        trip.endDate = "2026-11-05"
        #expect(trip.dayCount == 5)
        #expect(trip.priceCents(under: rates) == 640)

        trip.endDate = "2026-11-01"
        #expect(trip.dayCount == 1)

        // Across the US daylight saving change, which a 23- or 25-hour day mustn't skew.
        trip.startDate = "2026-10-31"
        trip.endDate = "2026-11-02"
        #expect(trip.dayCount == 3)
    }
}

extension PricingSchedule {
    /// The server's "2026-11" schedule, as `GET /pricing/schedule` sends it.
    static let rates2026_11 = PricingSchedule(
        key: "2026-11",
        includedMembers: 5,
        tripBrackets: [
            .init(firstDay: 1, lastDay: 3, centsPerDay: 160),
            .init(firstDay: 4, lastDay: 9, centsPerDay: 80),
            .init(firstDay: 10, lastDay: 16, centsPerDay: 70),
            .init(firstDay: 17, lastDay: 23, centsPerDay: 50),
            .init(firstDay: 24, lastDay: 30, centsPerDay: 30),
            .init(firstDay: 31, lastDay: nil, centsPerDay: 20),
        ],
        memberBrackets: [
            .init(firstDay: 1, lastDay: 10, centsPerDay: 20),
            .init(firstDay: 11, lastDay: 25, centsPerDay: 15),
            .init(firstDay: 26, lastDay: 40, centsPerDay: 10),
            .init(firstDay: 41, lastDay: nil, centsPerDay: 5),
        ]
    )
}
