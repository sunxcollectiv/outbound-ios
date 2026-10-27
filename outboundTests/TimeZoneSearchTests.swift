//
//  TimeZoneSearchTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct TimeZoneSearchTests {
    /// A winter day, so northern zones use their standard abbreviations.
    private let winter = Calendar.sundayFirst.date(from: DateComponents(year: 2026, month: 12, day: 1))!

    private func ids(_ query: String) -> [String] {
        TimeZoneSearch.matches(query, at: winter).map(\.identifier)
    }

    @Test func findsCityByPrefixIgnoringCaseAndUnderscores() {
        #expect(ids("tokyo").first == "Asia/Tokyo")
        #expect(ids("New Y").first == "America/New_York")
    }

    @Test func findsByRegionPath() {
        #expect(ids("europe/lond").contains("Europe/London"))
    }

    @Test func cityPrefixRanksAboveOtherMatches() {
        // "ma" starts cities like Madrid and also sits inside others like Panama; every
        // city-prefix match should come before any match that only contains it.
        let results = TimeZoneSearch.matches("ma", at: winter, limit: 100)
        let startsWith = results.map { TimeZoneSearch.city($0).lowercased().hasPrefix("ma") }
        #expect(startsWith.contains(false))
        #expect(startsWith == startsWith.sorted { $0 && !$1 })
    }

    @Test func blankQueryHasNoResults() {
        #expect(ids("   ").isEmpty)
    }

    @Test func limitsResults() {
        #expect(TimeZoneSearch.matches("a", at: winter, limit: 3).count == 3)
    }

    @Test func labelsWithCityAndAbbreviation() {
        let zone = TimeZone(identifier: "America/New_York")!
        #expect(TimeZoneSearch.label(zone, at: winter) == "New York (EST)")
    }
}
