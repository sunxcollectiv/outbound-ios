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
/// Times are local wall time + an IANA zone, one zone per end of the item. The server
/// sends the wall clock (`starts_at`, no offset) alongside the same moment as a true
/// UTC instant (`starts_at_utc`, with `Z`). We keep the instant plus its zone: the
/// wall clock is recoverable by formatting the instant in that zone, which is what the
/// display helpers below do. Do not format `startsAt` without setting the zone — it
/// would print the device's wall clock, not the item's.
struct TripItem: Identifiable, Equatable {
    let id: String
    let tripId: String
    var kind: TripItemKind
    var scope: TripItemScope
    var title: String
    var notes: String?
    var tags: [String]
    /// The start moment as a true instant (decoded from `starts_at_utc`).
    var startsAt: Date
    /// The zone the start wall clock is printed in (e.g. "Asia/Tokyo").
    var startTimezone: TimeZone
    /// The end moment as a true instant; nil iff the item has no end.
    var endsAt: Date?
    /// The zone for the end wall clock; set iff `endsAt` is set.
    var endTimezone: TimeZone?
    var imageUrl: String?
    var place: Place?
    var endPlace: Place?
    let createdAt: Date
    let updatedAt: Date
}

extension TripItem {
    /// The start wall clock formatted in the item's start zone, e.g. "4:00 PM".
    func startText(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = startTimezone
        return startsAt.formatted(style)
    }

    /// The end wall clock formatted in the item's end zone, or nil when there's no end.
    func endText(_ style: Date.FormatStyle) -> String? {
        guard let endsAt, let endTimezone else { return nil }
        var style = style
        style.timeZone = endTimezone
        return endsAt.formatted(style)
    }

    /// A short zone label for the start, e.g. "PDT" or "JST".
    var startZoneAbbreviation: String {
        Self.zoneAbbreviation(startTimezone, at: startsAt)
    }

    /// A short zone label for the end, or nil when there's no end.
    var endZoneAbbreviation: String? {
        guard let endsAt, let endTimezone else { return nil }
        return Self.zoneAbbreviation(endTimezone, at: endsAt)
    }

    /// A short code for a zone at a given moment (handles DST), e.g. "EST"/"EDT".
    ///
    /// Uses `TimeZone.abbreviation(for:)` so we get three-letter codes rather than the
    /// "GMT+11"-style text `.specificName(.short)` falls back to for some zones. Zones
    /// that have no code of their own still surface as a GMT offset here; that's the one
    /// remaining case to tidy up as we extend coverage.
    static func zoneAbbreviation(_ zone: TimeZone, at date: Date) -> String {
        zone.abbreviation(for: date) ?? zone.identifier
    }
}

extension TripItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, tripId, kind, scope, title, notes, tags
        case startTimezone, endTimezone
        // We take the instants, not the naive wall-clock strings.
        case startsAtUtc, endsAtUtc
        case imageUrl, place, endPlace, createdAt, updatedAt
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
        startsAt = try c.decode(Date.self, forKey: .startsAtUtc)
        startTimezone = try Self.decodeZone(c, forKey: .startTimezone) ?? .gmt
        endsAt = try c.decodeIfPresent(Date.self, forKey: .endsAtUtc)
        endTimezone = try Self.decodeZone(c, forKey: .endTimezone)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        endPlace = try c.decodeIfPresent(Place.self, forKey: .endPlace)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    private static func decodeZone(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> TimeZone? {
        guard let identifier = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return TimeZone(identifier: identifier) ?? .gmt
    }
}

/// Request shapes for a trip's items.
///
///     GET   /trips/{id}/items                 -> [TripItemRead]
///     POST  /trips/{id}/items  TripItemCreate -> TripItemRead (201)
///     PATCH /trips/{id}/items/{itemId} TripItemUpdate -> TripItemRead
enum TripItemsAPI {
    /// `TripItemCreate` — body for `POST /trips/{id}/items`. Times are naive ISO 8601
    /// wall clocks (no offset or `Z`) paired with an IANA zone; `start_timezone` is
    /// required unless a place resolves one. `placeId`/`endPlaceId` are internal place
    /// UUIDs (from `POST /places`); nil values are omitted from the JSON.
    struct CreateRequest: Encodable {
        let kind: TripItemKind
        let scope: TripItemScope
        let title: String
        let notes: String?
        let startsAt: String
        let startTimezone: String
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
        let startTimezone: String
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
            try c.encode(startTimezone, forKey: .startTimezone)
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
        startsAt: .now,
        startTimezone: .current,
        endsAt: nil,
        endTimezone: nil,
        imageUrl: nil,
        place: nil,
        endPlace: nil,
        createdAt: .now,
        updatedAt: .now
    )
}
#endif
