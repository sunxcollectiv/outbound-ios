//
//  TripSectionsTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct TripSectionsTests {
    private func trip(_ id: String, _ start: String, _ end: String) -> Trip {
        Trip(id: id, title: id, startDate: start, endDate: end, createdAt: .now, updatedAt: .now)
    }

    @Test func upcomingIsSoonestFirstAndPastIsMostRecentFirst() {
        let trips = [
            trip("later", "2026-12-01", "2026-12-05"),
            trip("old", "2026-01-01", "2026-01-05"),
            trip("soon", "2026-11-01", "2026-11-03"),
            trip("recent", "2026-09-01", "2026-09-05"),
        ]
        let (upcoming, past) = Trip.upcomingAndPast(trips, today: "2026-10-23")
        #expect(upcoming.map(\.id) == ["soon", "later"])
        #expect(past.map(\.id) == ["recent", "old"])
    }

    @Test func tripEndingTodayIsStillUpcoming() {
        let (upcoming, past) = Trip.upcomingAndPast([trip("now", "2026-10-20", "2026-10-23")], today: "2026-10-23")
        #expect(upcoming.map(\.id) == ["now"])
        #expect(past.isEmpty)
    }
}
