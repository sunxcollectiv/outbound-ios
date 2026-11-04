//
//  TripGroupPartTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// When the edit form says which trip in a group is being edited.
struct TripGroupPartTests {
    private func user(_ id: String) -> User {
        User(id: id, email: "\(id)@example.com", displayName: id, avatarUrl: nil, createdAt: .now)
    }

    private func trip(_ id: String, organizers: [String], members: [String] = []) -> Trip {
        var trip = Trip(id: id, title: id, startDate: "2026-12-07", endDate: "2026-12-11", createdAt: .now, updatedAt: .now)
        trip.members = organizers.map { TripMember(id: "\(id)-\($0)", email: "\($0)@example.com", user: user($0), role: .organizer) }
            + members.map { TripMember(id: "\(id)-\($0)", email: "\($0)@example.com", user: user($0), role: .member) }
        return trip
    }

    @Test func extensionOrganizerIsToldWhichTrip() {
        let home = trip("home", organizers: ["owner"], members: ["sun"])
        let after = trip("after", organizers: ["sun"])
        #expect(TripGroupPart.forEditing(home, primary: home, extensions: [after], userId: "sun") == .primary)
        #expect(TripGroupPart.forEditing(after, primary: home, extensions: [after], userId: "sun") == .extension)
    }

    @Test func primaryOrganizerWithoutAnExtensionSeesNothing() {
        let home = trip("home", organizers: ["owner"], members: ["sun"])
        let after = trip("after", organizers: ["sun"])
        #expect(TripGroupPart.forEditing(home, primary: home, extensions: [after], userId: "owner") == nil)
        // Nor does anyone on a trip with no extensions.
        #expect(TripGroupPart.forEditing(home, primary: home, extensions: [], userId: "sun") == nil)
    }

    @Test func plainMemberOfAnExtensionSeesNothing() {
        let home = trip("home", organizers: ["owner"])
        let after = trip("after", organizers: ["owner"], members: ["sun"])
        #expect(TripGroupPart.forEditing(home, primary: home, extensions: [after], userId: "sun") == nil)
    }
}
