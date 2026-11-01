//
//  TripPricingTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct TripPricingTests {
    @Test(arguments: [
        (0, 0), (1, 160), (3, 480), (4, 560), (7, 800), (9, 960), (10, 1030),
        (14, 1310), (16, 1450), (17, 1500), (21, 1700), (23, 1800), (24, 1830),
        (30, 2010), (31, 2030), (45, 2310), (60, 2610), (90, 3210),
    ])
    func priceForLength(days: Int, cents: Int) {
        #expect(TripPricing.priceCents(days: days) == cents)
    }

    @Test func eachExtraDayNeverCostsMoreThanTheOneBefore() {
        let perDay = (1...60).map { TripPricing.priceCents(days: $0) - TripPricing.priceCents(days: $0 - 1) }
        #expect(zip(perDay, perDay.dropFirst()).allSatisfy { $0 >= $1 })
    }

    @Test func bracketsRunBackToBack() {
        let brackets = TripPricing.brackets
        #expect(brackets.first?.firstDay == 1)
        #expect(brackets.last?.lastDay == nil)
        for (bracket, next) in zip(brackets, brackets.dropFirst()) {
            #expect(bracket.lastDay.map { $0 + 1 } == next.firstDay)
        }
    }

    @Test func breakdownCutsOffAtTheLastDay() {
        #expect(TripPricing.breakdown(days: 5) == [
            .init(firstDay: 1, lastDay: 3, centsPerDay: 160),
            .init(firstDay: 4, lastDay: 5, centsPerDay: 80),
        ])
        #expect(TripPricing.breakdown(days: 35).last == .init(firstDay: 31, lastDay: 35, centsPerDay: 20))
    }

    @Test func tripDayCountIncludesBothEnds() {
        var trip = Trip.sample
        trip.startDate = "2026-11-01"
        trip.endDate = "2026-11-05"
        #expect(trip.dayCount == 5)
        #expect(trip.priceCents == 640)

        trip.endDate = "2026-11-01"
        #expect(trip.dayCount == 1)

        // Across the US daylight saving change, which a 23- or 25-hour day mustn't skew.
        trip.startDate = "2026-10-31"
        trip.endDate = "2026-11-02"
        #expect(trip.dayCount == 3)
    }
}
