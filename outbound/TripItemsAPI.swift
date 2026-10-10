//
//  TripItemsAPI.swift
//  outbound
//

import Foundation

/// The kind of a trip item, matching the backend's `TripItemKind` enum.
enum TripItemKind: String, Codable, CaseIterable, Identifiable {
    case lodging
    case activity
    case transit

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Whether an item is for the whole group or a single traveler, matching `TripItemScope`.
enum TripItemScope: String, Codable, CaseIterable, Identifiable {
    case group
    case personal

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// `TripItemRead` from the backend. Nested location/traveler objects are omitted
/// for now — they'll be added when the itinerary is wired up.
struct TripItem: Codable, Identifiable, Equatable {
    let id: String
    let tripId: String
    var kind: TripItemKind
    var scope: TripItemScope
    var title: String
    var notes: String?
    var tags: [String]
    var startsAt: Date
    var endsAt: Date?
    var imageUrl: String?
    let createdAt: Date
    let updatedAt: Date
}

/// Request shapes for a trip's items.
///
///     GET  /trips/{id}/items              -> [TripItemRead]
///     POST /trips/{id}/items  TripItemCreate -> TripItemRead (201)
enum TripItemsAPI {
    /// `TripItemCreate` — body for `POST /trips/{id}/items`. Locations come later,
    /// so only kind, title, times, and notes are sent here.
    struct CreateRequest: Encodable {
        let kind: TripItemKind
        let scope: TripItemScope
        let title: String
        let notes: String?
        let startsAt: Date
        let endsAt: Date?
    }

    static func list(tripId: String) -> Endpoint {
        Endpoint(path: "/trips/\(tripId)/items")
    }

    static func create(tripId: String, _ body: CreateRequest) -> Endpoint {
        Endpoint(path: "/trips/\(tripId)/items", method: .post, body: body)
    }
}

#if DEBUG
extension TripItem {
    static let sample = TripItem(
        id: "sample-item",
        tripId: "sample",
        kind: .activity,
        scope: .group,
        title: "Land at HND",
        notes: "Terminal 3",
        tags: [],
        startsAt: .now,
        endsAt: nil,
        imageUrl: nil,
        createdAt: .now,
        updatedAt: .now
    )
}
#endif
