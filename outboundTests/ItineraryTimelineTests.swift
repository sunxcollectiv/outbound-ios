//
//  ItineraryTimelineTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// Lays out transit from `item.segments` as decoded from the itinerary payload.
struct ItineraryTimelineTests {

    @Test func directFlightIsDepartureThenArrivalOnTheirOwnDays() throws {
        let days = try decodeDays(dates: ["2026-11-11", "2026-11-12"], legs: [
            leg("JFK", "MEL", "2026-11-11T08:30:00", "2026-11-12T09:00:00"),
        ])
        let cards = ItineraryTimeline.cards(for: days)

        #expect(stops(cards["2026-11-11"]).map(\.kind) == [.departure])
        #expect(stops(cards["2026-11-11"]).first?.place?.id == "JFK")
        #expect(stops(cards["2026-11-12"]).map(\.kind) == [.arrival])
        #expect(stops(cards["2026-11-12"]).first?.place?.id == "MEL")
    }

    @Test func sameDayConnectionIsOneLayover() throws {
        let days = try decodeDays(dates: ["2026-11-11", "2026-11-12"], legs: [
            leg("JFK", "LAX", "2026-11-11T08:00:00", "2026-11-11T11:00:00", flight: "QF 12"),
            leg("LAX", "MEL", "2026-11-11T13:30:00", "2026-11-12T21:00:00", flight: "QF 94"),
        ])
        let day1 = stops(ItineraryTimeline.cards(for: days)["2026-11-11"])

        #expect(day1.map(\.kind) == [.departure, .layover])
        let layover = try #require(day1.last)
        #expect(layover.place?.id == "LAX")
        #expect(layover.layoverDuration == .seconds(2.5 * 3600))
        #expect(layover.outbound?.label == "Qantas QF 94")
        #expect(stops(ItineraryTimeline.cards(for: days)["2026-11-12"]).map(\.kind) == [.arrival])
    }

    @Test func overnightConnectionSplitsIntoArrivalAndDeparture() throws {
        let days = try decodeDays(dates: ["2026-11-11", "2026-11-12"], legs: [
            leg("JFK", "LAX", "2026-11-11T18:00:00", "2026-11-11T21:00:00"),
            leg("LAX", "MEL", "2026-11-12T07:00:00", "2026-11-12T23:00:00"),
        ])
        let cards = ItineraryTimeline.cards(for: days)

        #expect(stops(cards["2026-11-11"]).map(\.kind) == [.departure, .arrival])
        #expect(stops(cards["2026-11-12"]).map(\.kind) == [.departure, .arrival])
    }

    @Test func transitWithoutSegmentsFallsBackToItsEntries() throws {
        let days = try decodeDays(dates: ["2026-11-11", "2026-11-12"], legs: [])
        let cards = ItineraryTimeline.cards(for: days)

        guard case .entry(let departure) = cards["2026-11-11"]?.first,
              case .entry(let arrival) = cards["2026-11-12"]?.first else {
            Issue.record("expected entry cards"); return
        }
        #expect(departure.phase == .departure)
        #expect(arrival.phase == .arrival)
        // The arrival entry shows the item's end, not its start.
        #expect(arrival.displayLocal == arrival.item.endsAtLocal)
    }

    // MARK: - Fixtures

    private func stops(_ cards: [ItineraryCard]?) -> [TransitStop] {
        (cards ?? []).compactMap { if case .transit(let stop) = $0 { stop } else { nil } }
    }

    private func leg(_ from: String, _ to: String, _ start: String, _ end: String, flight: String? = nil) -> String {
        """
        {"id": "\(from)-\(to)", "position": 0, "starts_at": "\(start)", "start_timezone": null,
         "ends_at": "\(end)", "end_timezone": null, "starts_at_utc": null, "ends_at_utc": null,
         "place": \(place(from)), "end_place": \(place(to)),
         "carrier": \(flight == nil ? "null" : "\"Qantas\""), "flight_number": \(flight.map { "\"\($0)\"" } ?? "null")}
        """
    }

    private func place(_ id: String) -> String {
        """
        {"id": "\(id)", "name": "\(id)", "address": null, "latitude": null, "longitude": null,
         "timezone": null, "google_place_id": null}
        """
    }

    /// A transit item split into departure/arrival entries on the first and last day,
    /// as the server sends it. Leg positions follow array order.
    private func decodeDays(dates: [String], legs: [String]) throws -> [ItineraryDay] {
        let segments = legs.enumerated()
            .map { $1.replacingOccurrences(of: "\"position\": 0", with: "\"position\": \($0)") }
            .joined(separator: ",")
        let item = """
        {"id": "trip-to-aus", "trip_id": "t", "kind": "transit", "scope": "group", "title": "Trip To Australia",
         "notes": null, "tags": [], "starts_at": "2026-11-11T08:30:00", "start_timezone": null,
         "ends_at": "2026-11-12T21:00:00", "end_timezone": null, "starts_at_utc": null, "ends_at_utc": null,
         "image_url": null, "place": \(place("JFK")), "end_place": \(place("MEL")), "segments": [\(segments)],
         "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"}
        """
        let json = dates.enumerated().map { index, date in
            let phase = index == 0 ? "departure" : (index == dates.count - 1 ? "arrival" : nil)
            let items = phase.map { "[{\"item\": \(item), \"phase\": \"\($0)\"}]" } ?? "[]"
            return "{\"date\": \"\(date)\", \"day_number\": \(index + 1), \"lodging\": [], \"items\": \(items)}"
        }.joined(separator: ",")

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ItineraryDay].self, from: Data("[\(json)]".utf8))
    }
}
