//
//  ItemMemberSelection.swift
//  outbound
//

import Foundation

/// Who a trip item is for, in terms of the trip's members: how a selection is seeded
/// from an item, summarized on a row or card, and turned into the backend's
/// `scope` + `participants`. Shared by the item form and the itinerary cards.
struct ItemMemberSelection {
    /// Everyone on the trip.
    let members: [TripMember]
    /// The signed-in user's id.
    let currentUserId: String?

    /// The signed-in user's row on this trip, if they're on it.
    var currentMember: TripMember? {
        members.first { $0.user?.id != nil && $0.user?.id == currentUserId }
    }

    /// The member a personal item belongs to: its creator, or the signed-in user for a
    /// new item. The server always keeps them in, so their row can't be unchecked.
    func ownerMember(of item: TripItem?) -> TripMember? {
        guard let ownerId = item.map({ $0.createdBy?.id }) ?? currentUserId else { return nil }
        return members.first { $0.user?.id == ownerId }
    }

    /// A new or group item starts with everyone; a personal one with whoever's in.
    func initialSelection(for item: TripItem?) -> Set<String> {
        guard let item, item.scope == .personal else { return Set(members.map(\.id)) }
        let joined = item.participants.filter { $0.status != .declined }.map(\.member.id)
        return Set(joined + [ownerMember(of: item)?.id].compactMap { $0 })
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

    /// How a selection is saved. Everyone, picked by an organizer, is a group item
    /// (only organizers may post those); any other pick is a personal item for the
    /// chosen members, all going. Members are listed in roster order so the request
    /// is stable.
    func saved(_ selected: Set<String>) -> (scope: TripItemScope, participants: [TripItemsAPI.ParticipantRequest]?) {
        if selected.count == members.count, currentMember?.role == .organizer {
            return (.group, nil)
        }
        let going = members.filter { selected.contains($0.id) }
            .map { TripItemsAPI.ParticipantRequest(memberId: $0.id, status: .going) }
        return (.personal, going)
    }
}
