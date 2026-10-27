//
//  TripMembersTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct TripMembersTests {
    @Test func tripDecodesMembersWithAndWithoutAccounts() throws {
        let json = """
        {
          "id": "t1", "owner_id": "u1", "title": "Tokyo", "description": null,
          "start_date": "2026-11-01", "end_date": "2026-11-05", "cover_image_url": null,
          "areas": [], "areas_missing_photos": [],
          "members": [
            {"id": "m1", "email": "owner@example.com", "role": "organizer", "created_at": "2026-10-26T00:00:00Z",
             "user": {"id": "u1", "email": "owner@example.com", "display_name": "Owner", "avatar_url": null,
                      "created_at": "2026-10-01T00:00:00Z"}},
            {"id": "m2", "email": "sam@example.com", "role": "member", "created_at": "2026-10-26T00:00:00Z",
             "user": null}
          ],
          "created_at": "2026-10-26T00:00:00Z", "updated_at": "2026-10-26T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let trip = try decoder.decode(Trip.self, from: Data(json.utf8))

        #expect(trip.ownerId == "u1")
        #expect(trip.members?.map(\.email) == ["owner@example.com", "sam@example.com"])
        #expect(trip.members?.first?.role == .organizer)
        #expect(trip.members?.last?.user == nil)
    }

    @Test func tripStillDecodesWithoutMembers() throws {
        let json = """
        {"id": "t1", "title": "Tokyo", "start_date": "2026-11-01", "end_date": "2026-11-05",
         "created_at": "2026-10-26T00:00:00Z", "updated_at": "2026-10-26T00:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let trip = try decoder.decode(Trip.self, from: Data(json.utf8))
        #expect(trip.members == nil)
    }

    @Test func createRequestEncodesMembersAndOmitsNilRole() throws {
        let body = TripsAPI.CreateRequest(
            title: "Tokyo", description: nil, startDate: "2026-11-01", endDate: "2026-11-05",
            members: [
                .init(email: "jesse@example.com", role: .organizer),
                .init(email: "sam@example.com"),
            ]
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: Any]
        let members = try #require(object?["members"] as? [[String: Any]])

        #expect(members.count == 2)
        #expect(members[0]["email"] as? String == "jesse@example.com")
        #expect(members[0]["role"] as? String == "organizer")
        #expect(members[1]["role"] == nil)
    }

    @Test func createRequestOmitsMembersWhenNil() throws {
        let body = TripsAPI.CreateRequest(title: "Tokyo", description: nil, startDate: "2026-11-01", endDate: "2026-11-05")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try JSONSerialization.jsonObject(with: encoder.encode(body)) as? [String: Any]
        #expect(object?["members"] == nil)
    }
}
