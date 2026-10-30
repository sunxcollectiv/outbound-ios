//
//  TripItemParticipantsTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct TripItemParticipantsTests {
    private func decodeItem(_ extra: String) throws -> TripItem {
        let json = """
        {"id": "item", "trip_id": "t", "kind": "activity", "visibility": "closed", "title": "Dinner",
         "notes": null, "tags": [], "starts_at": "2026-11-11T19:00:00", "start_timezone": null,
         "ends_at": null, "end_timezone": null, "starts_at_utc": null, "ends_at_utc": null,
         "image_url": null, "place": null, "end_place": null, "segments": [],
         "created_at": "2026-10-01T00:00:00Z", "updated_at": "2026-10-01T00:00:00Z"\(extra)}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TripItem.self, from: Data(json.utf8))
    }

    private func encode(_ value: some Encodable) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try #require(JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any])
    }

    @Test func itemDecodesCreatorAndParticipants() throws {
        let item = try decodeItem("""
        , "created_by": {"id": "u1", "email": "a@example.com", "display_name": "A", "avatar_url": null,
                         "created_at": "2026-10-01T00:00:00Z"},
          "participants": [
            {"member": {"id": "m2", "email": "b@example.com", "user": null, "role": "member",
                        "created_at": "2026-10-01T00:00:00Z"},
             "status": "going", "updated_at": "2026-10-01T00:00:00Z"}
          ]
        """)
        #expect(item.createdBy?.id == "u1")
        #expect(item.participants.map(\.member.id) == ["m2"])
        #expect(item.participants.first?.status == .going)
        #expect(item.visibility == .closed)
        #expect(item.redacted == false)
    }

    @Test func participantWithoutAnAnswerDecodes() throws {
        let item = try decodeItem("""
        , "redacted": true, "participants": [
            {"member": {"id": "m2", "email": "b@example.com", "user": null, "role": "member",
                        "created_at": "2026-10-01T00:00:00Z"},
             "status": null, "updated_at": "2026-10-01T00:00:00Z"}
          ]
        """)
        #expect(item.redacted)
        #expect(item.participants.first?.status == nil)
    }

    @Test func itemWithoutParticipantsStillDecodes() throws {
        let item = try decodeItem("")
        #expect(item.createdBy == nil)
        #expect(item.participants.isEmpty)
    }

    @Test func itemDecodesDisplayTitle() throws {
        let item = try decodeItem(#", "display_title": "Dinner at Lilia""#)
        #expect(item.title == "Dinner")
        #expect(item.displayTitle == "Dinner at Lilia")
    }

    @Test func untitledItemDecodes() throws {
        let json = """
        {"id": "item", "trip_id": "t", "kind": "lodging", "title": null, "display_title": "Ace Hotel",
         "starts_at": "2026-11-11T15:00:00", "created_at": "2026-10-01T00:00:00Z",
         "updated_at": "2026-10-01T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let item = try decoder.decode(TripItem.self, from: Data(json.utf8))
        #expect(item.title == nil)
        #expect(item.displayTitle == "Ace Hotel")
    }

    @Test func itemDecodesTransitMode() throws {
        #expect(try decodeItem(#", "transit_mode": "car_rental""#).transitMode == .carRental)
        // An unknown mode leaves it unset rather than failing the item.
        #expect(try decodeItem(#", "transit_mode": "hovercraft""#).transitMode == nil)
        #expect(try decodeItem("").transitMode == nil)
    }

    @Test func requestsSendTransitModeOnlyWhenSet() throws {
        let create = TripItemsAPI.CreateRequest(
            kind: .transit, title: nil, notes: nil,
            startsAt: "2026-11-11T09:00:00", startTimezone: nil, endsAt: nil, endTimezone: nil,
            placeId: "p1", endPlaceId: "p2", transitMode: .train
        )
        #expect(try encode(create)["transit_mode"] as? String == "train")
        #expect(try encode(TripItemsAPI.UpdateRequest(create))["transit_mode"] as? String == "train")

        let unset = TripItemsAPI.CreateRequest(
            kind: .transit, title: nil, notes: nil,
            startsAt: "2026-11-11T09:00:00", startTimezone: nil, endsAt: nil, endTimezone: nil,
            placeId: "p1", endPlaceId: "p2"
        )
        #expect(try encode(unset).keys.contains("transit_mode") == false)
        #expect(try encode(TripItemsAPI.UpdateRequest(unset)).keys.contains("transit_mode") == false)
    }

    @Test func createSendsParticipantsByMemberId() throws {
        let body = TripItemsAPI.CreateRequest(
            kind: .activity, title: "Dinner", notes: nil,
            startsAt: "2026-11-11T19:00:00", startTimezone: nil, endsAt: nil, endTimezone: nil,
            placeId: nil, endPlaceId: nil,
            participants: [.init(memberId: "m2")]
        )
        let object = try encode(body)
        #expect(object["scope"] == nil)
        let participants = try #require(object["participants"] as? [[String: Any]])
        #expect(participants.first?["member_id"] as? String == "m2")
        // No status sent, so the server keeps any existing answer.
        #expect(participants.first?["status"] == nil)
    }

    @Test func requestsSendVisibility() throws {
        let create = TripItemsAPI.CreateRequest(
            kind: .activity, visibility: .closed, title: "Dinner", notes: nil,
            startsAt: "2026-11-11T19:00:00", startTimezone: nil, endsAt: nil, endTimezone: nil,
            placeId: nil, endPlaceId: nil
        )
        #expect(try encode(create)["visibility"] as? String == "closed")
        let update = TripItemsAPI.UpdateRequest(
            kind: .activity, visibility: .private, title: "Dinner", notes: nil, startsAt: "2026-11-11T19:00:00",
            startTimezone: nil, endsAt: nil, endTimezone: nil, placeId: nil, endPlaceId: nil
        )
        #expect(try encode(update)["visibility"] as? String == "private")
    }

    @Test func createOmitsMissingTitle() throws {
        let body = TripItemsAPI.CreateRequest(
            kind: .lodging, title: nil, notes: nil,
            startsAt: "2026-11-11T15:00:00", startTimezone: nil, endsAt: nil, endTimezone: nil,
            placeId: "p1", endPlaceId: nil
        )
        let object = try encode(body)
        #expect(object.keys.contains("title") == false)
        #expect(object["place_id"] as? String == "p1")
    }

    @Test func updateNullsTitleOrPlaceWhenAsked() throws {
        let create = TripItemsAPI.CreateRequest(
            kind: .lodging, title: "Grandma's", notes: nil,
            startsAt: "2026-11-11T15:00:00", startTimezone: nil, endsAt: nil, endTimezone: nil,
            placeId: nil, endPlaceId: nil
        )
        let lodging = try encode(TripItemsAPI.UpdateRequest(create, nullsTitleAndPlace: true))
        #expect(lodging["title"] as? String == "Grandma's")
        // Present as null, so the server clears the place the name replaces.
        #expect(lodging["place_id"] is NSNull)

        let other = try encode(TripItemsAPI.UpdateRequest(create))
        #expect(other.keys.contains("place_id") == false)
    }

    @Test func updateOmitsParticipantsWhenUnchanged() throws {
        let body = TripItemsAPI.UpdateRequest(
            kind: .activity, title: "Dinner", notes: nil, startsAt: "2026-11-11T19:00:00",
            startTimezone: nil, endsAt: nil, endTimezone: nil, placeId: nil, endPlaceId: nil
        )
        let object = try encode(body)
        #expect(object["scope"] == nil)
        #expect(object["participants"] == nil)
    }

    @Test func updateSendsParticipantsWhenSet() throws {
        let body = TripItemsAPI.UpdateRequest(
            kind: .activity, title: "Dinner", notes: nil, startsAt: "2026-11-11T19:00:00",
            startTimezone: nil, endsAt: nil, endTimezone: nil, placeId: nil, endPlaceId: nil,
            participants: [.init(memberId: "m1")]
        )
        let object = try encode(body)
        // The update endpoint rejects unknown keys, so scope must never be sent.
        #expect(object["scope"] == nil)
        #expect((object["participants"] as? [[String: Any]])?.count == 1)
    }
}
