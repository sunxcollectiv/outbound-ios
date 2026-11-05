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

    @Test func removingAParticipantTakesThemOutOfTheirRoom() throws {
        let draft = try assigningDraft()
        var room = draft.rooms[0]
        room.occupants = ["m2"]
        draft.updateRoom(room)
        #expect(draft.rooms.map(\.occupants) == [["m2"], ["m1"]])

        draft.selectedMemberIds = ["m2"]
        #expect(draft.rooms.map(\.occupants) == [["m2"], []])
        // Adding someone back doesn't put them back in a room.
        draft.selectedMemberIds = ["m1", "m2"]
        #expect(draft.rooms.map(\.occupants) == [["m2"], []])
    }

    // MARK: - Saving rooms

    private func lodgingCreate(rooms: [TripItemsAPI.RoomRequest]?) -> TripItemsAPI.CreateRequest {
        TripItemsAPI.CreateRequest(kind: .lodging, title: "Stay", notes: nil, startsAt: "2026-12-27T15:00:00",
                                   startTimezone: nil, endsAt: nil, endTimezone: nil, placeId: nil,
                                   endPlaceId: nil, rooms: rooms)
    }

    @Test func roomsAreSentInTheServersShape() throws {
        var new = LodgingRoom.new()
        new.roomType = "Twin"
        new.occupants = ["m2"]
        let rooms = [TripItemsAPI.RoomRequest(LodgingRoom(id: "r1", roomNumber: "412")), TripItemsAPI.RoomRequest(new)]
        let sent = try #require(try encode(lodgingCreate(rooms: rooms))["rooms"] as? [[String: Any]])
        // A stored room keeps its id; a new one goes without its local one.
        #expect(sent[0]["id"] as? String == "r1")
        #expect(sent[0]["room_number"] as? String == "412")
        #expect(sent[0]["room_type"] == nil)
        #expect(sent[1]["id"] == nil)
        #expect(sent[1]["room_type"] as? String == "Twin")
        #expect(sent[1]["occupants"] as? [String] == ["m2"])
        #expect(try encode(lodgingCreate(rooms: nil))["rooms"] == nil)
    }

    @Test func updateSendsRoomsOnlyWhenAsked() throws {
        let create = lodgingCreate(rooms: [])
        #expect(try encode(TripItemsAPI.UpdateRequest(create))["rooms"] == nil)
        // Sent empty, it clears them.
        #expect(try encode(TripItemsAPI.UpdateRequest(create, sendsRooms: true))["rooms"] as? [Any] != nil)
        #expect((try encode(TripItemsAPI.UpdateRequest(create, sendsRooms: true))["rooms"] as? [Any])?.isEmpty == true)
    }

    @Test func untouchedRoomsAreLeftOut() throws {
        let draft = try assigningDraft()
        #expect(!draft.roomsChanged)
        // Reopening a room and closing it without changes doesn't count.
        draft.updateRoom(draft.rooms[0])
        #expect(!draft.roomsChanged)
    }

    @Test func editedRoomsAreSentWhole() throws {
        let draft = try assigningDraft()
        var room = draft.rooms[0]
        room.occupants = ["m2"]
        draft.updateRoom(room)
        #expect(draft.roomsChanged)
        let sent = try #require(draft.roomsToSave)
        #expect(sent.map(\.id) == ["r1", "r2"])
        #expect(sent.map(\.occupants) == [["m2"], ["m1"]])

        // Taking someone off the stay empties their room, which is a change too.
        let other = try assigningDraft()
        other.selectedMemberIds = ["m2"]
        #expect(other.roomsChanged)
        #expect(other.roomsToSave?.map(\.occupants) == [[], []])
    }

    @Test func newStaySendsRoomsOnlyWhenItHasSome() {
        let draft = TripItemDraft(tripId: "t", kind: .lodging, members: Self.roster)
        #expect(draft.roomsToSave == nil)
        var room = LodgingRoom.new()
        room.roomNumber = "7"
        draft.updateRoom(room)
        #expect(draft.roomsToSave == [TripItemsAPI.RoomRequest(roomNumber: "7")])
        #expect(TripItemDraft(tripId: "t", kind: .activity).roomsToSave == nil)
    }

    // MARK: - Import source

    @Test func decodesImportSource() throws {
        let imported = try decodeItem(#"""
        , "source": "email", "has_source": true, "edited_at": "2026-11-05T19:41:17.885521Z",
          "edited_by": {"id": "u1", "email": "sam@example.com", "display_name": "Sam", "avatar_url": null,
                        "created_at": "2026-10-01T00:00:00Z"}
        """#)
        #expect(imported.source == .email)
        #expect(imported.source?.importLabel == "Imported from email")
        #expect(imported.hasSource)
        #expect(imported.editedAt != nil)
        #expect(imported.editedBy?.displayName == "Sam")

        let screenshot = try decodeItem(kind: "transit", #", "source": "image", "has_source": false, "edited_at": null"#)
        #expect(screenshot.source == .image)
        #expect(!screenshot.hasSource)
        #expect(screenshot.editedAt == nil)

        #expect(try decodeItem(#", "source": "manual""#).source?.importLabel == nil)
        // An older server, or a source the app doesn't know yet, leaves it unknown.
        #expect(try decodeItem("").source == nil)
        #expect(try decodeItem(#", "source": "fax""#).source == nil)
    }

    // MARK: - Real bookings

    /// A stay from Dec 27, 3 PM to Dec 29, 11 AM, as edited.
    private func bookedDraft(type: String = "hotel") throws -> TripItemDraft {
        var item = try decodeItem(#", "lodging": {"property_type": "\#(type)"}"#)
        // Wall clocks are floating UTC dates.
        item.endsAtLocal = try #require(ISO8601DateFormatter().date(from: "2026-12-29T11:00:00Z"))
        return TripItemDraft(tripId: "t", kind: .lodging, item: item)
    }

    @Test func movingABookedStaysDatesAsksFirst() throws {
        let draft = try bookedDraft()
        #expect(!draft.changesBookedDates)

        // A new time on the same day doesn't ask.
        draft.startsAt = draft.startsAt?.addingTimeInterval(2 * 3600)
        #expect(!draft.changesBookedDates)

        // A day later does, for check-in or check-out.
        draft.startsAt = draft.startsAt?.addingTimeInterval(86_400)
        #expect(draft.changesBookedDates)
        let checkOut = try bookedDraft()
        checkOut.endsAt = checkOut.endsAt?.addingTimeInterval(86_400)
        #expect(checkOut.changesBookedDates)
        let cleared = try bookedDraft()
        cleared.endsAt = nil
        #expect(cleared.changesBookedDates)
    }

    @Test func otherStaysAndNewOnesDontAsk() throws {
        let other = try bookedDraft(type: "other")
        other.startsAt = other.startsAt?.addingTimeInterval(86_400)
        #expect(!other.changesBookedDates)
        #expect(!other.deletesBookedStay)

        // Changing a stay to Other while moving it doesn't ask either.
        let retyped = try bookedDraft()
        retyped.propertyType = .other
        retyped.startsAt = retyped.startsAt?.addingTimeInterval(86_400)
        #expect(!retyped.changesBookedDates)

        let new = TripItemDraft(tripId: "t", kind: .lodging)
        new.startsAt = new.startsAt?.addingTimeInterval(86_400)
        #expect(!new.changesBookedDates)
        #expect(!new.deletesBookedStay)

        let activity = try decodeItem(kind: "activity", "")
        #expect(!TripItemDraft(tripId: "t", kind: .activity, item: activity).deletesBookedStay)
    }

    @Test func deletingABookedStayAsksFirst() throws {
        #expect(try bookedDraft().deletesBookedStay)
        // A stay with no type set still has a booking as far as we know.
        let untyped = try decodeItem("")
        #expect(TripItemDraft(tripId: "t", kind: .lodging, item: untyped).deletesBookedStay)
    }

    @Test func changingABookedStaysRoomCountAsksFirst() throws {
        let draft = try assigningDraft()
        #expect(!draft.changesBookedRoomCount)

        // Who's in which room isn't the property's business.
        var room = draft.rooms[0]
        room.occupants = ["m2"]
        room.roomNumber = "9"
        draft.updateRoom(room)
        #expect(!draft.changesBookedRoomCount)

        // Adding or dropping a room is.
        var added = LodgingRoom.new()
        added.roomType = "Twin"
        draft.updateRoom(added)
        #expect(draft.changesBookedRoomCount)
        let dropped = try assigningDraft()
        dropped.rooms.removeLast()
        #expect(dropped.changesBookedRoomCount)

        let other = try assigningDraft()
        other.propertyType = .other
        other.updateRoom(added)
        #expect(!other.changesBookedRoomCount)
        #expect(!TripItemDraft(tripId: "t", kind: .lodging).changesBookedRoomCount)
    }

    @Test func bookingPopupSaysWhatChanged() {
        #expect(BookingChangePopup.Change.edit(changingDates: false, rooms: false) == nil)
        let rooms = BookingChangePopup(change: .edit(dates: false, rooms: true), onConfirm: {}, onClose: {})
        #expect(rooms.question == "Change the number of rooms?")
        #expect(rooms.explanation.contains("new number of rooms has already been confirmed"))
        let both = BookingChangePopup(change: .edit(dates: true, rooms: true), onConfirm: {}, onClose: {})
        #expect(both.question == "Change this stay's dates and rooms?")
        #expect(both.explanation.contains("new dates and rooms have already been confirmed"))
        let dates = BookingChangePopup(change: .edit(dates: true, rooms: false), onConfirm: {}, onClose: {})
        #expect(dates.question == "Change this stay's dates?")
        #expect(dates.confirmTitle == "Changed with Property")
    }

    @Test func deletingARoomKeepsItsPeopleOnTheStay() throws {
        let draft = try assigningDraft()
        draft.removeRoom(id: "r2")
        #expect(draft.rooms.map(\.id) == ["r1"])
        #expect(draft.selectedMemberIds == ["m1", "m2"])
        #expect(draft.roomAssignments(for: "r1").participants.map(\.id) == ["m1", "m2"])
        // One fewer room is a change to the booking, and sent.
        #expect(draft.changesBookedRoomCount)
        #expect(draft.roomsToSave?.map(\.id) == ["r1"])
    }
}
