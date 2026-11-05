//
//  LodgingDetailsTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct LodgingDetailsTests {
    private func decodeItem(kind: String = "lodging", _ extra: String) throws -> TripItem {
        let json = """
        {"id": "item", "trip_id": "t", "kind": "\(kind)", "title": "Stay",
         "notes": null, "tags": [], "starts_at": "2026-12-27T15:00:00", "start_timezone": "Asia/Bangkok",
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

    private static let importedHotel = """
    , "lodging": {"property_type": "hotel", "phone": "+66 2 012 1234",
                  "free_cancellation_until": "2026-12-29T23:59:00"},
      "rooms": [
        {"id": "r2", "position": 1, "label": null, "room_number": "412", "room_type": null,
         "guests": 2, "confirmation_number": null, "occupants": ["m1"]},
        {"id": "r1", "position": 0, "label": null, "room_number": null,
         "room_type": "1 King Bed, City view", "guests": 1, "confirmation_number": null, "occupants": []}
      ]
    """

    @Test func decodesLodgingDetails() throws {
        let item = try decodeItem(Self.importedHotel)
        let lodging = try #require(item.lodging)
        #expect(lodging.propertyType == .hotel)
        #expect(lodging.phone == "+66 2 012 1234")
        #expect(lodging.freeCancellationUntil.map(WallClock.naiveString) == "2026-12-29T23:59:00")
        #expect(item.typeLabel == "Hotel")
    }

    @Test func vacationRentalDecodes() throws {
        let item = try decodeItem(#", "lodging": {"property_type": "vacation_rental"}"#)
        #expect(item.lodging?.propertyType == .vacationRental)
        #expect(item.typeLabel == "Vacation rental")
    }

    @Test func missingOrNullOrUnknownDetailsStillDecode() throws {
        #expect(try decodeItem("").lodging == nil)
        #expect(try decodeItem(#", "lodging": null"#).lodging == nil)
        let unknown = try decodeItem(#", "lodging": {"property_type": "castle", "phone": "123"}"#)
        #expect(unknown.lodging?.propertyType == nil)
        #expect(unknown.lodging?.phone == "123")
        #expect(unknown.typeLabel == "Lodging")
        #expect(unknown.rooms.isEmpty)
    }

    @Test func createSendsDetailsOnlyWhenSet() throws {
        func body(_ lodging: LodgingDetails?) -> TripItemsAPI.CreateRequest {
            TripItemsAPI.CreateRequest(kind: .lodging, title: "Stay", notes: nil, startsAt: "2026-12-27T15:00:00",
                                       startTimezone: nil, endsAt: nil, endTimezone: nil, placeId: nil,
                                       endPlaceId: nil, lodging: lodging)
        }
        #expect(try encode(body(nil))["lodging"] == nil)
        let sent = try #require(try encode(body(LodgingDetails(propertyType: .hostel)))["lodging"] as? [String: Any])
        #expect(sent["property_type"] as? String == "hostel")
    }

    @Test func updateSendsDetailsOnlyWhenChanged() throws {
        let create = TripItemsAPI.CreateRequest(kind: .lodging, title: "Stay", notes: nil, startsAt: "2026-12-27T15:00:00",
                                                startTimezone: nil, endsAt: nil, endTimezone: nil, placeId: nil,
                                                endPlaceId: nil, lodging: LodgingDetails(propertyType: .hotel))
        let untouched = try encode(TripItemsAPI.UpdateRequest(create))
        #expect(untouched["lodging"] == nil)
        let changed = try encode(TripItemsAPI.UpdateRequest(create, sendsLodging: true))
        #expect((changed["lodging"] as? [String: Any])?["property_type"] as? String == "hotel")

        var cleared = TripItemsAPI.UpdateRequest(create, sendsLodging: true)
        cleared.lodging = nil
        #expect(try encode(cleared)["lodging"] is NSNull)
    }

    @Test func changingTheTypeKeepsTheImportedDetails() throws {
        let item = try decodeItem(Self.importedHotel)
        let draft = TripItemDraft(tripId: "t", kind: .lodging, item: item)
        #expect(draft.propertyType == .hotel)
        #expect(draft.lodgingChanged == false)

        draft.propertyType = .vacationRental
        #expect(draft.lodgingChanged)
        let details = try #require(draft.lodgingToSave)
        #expect(details.propertyType == .vacationRental)
        #expect(details.phone == "+66 2 012 1234")
        // Sent back as the same naive wall clock it came in as, and only with the keys
        // the server takes (it rejects any others).
        let sent = try encode(details)
        #expect(sent["free_cancellation_until"] as? String == "2026-12-29T23:59:00")
        #expect(Set(sent.keys) == ["property_type", "phone", "free_cancellation_until"])
    }

    @Test func clearingTheOnlyDetailClearsThem() throws {
        let item = try decodeItem(#", "lodging": {"property_type": "hostel"}"#)
        let draft = TripItemDraft(tripId: "t", kind: .lodging, item: item)
        draft.propertyType = nil
        #expect(draft.lodgingChanged)
        #expect(draft.lodgingToSave == nil)
    }

    @Test func otherKindsSendNoDetails() {
        let draft = TripItemDraft(tripId: "t", kind: .activity)
        draft.propertyType = .hotel
        #expect(draft.lodgingToSave == nil)
        #expect(draft.lodgingChanged == false)
    }

    // MARK: - Display

    @Test func roomsDecodeInOrder() throws {
        let item = try decodeItem(Self.importedHotel)
        #expect(item.rooms.map(\.id) == ["r1", "r2"])
        #expect(item.rooms[1].occupants == ["m1"])
        let draft = TripItemDraft(tripId: "t", kind: .lodging, item: item)
        #expect(draft.rooms.map(\.id) == ["r1", "r2"])
        #expect(TripItemDraft(tripId: "t", kind: .lodging).rooms.isEmpty)
    }

    @Test func roomsReadNaturally() {
        let typed = LodgingRoom(id: "a", roomType: "1 King Bed", guests: 1)
        #expect(typed.title(number: 1) == "Room 1")
        #expect(typed.summary == "1 King Bed · 1 guest")
        #expect(LodgingRoom(id: "b", roomNumber: "412", guests: 3).title(number: 2) == "Room 412")
        #expect(LodgingRoom(id: "c", label: "Kids' room", roomNumber: "412").title(number: 3) == "Kids' room")
        #expect(LodgingRoom(id: "d", label: " ", roomType: " ").title(number: 4) == "Room 4")
        #expect(LodgingRoom(id: "d").summary == nil)
    }

    @Test func cancellationDeadlineIsReadAtTheProperty() throws {
        let item = try decodeItem(Self.importedHotel)
        let lodging = try #require(item.lodging)
        let bangkok = try #require(TimeZone(identifier: "Asia/Bangkok"))
        let text = try #require(lodging.cancellationText(zone: bangkok))
        // The wall clock as written, whatever the device's zone, with the stay's zone.
        #expect(text.contains("Dec 29"))
        #expect(text.contains("11:59"))
        #expect(text.hasSuffix("GMT+7"))
        #expect(lodging.cancellationText(zone: nil)?.hasSuffix("PM") == true)

        // 23:59 in Bangkok is 16:59 UTC.
        let deadline = try #require(ISO8601DateFormatter().date(from: "2026-12-29T16:59:00Z"))
        #expect(!lodging.cancellationHasPassed(zone: bangkok, now: deadline.addingTimeInterval(-60)))
        #expect(lodging.cancellationHasPassed(zone: bangkok, now: deadline))
        #expect(!LodgingDetails().cancellationHasPassed(zone: bangkok))
    }

    // MARK: - Editing rooms

    @Test func editedRoomReplacesItsRow() throws {
        let draft = TripItemDraft(tripId: "t", kind: .lodging, item: try decodeItem(Self.importedHotel))
        var room = draft.rooms[0]
        room.roomNumber = " 1201 "
        draft.updateRoom(room)
        #expect(draft.rooms.count == 2)
        #expect(draft.rooms[0].roomNumber == "1201")
        #expect(draft.rooms[0].title(number: 1) == "Room 1201")
        #expect(draft.rooms[0].roomType == "1 King Bed, City view")
    }

    @Test func newRoomIsAddedUnlessBlank() {
        let draft = TripItemDraft(tripId: "t", kind: .lodging)
        draft.updateRoom(.new())
        var blank = LodgingRoom.new()
        blank.roomType = "   "
        draft.updateRoom(blank)
        #expect(draft.rooms.isEmpty)

        var room = LodgingRoom.new()
        room.roomType = "Twin"
        draft.updateRoom(room)
        #expect(draft.rooms.count == 1)
        #expect(draft.rooms[0].isNew)
        #expect(draft.rooms[0].title(number: 1) == "Room 1")

        // Edited again, it stays one room.
        room.roomNumber = "7"
        draft.updateRoom(room)
        #expect(draft.rooms.map(\.roomNumber) == ["7"])
    }

    @Test func clearedTextFieldsBecomeNil() throws {
        let draft = TripItemDraft(tripId: "t", kind: .lodging, item: try decodeItem(Self.importedHotel))
        var room = draft.rooms[1]
        room.roomNumber = ""
        draft.updateRoom(room)
        #expect(draft.rooms[1].roomNumber == nil)
        #expect(draft.rooms[1].title(number: 2) == "Room 2")
    }

    // MARK: - Room assignments

    private static let roster = ["m1", "m2", "m3", "m4"].map {
        TripMember(id: $0, email: "\($0)@example.com", user: nil, role: .member)
    }

    /// A stay with `importedHotel`'s two rooms (r1 empty, r2 holding m1), for
    /// m1 and m2, on a trip of m1–m4.
    private func assigningDraft() throws -> TripItemDraft {
        let draft = TripItemDraft(tripId: "t", kind: .lodging, members: Self.roster, item: try decodeItem(Self.importedHotel))
        draft.selectedMemberIds = ["m1", "m2"]
        return draft
    }

    @Test func roomPopupGroupsTheTrip() throws {
        let draft = try assigningDraft()
        let forR1 = draft.roomAssignments(for: "r1")
        #expect(forR1.participants.map(\.id) == ["m2"])
        #expect(forR1.others.map(\.id) == ["m3", "m4"])
        #expect(forR1.inOtherRooms.map(\.id) == ["m1"])
        #expect(forR1.inOtherRooms.first?.roomTitle == "Room 412")

        // A room's own people aren't "in another room" for it.
        let forR2 = draft.roomAssignments(for: "r2")
        #expect(forR2.participants.map(\.id) == ["m1", "m2"])
        #expect(forR2.inOtherRooms.isEmpty)
    }

    @Test func assigningSomeoneOffTheStayAddsThem() throws {
        let draft = try assigningDraft()
        var room = draft.rooms[0]
        room.occupants = ["m2", "m3"]
        draft.updateRoom(room)
        #expect(draft.rooms[0].occupants == ["m2", "m3"])
        #expect(draft.selectedMemberIds == ["m1", "m2", "m3"])
        #expect(draft.roomAssignments(for: "r2").inOtherRooms.map(\.id) == ["m2", "m3"])
    }

    @Test func blankNewRoomAddsNobody() throws {
        let draft = try assigningDraft()
        draft.updateRoom(.new())
        #expect(draft.rooms.count == 2)
        #expect(draft.selectedMemberIds == ["m1", "m2"])
    }

    @Test func roomRowNamesWhosIn() throws {
        let you = TripMember(id: "m1", email: "me@example.com", user: User(id: "u1", email: "me@example.com", displayName: "Sun", avatarUrl: nil, createdAt: .now), role: .organizer)
        let roster = [you] + ["m2", "m3", "m4"].map { TripMember(id: $0, email: "\($0)@example.com", user: nil, role: .member) }
        let draft = TripItemDraft(tripId: "t", kind: .lodging, members: roster)
        var room = LodgingRoom.new()
        #expect(draft.occupantNames(of: room, currentUserId: "u1") == nil)
        room.occupants = ["m2", "m1"]
        // In trip order, with the signed-in user as "You".
        #expect(draft.occupantNames(of: room, currentUserId: "u1") == "You and m2")
        #expect(draft.occupantNames(of: room, currentUserId: nil) == "Sun and m2")
        room.occupants = ["m1", "m2", "m3", "m4"]
        #expect(draft.occupantNames(of: room, currentUserId: "u1") == "You, m2 and 2 others")
    }
}
