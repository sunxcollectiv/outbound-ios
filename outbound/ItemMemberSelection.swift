//
//  ItemMemberSelection.swift
//  outbound
//

import Foundation

/// Who a trip item is for, in terms of the trip's members: how a selection is seeded
/// from an item, summarized on a row or card, and turned into the backend's
/// `participants`. Shared by the item form and the itinerary cards.
struct ItemMemberSelection {
    /// Everyone on the trip.
    let members: [TripMember]
    /// The signed-in user's id.
    let currentUserId: String?

    /// The signed-in user's row on this trip, if they're on it.
    var currentMember: TripMember? {
        members.first { $0.user?.id != nil && $0.user?.id == currentUserId }
    }

    /// A new item starts with everyone; an existing one with exactly its participants.
    func initialSelection(for item: TripItem?) -> Set<String> {
        guard let item else { return Set(members.map(\.id)) }
        return Set(item.participants.map(\.member.id))
    }

    /// "Everyone", "Just you", "You and 2 others", or a head count without you.
    func summary(of selected: Set<String>) -> String {
        // A trip without a loaded roster only has the user creating the item.
        if members.isEmpty { return "Just you" }
        if selected.isEmpty { return "No one" }
        if selected.count == members.count && members.count > 1 { return "Everyone" }
        let includesYou = currentMember.map { selected.contains($0.id) } ?? false
        let others = selected.count - (includesYou ? 1 : 0)
        switch (includesYou, others) {
        case (true, 0): return "Just you"
        case (true, 1): return "You and 1 other"
        case (true, _): return "You and \(others) others"
        case (false, 1): return "1 person"
        case (false, _): return "\(others) people"
        }
    }

    /// The SF Symbol for how many are going: one person, or two people for two or more.
    /// An empty selection (a trip without a roster) counts as one.
    static func symbol(forCount count: Int) -> String {
        count <= 1 ? "person.fill" : "person.2.fill"
    }

    /// The `participants` to send: exactly the selected members, in roster order so the
    /// request is stable. No status is sent, so anyone already on the item keeps their
    /// answer.
    func participants(for selected: Set<String>) -> [TripItemsAPI.ParticipantRequest] {
        members.filter { selected.contains($0.id) }.map { TripItemsAPI.ParticipantRequest(memberId: $0.id) }
    }
}
