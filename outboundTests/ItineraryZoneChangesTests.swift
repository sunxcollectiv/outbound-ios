//
//  ItineraryZoneChangesTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// Where the itinerary marks a change of clock between entries.
struct ItineraryZoneChangesTests {

    @Test func marksTheFirstEntryInANewZoneOnly() throws {
        let day = ItineraryDay(date: "2026-11-11", dayNumber: 1, lodging: [], entries: [
            try entry("breakfast", start: "2026-11-11T08:00:00", startZone: "America/New_York"),
            try entry("flight", kind: "transit", phase: "arrival", start: "2026-11-11T10:00:00", startZone: "America/New_York",
                      end: "2026-11-11T13:00:00", endZone: "America/Los_Angeles"),
            try entry("dinner", start: "2026-11-11T19:00:00", startZone: "America/Los_Angeles"),
        ])

        let changes = ItineraryZoneChanges.changes(in: [day])

        #expect(changes.keys.sorted() == ["flight|arrival|"])
        #expect(changes["flight|arrival|"]?.identifier == "America/Los_Angeles")
    }

    @Test func aChangeOvernightMarksTheTopOfTheNextDay() throws {
        let days = [
            ItineraryDay(date: "2026-11-11", dayNumber: 1, lodging: [], entries: [
                try entry("dinner", start: "2026-11-11T19:00:00", startZone: "America/New_York"),
            ]),
            ItineraryDay(date: "2026-11-12", dayNumber: 2, lodging: [], entries: [
                try entry("tour", start: "2026-11-12T09:00:00", startZone: "Europe/London"),
            ]),
        ]

        #expect(ItineraryZoneChanges.changes(in: days).keys.sorted() == ["tour||"])
    }

    @Test func zonelessEntriesAndMatchingOffsetsAreNotChanges() throws {
        let day = ItineraryDay(date: "2026-11-11", dayNumber: 1, lodging: [], entries: [
            try entry("coffee", start: "2026-11-11T08:00:00", startZone: "America/New_York"),
            try entry("walk", start: "2026-11-11T10:00:00", startZone: nil),
            try entry("lunch", start: "2026-11-11T12:00:00", startZone: "America/Toronto"),
        ])

        #expect(ItineraryZoneChanges.changes(in: [day]).isEmpty)
    }

    @Test func aLayoverIsReadInItsStopsZone() throws {
        let layover = try entry("flight", kind: "transit", phase: "layover", start: "2026-11-11T08:00:00",
                                startZone: "America/New_York", layoverZone: "America/Chicago")
        let day = ItineraryDay(date: "2026-11-11", dayNumber: 1, lodging: [], entries: [
            try entry("coffee", start: "2026-11-11T06:00:00", startZone: "America/New_York"),
            layover,
        ])

        #expect(layover.timeZone?.identifier == "America/Chicago")
        #expect(ItineraryZoneChanges.changes(in: [day])[layover.id]?.identifier == "America/Chicago")
    }

    @Test func aFlightsEntriesStayTogetherInTravelOrder() throws {
        // Melbourne → LA → New York: the LA layover's 10:10 AM ties the 10:10 AM
        // departure on the wall clock, and the 3 PM check-out falls between legs.
        let legs = """
        [{"id": "MEL-LAX", "position": 0, "starts_at": "2026-11-19T10:10:00", "start_timezone": "Australia/Melbourne",
          "ends_at": "2026-11-19T08:40:00", "end_timezone": "America/Los_Angeles",
          "place": {"id": "MEL"}, "end_place": {"id": "LAX"}},
         {"id": "LAX-JFK", "position": 1, "starts_at": "2026-11-19T10:10:00", "start_timezone": "America/Los_Angeles",
          "ends_at": "2026-11-19T15:41:00", "end_timezone": "America/New_York",
          "place": {"id": "LAX"}, "end_place": {"id": "JFK"}}]
        """
        let flight = { (phase: String, extra: String) in
            try self.entry("flight", kind: "transit", phase: phase, start: "2026-11-19T10:10:00", startZone: "Australia/Melbourne",
                           end: "2026-11-19T15:41:00", endZone: "America/New_York", segments: legs, extra: extra)
        }
        let arrival = try flight("arrival", "")
        let layover = try flight("layover", #", "layover_place": {"id": "LAX"}, "layover_timezone": "America/Los_Angeles""#)
        let departure = try flight("departure", "")
        let checkOut = try entry("hotel", kind: "lodging", phase: "check_out", start: "2026-11-13T15:00:00",
                                 startZone: "Australia/Melbourne", end: "2026-11-19T15:00:00", endZone: "Australia/Melbourne")

        let ordered = ItineraryDay.ordered([arrival, checkOut, layover, departure])

        #expect(ordered.map(\.id) == [departure.id, layover.id, arrival.id, checkOut.id])
        let day = ItineraryDay(date: "2026-11-19", dayNumber: 9, lodging: [], entries: ordered)
        let changes = ItineraryZoneChanges.changes(in: [day])
        #expect(changes[layover.id]?.identifier == "America/Los_Angeles")
        #expect(changes[arrival.id]?.identifier == "America/New_York")
        #expect(changes[checkOut.id]?.identifier == "Australia/Melbourne")
        #expect(changes[departure.id] == nil)
    }

    // MARK: - Fixtures

    private func entry(
        _ id: String, kind: String = "activity", phase: String? = nil,
        start: String, startZone: String?, end: String? = nil, endZone: String? = nil,
        layoverZone: String? = nil, segments: String = "[]", extra: String = ""
    ) throws -> ItineraryEntry {
        func json(_ value: String?) -> String { value.map { "\"\($0)\"" } ?? "null" }
        let payload = """
        {"item": {"id": "\(id)", "trip_id": "t", "kind": "\(kind)", "scope": "group", "title": "\(id)",
                  "tags": [], "starts_at": "\(start)", "start_timezone": \(json(startZone)),
                  "ends_at": \(json(end)), "end_timezone": \(json(endZone)), "segments": \(segments),
                  "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"},
         "phase": \(json(phase))\(extra.isEmpty ? ", \"layover_timezone\": \(json(layoverZone))" : extra)}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ItineraryEntry.self, from: Data(payload.utf8))
    }
}
