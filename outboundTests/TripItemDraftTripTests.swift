//
//  TripItemDraftTripTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// A new item saves to the trip its start date falls in, among the user's trips in a
/// group, and keeps who's going (by email) as that trip changes.
struct TripItemDraftTripTests {
    private let me = User(id: "u1", email: "me@example.com", displayName: "Me", avatarUrl: nil, createdAt: .now)

    /// "Home": me and Jesse on Dec 7–11. "Before": me and Sam on Dec 2–4.
    private var home: Trip {
        var trip = Trip(id: "home", title: "Home", startDate: "2026-12-07", endDate: "2026-12-11", createdAt: .now, updatedAt: .now)
        trip.members = [
            TripMember(id: "home-me", email: "me@example.com", user: me, role: .organizer),
            TripMember(id: "home-jesse", email: "jesse@example.com", user: nil, role: .member),
        ]
        return trip
    }

    private var before: Trip {
        var trip = Trip(id: "before", title: "Before", startDate: "2026-12-02", endDate: "2026-12-04", createdAt: .now, updatedAt: .now)
        trip.members = [
            TripMember(id: "before-me", email: "me@example.com", user: me, role: .organizer),
            TripMember(id: "before-sam", email: "sam@example.com", user: nil, role: .member),
        ]
        return trip
    }

    private var tripsByDate: [String: Trip] {
        ["2026-12-03": before, "2026-12-08": home]
    }

    /// Midday on a December day, on the device-zone canvas the draft uses.
    private func december(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 12, day: day, hour: 12))!
    }

    private func newDraft(on day: Int) -> TripItemDraft {
        TripItemDraft(tripId: home.id, kind: .activity, members: home.members ?? [], tripsByDate: tripsByDate, defaultDate: december(day))
    }

    @Test func newItemGoesToTheTripItsDateFallsIn() {
        let draft = newDraft(on: 8)
        #expect(draft.tripId == "home")
        draft.startsAt = december(3)
        #expect(draft.tripId == "before")
        #expect(draft.members.map(\.id) == ["before-me", "before-sam"])
        // A date no trip owns (a gap) stays on the trip the form was opened from.
        draft.startsAt = december(5)
        #expect(draft.tripId == "home")
    }

    @Test func whoIsGoingFollowsByEmail() {
        let draft = newDraft(on: 8)
        draft.seedSelectedMembers(currentUserId: "u1")
        #expect(draft.selectedMemberIds == ["home-me", "home-jesse"])
        // On Before, Jesse isn't on the trip; I'm selected as my row there.
        draft.startsAt = december(3)
        #expect(draft.selectedMemberIds == ["before-me"])
        // Back on Home, Jesse is still picked.
        draft.startsAt = december(8)
        #expect(draft.selectedMemberIds == ["home-me", "home-jesse"])
    }

    @Test func editedItemStaysOnItsTrip() {
        var item = TripItem.sample
        item.startsAtLocal = december(3)
        let draft = TripItemDraft(tripId: "home", kind: .activity, members: home.members ?? [], tripsByDate: tripsByDate, item: item)
        draft.startsAt = december(3)
        #expect(draft.tripId == "home")
    }
}
