//
//  ItineraryPlacesTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// How the itinerary keeps one copy of each place, and how a stale-place refresh
/// patches every card that shows it.
struct ItineraryPlacesTests {

    @Test func everyEntryForAPlaceReadsOneCopy() throws {
        // A flight's departure and arrival, and a dinner at the arrival airport.
        let itinerary = try decodeItinerary(stale: ["MEL"])
        var places = ItineraryPlaces(days: itinerary.days)
        let entries = itinerary.days.flatMap(\.entries)
        let melEntries = entries.filter { $0.place?.id == "MEL" }
        #expect(melEntries.count == 2)

        places.update(with: ["MEL": place("MEL", name: "Melbourne Airport", photo: "https://example.com/mel.jpg")])

        for entry in melEntries {
            #expect(places.current(entry.place)?.name == "Melbourne Airport")
            #expect(places.current(entry.place)?.coverPhoto?.url.absoluteString == "https://example.com/mel.jpg")
        }
        // Places outside the refresh keep the itinerary's copy.
        let departure = try #require(entries.first { $0.phase == .departure })
        #expect(places.current(departure.place)?.name == "JFK")
    }

    @Test func aRefreshReplacesTheWholePlace() throws {
        var places = ItineraryPlaces(days: try decodeItinerary().days)
        #expect(places.byId["MEL"]?.coverPhoto?.url.absoluteString == "https://example.com/old.jpg")

        places.update(with: ["MEL": place("MEL", name: "Melbourne Airport", address: "Tullamarine VIC", photo: nil)])

        let mel = try #require(places.byId["MEL"])
        #expect(mel.name == "Melbourne Airport")
        #expect(mel.address == "Tullamarine VIC")
        #expect(mel.coverPhoto == nil)
    }

    @Test func resolvingAnItemSwapsInTheSharedCopies() throws {
        let itinerary = try decodeItinerary()
        var places = ItineraryPlaces(days: itinerary.days)
        places.update(with: ["MEL": place("MEL", name: "Melbourne Airport")])
        let flight = try #require(itinerary.days.flatMap(\.entries).first { $0.item.kind == .transit }?.item)

        let resolved = places.resolving(flight)

        #expect(resolved.endPlace?.name == "Melbourne Airport")
        #expect(resolved.segments.first?.endPlace?.name == "Melbourne Airport")
        #expect(resolved.place?.name == "JFK")
    }

    @Test func decodesStalePlaceIds() throws {
        #expect(try decodeItinerary(stale: ["MEL", "JFK"]).stalePlaceIds == ["MEL", "JFK"])
        #expect(try decodeItinerary(stale: nil).stalePlaceIds == [])
    }

    @Test func decodesARefreshResponseKeyedByPlaceId() throws {
        // Real ids are UUIDs; the snake-case key strategy must leave them alone.
        let id = "3f2c7a9e-1b4d-4c8e-9a6f-2d5b8e1c0a7f"
        let json = #"{"places": {"\#(id)": \#(placeJSON(id, name: "Grill'd", photo: "https://example.com/g.jpg"))}}"#
        let response = try decoder.decode(PlacesAPI.RefreshResponse.self, from: Data(json.utf8))

        #expect(response.places[id]?.name == "Grill'd")
        #expect(response.places[id]?.coverPhoto?.url.absoluteString == "https://example.com/g.jpg")
    }

    // MARK: - Fixtures

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func place(_ id: String, name: String, address: String? = nil, photo: String? = nil) -> Place {
        try! decoder.decode(Place.self, from: Data(placeJSON(id, name: name, address: address, photo: photo).utf8))
    }

    private func placeJSON(_ id: String, name: String, address: String? = nil, photo: String? = nil) -> String {
        let cover = photo.map { #"{"url": "\#($0)", "attributions": [], "is_stale": false}"# } ?? "null"
        return """
        {"id": "\(id)", "name": "\(name)", "address": \(address.map { "\"\($0)\"" } ?? "null"),
         "latitude": null, "longitude": null, "timezone": null, "google_place_id": null, "cover_photo": \(cover)}
        """
    }

    /// One day: a JFK → MEL flight (departure + arrival entries) and a dinner at MEL.
    /// The itinerary's own copy of MEL carries an old cover photo.
    private func decodeItinerary(stale: [String]? = []) throws -> Itinerary {
        let jfk = placeJSON("JFK", name: "JFK")
        let mel = placeJSON("MEL", name: "MEL", photo: "https://example.com/old.jpg")
        func item(_ id: String, _ kind: String, place: String, endPlace: String, segments: String) -> String {
            """
            {"id": "\(id)", "trip_id": "t", "kind": "\(kind)", "scope": "group", "title": "\(id)",
             "notes": null, "tags": [], "starts_at": "2026-11-11T08:30:00", "start_timezone": null,
             "ends_at": "2026-11-11T21:00:00", "end_timezone": null, "starts_at_utc": null, "ends_at_utc": null,
             "image_url": null, "place": \(place), "end_place": \(endPlace), "segments": [\(segments)],
             "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"}
            """
        }
        let leg = """
        {"id": "JFK-MEL", "position": 0, "starts_at": "2026-11-11T08:30:00", "start_timezone": null,
         "ends_at": "2026-11-11T21:00:00", "end_timezone": null, "starts_at_utc": null, "ends_at_utc": null,
         "place": \(jfk), "end_place": \(mel), "carrier": null, "flight_number": null}
        """
        let flight = item("flight", "transit", place: jfk, endPlace: mel, segments: leg)
        let dinner = item("dinner", "activity", place: mel, endPlace: "null", segments: "")
        let staleJSON = stale.map { #", "stale_place_ids": [\#($0.map { "\"\($0)\"" }.joined(separator: ","))]"# } ?? ""
        let json = """
        {"trip": {"id": "t", "title": "Trip", "description": null, "start_date": "2026-11-11", "end_date": "2026-11-12",
                  "cover_image_url": null, "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"},
         "days": [{"date": "2026-11-11", "day_number": 1, "lodging": [], "items": [
            {"item": \(flight), "phase": "departure", "layover_place": null, "layover_minutes": null},
            {"item": \(flight), "phase": "arrival", "layover_place": null, "layover_minutes": null},
            {"item": \(dinner), "phase": null, "layover_place": null, "layover_minutes": null}
         ]}]\(staleJSON)}
        """
        return try decoder.decode(Itinerary.self, from: Data(json.utf8))
    }
}
