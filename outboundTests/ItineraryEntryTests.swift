//
//  ItineraryEntryTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// How an itinerary entry picks the time and place for the spot its phase stands for.
struct ItineraryEntryTests {

    @Test func arrivalShowsTheItemsEndAndDestination() throws {
        let entry = try decodeEntry(phase: "arrival", legs: [leg("JFK", "MEL", "2026-11-11T08:30:00", "2026-11-12T09:00:00")])

        #expect(entry.displayLocal == entry.item.endsAtLocal)
        #expect(entry.place?.id == "MEL")
    }

    @Test func checkOutFallsBackToTheLodgingsOwnPlace() throws {
        let entry = try decodeEntry(kind: "lodging", phase: "check_out", endPlace: nil, legs: [])

        #expect(entry.displayLocal == entry.item.endsAtLocal)
        #expect(entry.place?.id == "JFK")
    }

    @Test func layoverReadsItsTimesOffTheLegsAroundTheStop() throws {
        let entry = try decodeEntry(phase: "layover", layoverPlace: "LAX", layoverMinutes: 150, legs: [
            leg("JFK", "LAX", "2026-11-11T08:00:00", "2026-11-11T11:00:00", flight: "QF 12"),
            leg("LAX", "MEL", "2026-11-11T13:30:00", "2026-11-12T21:00:00", flight: "QF 94"),
        ])

        #expect(entry.place?.id == "LAX")
        #expect(entry.layoverMinutes == 150)
        #expect(entry.layoverInbound?.id == "JFK-LAX")
        #expect(entry.displayLocal == entry.layoverInbound?.endsAtLocal)
        #expect(entry.layoverOutbound?.id == "LAX-MEL")
        #expect(entry.segment?.label == "Qantas QF 94")
    }

    @Test func entriesOfOneItemHaveDistinctIds() throws {
        let legs = [
            leg("JFK", "LAX", "2026-11-11T08:00:00", "2026-11-11T11:00:00"),
            leg("LAX", "SYD", "2026-11-11T13:30:00", "2026-11-12T21:00:00"),
            leg("SYD", "MEL", "2026-11-12T23:00:00", "2026-11-13T00:30:00"),
        ]
        let ids = try [
            decodeEntry(phase: "departure", legs: legs),
            decodeEntry(phase: "layover", layoverPlace: "LAX", layoverMinutes: 150, legs: legs),
            decodeEntry(phase: "layover", layoverPlace: "SYD", layoverMinutes: 120, legs: legs),
            decodeEntry(phase: "arrival", legs: legs),
        ].map(\.id)

        #expect(Set(ids).count == ids.count)
    }

    // MARK: - Fixtures

    private func leg(_ from: String, _ to: String, _ start: String, _ end: String, flight: String? = nil) -> String {
        """
        {"id": "\(from)-\(to)", "position": 0, "starts_at": "\(start)", "start_timezone": null,
         "ends_at": "\(end)", "end_timezone": null, "starts_at_utc": null, "ends_at_utc": null,
         "place": \(place(from)), "end_place": \(place(to)),
         "carrier": \(flight == nil ? "null" : "\"Qantas\""), "flight_number": \(flight.map { "\"\($0)\"" } ?? "null")}
        """
    }

    private func place(_ id: String?) -> String {
        guard let id else { return "null" }
        return """
        {"id": "\(id)", "name": "\(id)", "address": null, "latitude": null, "longitude": null,
         "timezone": null, "google_place_id": null}
        """
    }

    /// One entry of an item running JFK → `endPlace`, as the server sends it. Leg
    /// positions follow array order.
    private func decodeEntry(
        kind: String = "transit", phase: String, endPlace: String? = "MEL",
        layoverPlace: String? = nil, layoverMinutes: Int? = nil, legs: [String]
    ) throws -> ItineraryEntry {
        let segments = legs.enumerated()
            .map { $1.replacingOccurrences(of: "\"position\": 0", with: "\"position\": \($0)") }
            .joined(separator: ",")
        let json = """
        {"item": {"id": "item", "trip_id": "t", "kind": "\(kind)", "scope": "group", "title": "Trip",
                  "notes": null, "tags": [], "starts_at": "2026-11-11T08:30:00", "start_timezone": null,
                  "ends_at": "2026-11-12T21:00:00", "end_timezone": null, "starts_at_utc": null, "ends_at_utc": null,
                  "image_url": null, "place": \(place("JFK")), "end_place": \(place(endPlace)), "segments": [\(segments)],
                  "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"},
         "phase": "\(phase)", "layover_place": \(place(layoverPlace)),
         "layover_minutes": \(layoverMinutes.map(String.init) ?? "null")}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ItineraryEntry.self, from: Data(json.utf8))
    }
}
