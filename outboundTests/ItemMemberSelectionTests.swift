//
//  ItemMemberSelectionTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct ItemMemberSelectionTests {
    private let me = User(id: "u1", email: "me@example.com", displayName: "Me", avatarUrl: nil, createdAt: .now)
    private var members: [TripMember] {
        [
            TripMember(id: "m1", email: "me@example.com", user: me, role: .organizer),
            TripMember(id: "m2", email: "jesse@example.com", user: nil, role: .member),
            TripMember(id: "m3", email: "sam@example.com", user: nil, role: .member),
        ]
    }

    private func item(participants: [(String, RsvpStatus?)]) -> TripItem {
        var item = TripItem.sample
        item.participants = participants.map { id, status in
            TripItemParticipant(member: members.first { $0.id == id }!, status: status)
        }
        return item
    }

    @Test func newItemStartsWithEveryone() {
        let selection = ItemMemberSelection(members: members, currentUserId: "u1")
        #expect(selection.initialSelection(for: nil) == ["m1", "m2", "m3"])
    }

    @Test func existingItemStartsWithExactlyItsParticipants() {
        let selection = ItemMemberSelection(members: members, currentUserId: "u1")
        // Answers don't matter: a declined or unanswered participant is still on the item.
        let existing = item(participants: [("m2", .going), ("m3", .declined)])
        #expect(selection.initialSelection(for: existing) == ["m2", "m3"])
        #expect(selection.initialSelection(for: item(participants: [("m1", nil)])) == ["m1"])
        #expect(selection.initialSelection(for: item(participants: [])).isEmpty)
    }

    @Test func summaries() {
        let selection = ItemMemberSelection(members: members, currentUserId: "u1")
        #expect(selection.summary(of: ["m1", "m2", "m3"]) == "Everyone")
        #expect(selection.summary(of: ["m1"]) == "Just you")
        #expect(selection.summary(of: ["m1", "m2"]) == "You and 1 other")
        #expect(selection.summary(of: ["m2", "m3"]) == "2 people")
        #expect(ItemMemberSelection(members: [], currentUserId: "u1").summary(of: []) == "Just you")
    }

    @Test func iconFollowsTheHeadCount() {
        #expect(ItemMemberSelection.symbol(forCount: 0) == "person.fill")
        #expect(ItemMemberSelection.symbol(forCount: 1) == "person.fill")
        #expect(ItemMemberSelection.symbol(forCount: 2) == "person.2.fill")
        #expect(ItemMemberSelection.symbol(forCount: 5) == "person.2.fill")
    }

    @Test func participantsAreExactlyTheSelectionInRosterOrderWithoutStatus() {
        let selection = ItemMemberSelection(members: members, currentUserId: "u1")
        #expect(selection.participants(for: ["m3", "m1"]) == [.init(memberId: "m1"), .init(memberId: "m3")])
        #expect(selection.participants(for: []).isEmpty)
    }
}
