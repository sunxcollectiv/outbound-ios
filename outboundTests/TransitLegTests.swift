//
//  TransitLegTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct TransitLegTests {
    private func encode(_ value: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try #require(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
    }

    private func decodeTransit(segments: String) throws -> TripItem {
        let json = """
        {"id": "item", "trip_id": "t", "kind": "transit", "title": null, "display_title": "JFK to LAX",
         "starts_at": "2026-11-11T09:00:00", "start_timezone": "America/New_York",
         "ends_at": "2026-11-11T18:00:00", "end_timezone": "America/Los_Angeles",
         "transit_mode": "mixed", "segments": \(segments),
         "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TripItem.self, from: Data(json.utf8))
    }

    private let twoLegs = """
    [{"id": "s2", "position": 1, "starts_at": "2026-11-11T14:00:00", "start_timezone": "America/Chicago",
      "ends_at": "2026-11-11T18:00:00", "end_timezone": "America/Los_Angeles",
      "transit_mode": "train", "carrier": null, "flight_number": null, "confirmation_number": null},
     {"id": "s1", "position": 0, "starts_at": "2026-11-11T09:00:00", "start_timezone": "America/New_York",
      "ends_at": "2026-11-11T12:00:00", "end_timezone": "America/Chicago",
      "transit_mode": "flight", "carrier": "Delta", "flight_number": "DL 12", "confirmation_number": "ABC123"}]
    """

    @Test func updateWithSegmentsLeavesOutTheItemsSpan() throws {
        let create = TripItemsAPI.CreateRequest(
            kind: .transit, title: nil, notes: nil,
            startsAt: nil, startTimezone: nil, endsAt: nil, endTimezone: nil,
            placeId: nil, endPlaceId: nil,
            segments: [.init(
                startsAt: "2026-11-11T09:00:00", startTimezone: "America/New_York",
                endsAt: nil, endTimezone: nil, placeId: "p1", endPlaceId: "p2", transitMode: .flight,
                carrier: "Delta"
            )]
        )
        for object in [try encode(create), try encode(TripItemsAPI.UpdateRequest(create))] {
            // The server rejects these alongside segments; an update mustn't even null them.
            for key in ["starts_at", "start_timezone", "ends_at", "end_timezone", "place_id", "end_place_id", "transit_mode"] {
                #expect(object.keys.contains(key) == false, "\(key)")
            }
            let segment = try #require((object["segments"] as? [[String: Any]])?.first)
            #expect(segment["starts_at"] as? String == "2026-11-11T09:00:00")
            #expect(segment["place_id"] as? String == "p1")
            #expect(segment["transit_mode"] as? String == "flight")
            #expect(segment["carrier"] as? String == "Delta")
            #expect(segment.keys.contains("ends_at") == false)
        }
    }

    @Test func updateWithoutSegmentsStillSendsTheSpan() throws {
        let create = TripItemsAPI.CreateRequest(
            kind: .activity, title: "Dinner", notes: nil,
            startsAt: "2026-11-11T19:00:00", startTimezone: nil, endsAt: nil, endTimezone: nil,
            placeId: nil, endPlaceId: nil
        )
        let object = try encode(TripItemsAPI.UpdateRequest(create))
        #expect(object["starts_at"] as? String == "2026-11-11T19:00:00")
        #expect(object["ends_at"] is NSNull)
        #expect(object.keys.contains("segments") == false)
    }

    @Test func draftLoadsSavedLegsInOrder() throws {
        let item = try decodeTransit(segments: twoLegs)
        let draft = TripItemDraft(tripId: "t", kind: .transit, item: item)
        #expect(draft.legs.count == 2)
        #expect(draft.legs.map(\.transitMode) == [.flight, .train])
        #expect(draft.legs.first?.startZone?.identifier == "America/New_York")
        // Booking details ride along, so saving doesn't drop them.
        let first = try #require(draft.legs.first?.request)
        #expect(first.carrier == "Delta")
        #expect(first.flightNumber == "DL 12")
        #expect(first.confirmationNumber == "ABC123")
        #expect(first.startsAt == "2026-11-11T09:00:00")
    }

    @Test func newTransitStartsWithOneLeg() {
        let draft = TripItemDraft(tripId: "t", kind: .transit)
        #expect(draft.legs.count == 1)
        #expect(draft.legs.first?.startsAt != nil)
        #expect(TripItemDraft(tripId: "t", kind: .activity).legs.isEmpty)
    }

    @Test func addedLegPicksUpWhereTheLastArrives() throws {
        let draft = TripItemDraft(tripId: "t", kind: .transit, item: try decodeTransit(segments: twoLegs))
        draft.addLeg()
        let last = draft.legs[1], added = draft.legs[2]
        #expect(added.startsAt == last.endsAt)
        #expect(added.startZone == last.endZone)
        #expect(added.transitMode == .train)
        #expect(added.endsAt == nil)
        // Nothing from the booking carries over to a new leg.
        #expect(added.carrier == nil)
    }

    @Test func lastLegCantBeRemoved() throws {
        let draft = TripItemDraft(tripId: "t", kind: .transit, item: try decodeTransit(segments: twoLegs))
        draft.removeLeg(draft.legs[0])
        #expect(draft.legs.map(\.transitMode) == [.train])
        draft.removeLeg(draft.legs[0])
        #expect(draft.legs.count == 1)
    }

    @Test func legArrivingBeforeItDepartsIsCaught() {
        let leg = TransitLeg(startsAt: Date(timeIntervalSince1970: 3600), endsAt: Date(timeIntervalSince1970: 0))
        #expect(leg.endsBeforeStart)
        #expect(TransitLeg(startsAt: nil).request == nil)
    }
}
