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
