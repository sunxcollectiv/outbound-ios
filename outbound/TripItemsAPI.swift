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

/// `TripItemRead` from the backend. `place`/`endPlace` are the associated places
/// (end place is used by transit for the destination); traveler objects are omitted.
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
    var place: Place?
    var endPlace: Place?
    let createdAt: Date
    let updatedAt: Date
}

/// Request shapes for a trip's items.
///
///     GET   /trips/{id}/items                 -> [TripItemRead]
///     POST  /trips/{id}/items  TripItemCreate -> TripItemRead (201)
///     PATCH /trips/{id}/items/{itemId} TripItemUpdate -> TripItemRead
enum TripItemsAPI {
    /// `TripItemCreate` — body for `POST /trips/{id}/items`. `placeId`/`endPlaceId` are
    /// internal place UUIDs (from `POST /places`); nil values are omitted from the JSON.
    struct CreateRequest: Encodable {
        let kind: TripItemKind
        let scope: TripItemScope
        let title: String
        let notes: String?
        let startsAt: Date
        let endsAt: Date?
        let placeId: String?
        let endPlaceId: String?
    }

    /// `TripItemUpdate` — body for `PATCH /trips/{id}/items/{itemId}`. Every field is
    /// optional server-side. Notably it has **no `scope`** (the backend rejects extra
    /// fields), so scope isn't editable through this endpoint. Nil place ids are omitted,
    /// leaving any existing places untouched.
    struct UpdateRequest: Encodable {
        let kind: TripItemKind
        let title: String
        let notes: String?
        let startsAt: Date
        let endsAt: Date?
        let placeId: String?
        let endPlaceId: String?
    }

    static func list(tripId: String) -> Endpoint {
        Endpoint(path: "/trips/\(tripId)/items")
    }

    static func create(tripId: String, _ body: CreateRequest) -> Endpoint {
        Endpoint(path: "/trips/\(tripId)/items", method: .post, body: body)
    }

    static func update(tripId: String, itemId: String, _ body: UpdateRequest) -> Endpoint {
        Endpoint(path: "/trips/\(tripId)/items/\(itemId)", method: .patch, body: body)
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
        place: nil,
        endPlace: nil,
        createdAt: .now,
        updatedAt: .now
    )
}
#endif
