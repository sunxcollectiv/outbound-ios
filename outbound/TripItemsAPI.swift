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
///
/// Times are local wall time + an optional IANA zone, one zone per end of the item;
/// see `WallClockSpan` for how to display and order them.
struct TripItem: Identifiable, Equatable, WallClockSpan {
    let id: String
    let tripId: String
    var kind: TripItemKind
    var scope: TripItemScope
    var title: String
    var notes: String?
    var tags: [String]
    var startsAtLocal: Date
    var startsAtUtc: Date?
    var startTimezone: TimeZone?
    var endsAtLocal: Date?
    var endsAtUtc: Date?
    var endTimezone: TimeZone?
    var imageUrl: String?
    var place: Place?
    var endPlace: Place?
    let createdAt: Date
    let updatedAt: Date
    /// The legs of a transit booking, in travel order (one for a direct trip). Empty
    /// for other kinds.
    var segments: [TransitSegment] = []
}

/// `TransitSegmentRead` — one leg of a transit booking, e.g. JFK → LAX on a two-leg
/// flight. Times follow the same wall-clock rules as `TripItem`.
struct TransitSegment: Identifiable, Equatable, Decodable, WallClockSpan {
    let id: String
    let position: Int
    var startsAtLocal: Date
    var startsAtUtc: Date?
    var startTimezone: TimeZone?
    var endsAtLocal: Date?
    var endsAtUtc: Date?
    var endTimezone: TimeZone?
    var place: Place?
    var endPlace: Place?
    var carrier: String?
    var flightNumber: String?

    /// The leg's label from its carrier and flight number, e.g. "Qantas QF 12"; nil
    /// when it has neither.
    var label: String? {
        let parts = [carrier, flightNumber].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, position, startsAt, startsAtUtc, startTimezone
        case endsAt, endsAtUtc, endTimezone, place, endPlace, carrier, flightNumber
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        position = try c.decode(Int.self, forKey: .position)
        startsAtLocal = try c.decodeWallClock(forKey: .startsAt)
        startsAtUtc = try c.decodeIfPresent(Date.self, forKey: .startsAtUtc)
        startTimezone = try c.decodeTimeZoneIfPresent(forKey: .startTimezone)
        endsAtLocal = try c.decodeWallClockIfPresent(forKey: .endsAt)
        endsAtUtc = try c.decodeIfPresent(Date.self, forKey: .endsAtUtc)
        endTimezone = try c.decodeTimeZoneIfPresent(forKey: .endTimezone)
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        endPlace = try c.decodeIfPresent(Place.self, forKey: .endPlace)
        carrier = try c.decodeIfPresent(String.self, forKey: .carrier)
        flightNumber = try c.decodeIfPresent(String.self, forKey: .flightNumber)
    }
}

extension TripItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, tripId, kind, scope, title, notes, tags
        case startTimezone, endTimezone
        case startsAt, endsAt, startsAtUtc, endsAtUtc
        case imageUrl, place, endPlace, createdAt, updatedAt, segments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        tripId = try c.decode(String.self, forKey: .tripId)
        kind = try c.decode(TripItemKind.self, forKey: .kind)
        scope = try c.decode(TripItemScope.self, forKey: .scope)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        startsAtLocal = try c.decodeWallClock(forKey: .startsAt)
        startsAtUtc = try c.decodeIfPresent(Date.self, forKey: .startsAtUtc)
        startTimezone = try c.decodeTimeZoneIfPresent(forKey: .startTimezone)
        endsAtLocal = try c.decodeWallClockIfPresent(forKey: .endsAt)
        endsAtUtc = try c.decodeIfPresent(Date.self, forKey: .endsAtUtc)
        endTimezone = try c.decodeTimeZoneIfPresent(forKey: .endTimezone)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        endPlace = try c.decodeIfPresent(Place.self, forKey: .endPlace)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        segments = (try c.decodeIfPresent([TransitSegment].self, forKey: .segments) ?? [])
            .sorted { $0.position < $1.position }
    }
}

/// Request shapes for a trip's items.
///
///     GET   /trips/{id}/items                 -> [TripItemRead]
///     POST  /trips/{id}/items  TripItemCreate -> TripItemRead (201)
///     PATCH /trips/{id}/items/{itemId} TripItemUpdate -> TripItemRead
enum TripItemsAPI {
    /// `TripItemCreate` — body for `POST /trips/{id}/items`. Times are naive ISO 8601
    /// wall clocks (no offset or `Z`) paired with an optional IANA zone; a nil zone
    /// makes a zoneless item. `placeId`/`endPlaceId` are internal place UUIDs (from
    /// `POST /places`); nil values are omitted from the JSON.
    struct CreateRequest: Encodable {
        let kind: TripItemKind
        let scope: TripItemScope
        let title: String
        let notes: String?
        let startsAt: String
        let startTimezone: String?
        let endsAt: String?
        let endTimezone: String?
        let placeId: String?
        let endPlaceId: String?
    }

    /// `TripItemUpdate` — body for `PATCH /trips/{id}/items/{itemId}`. Every field is
    /// optional server-side. It has **no `scope`** (the backend rejects extra fields),
    /// so scope isn't editable here. Nil place ids are omitted, leaving existing places
    /// untouched. A nil `endsAt` is sent as an explicit `null` to clear the end time;
    /// the server drops the end zone with it.
    struct UpdateRequest: Encodable {
        let kind: TripItemKind
        let title: String
        let notes: String?
        let startsAt: String
        let startTimezone: String?
        let endsAt: String?
        let endTimezone: String?
        let placeId: String?
        let endPlaceId: String?

        private enum CodingKeys: String, CodingKey {
            case kind, title, notes, startsAt, startTimezone, endsAt, endTimezone, placeId, endPlaceId
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encode(title, forKey: .title)
            try c.encodeIfPresent(notes, forKey: .notes)
            try c.encode(startsAt, forKey: .startsAt)
            try c.encodeIfPresent(startTimezone, forKey: .startTimezone)
            if let endsAt {
                try c.encode(endsAt, forKey: .endsAt)
                try c.encodeIfPresent(endTimezone, forKey: .endTimezone)
            } else {
                // Clear the end explicitly; `ends_at: null` also clears the end zone.
                try c.encodeNil(forKey: .endsAt)
            }
            try c.encodeIfPresent(placeId, forKey: .placeId)
            try c.encodeIfPresent(endPlaceId, forKey: .endPlaceId)
        }
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
        startsAtLocal: .now,
        startsAtUtc: nil,
        startTimezone: nil,
        endsAtLocal: nil,
        endsAtUtc: nil,
        endTimezone: nil,
        imageUrl: nil,
        place: nil,
        endPlace: nil,
        createdAt: .now,
        updatedAt: .now
    )
}
#endif
