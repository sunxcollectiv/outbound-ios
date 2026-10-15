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
/// Times are local wall time + an optional IANA zone, one zone per end of the item. The
/// server sends the wall clock (`starts_at`, no offset) and, when the item has a zone,
/// the same moment as a true UTC instant (`starts_at_utc`, with `Z`; null otherwise).
///
/// The wall clock is what we display, exactly as written. It's held as a "floating"
/// date whose UTC components are the wall clock, so it must only be formatted in UTC —
/// use `startText`/`endText`. For ordering, use `startInstant(fallbackZone:)`, which
/// prefers the true instant and reads a zoneless wall clock in the given zone.
struct TripItem: Identifiable, Equatable {
    let id: String
    let tripId: String
    var kind: TripItemKind
    var scope: TripItemScope
    var title: String
    var notes: String?
    var tags: [String]
    /// The start wall clock as written (`starts_at`), as a floating UTC date.
    var startsAtLocal: Date
    /// The start moment as a true instant (`starts_at_utc`); nil for a zoneless item.
    var startsAtUtc: Date?
    /// The zone the start wall clock is printed in (e.g. "Asia/Tokyo"); nil when the
    /// item has no zone attached (missing or unrecognized), in which case no zone is shown.
    var startTimezone: TimeZone?
    /// The end wall clock as written (`ends_at`), as a floating UTC date; nil iff the
    /// item has no end.
    var endsAtLocal: Date?
    /// The end moment as a true instant (`ends_at_utc`); nil without an end or zone.
    var endsAtUtc: Date?
    /// The zone for the end wall clock; nil when there's no end or the item is zoneless.
    var endTimezone: TimeZone?
    var imageUrl: String?
    var place: Place?
    var endPlace: Place?
    let createdAt: Date
    let updatedAt: Date
}

extension TripItem {
    /// The start wall clock as written, e.g. "4:00 PM".
    func startText(_ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = .gmt
        return startsAtLocal.formatted(style)
    }

    /// The end wall clock as written, or nil when there's no end.
    func endText(_ style: Date.FormatStyle) -> String? {
        guard let endsAtLocal else { return nil }
        var style = style
        style.timeZone = .gmt
        return endsAtLocal.formatted(style)
    }

    /// The true start instant, or for a zoneless item its wall clock read in
    /// `fallbackZone` (the trip day's zone, else the device's).
    func startInstant(fallbackZone: TimeZone) -> Date {
        startsAtUtc ?? Self.instant(ofLocal: startsAtLocal, in: fallbackZone)
    }

    /// Like `startInstant(fallbackZone:)` for the end; nil when there's no end.
    func endInstant(fallbackZone: TimeZone) -> Date? {
        guard let endsAtLocal else { return nil }
        return endsAtUtc ?? Self.instant(ofLocal: endsAtLocal, in: fallbackZone)
    }

    /// A short zone label for the start, e.g. "PDT" or "JST", or nil when there's no zone.
    var startZoneAbbreviation: String? {
        startTimezone.map { Self.zoneAbbreviation($0, at: startsAtUtc ?? startsAtLocal) }
    }

    /// A short zone label for the end, or nil when there's no end or zone.
    var endZoneAbbreviation: String? {
        guard let endsAtLocal, let endTimezone else { return nil }
        return Self.zoneAbbreviation(endTimezone, at: endsAtUtc ?? endsAtLocal)
    }

    /// A floating wall clock reinterpreted as a real moment in `zone`.
    private static func instant(ofLocal local: Date, in zone: TimeZone) -> Date {
        var floating = Calendar(identifier: .gregorian)
        floating.timeZone = .gmt
        var target = Calendar(identifier: .gregorian)
        target.timeZone = zone
        let components = floating.dateComponents([.year, .month, .day, .hour, .minute, .second], from: local)
        return target.date(from: components) ?? local
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
        case startsAt, endsAt, startsAtUtc, endsAtUtc
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
        startsAtLocal = try Self.decodeLocal(c, forKey: .startsAt)
        startsAtUtc = try c.decodeIfPresent(Date.self, forKey: .startsAtUtc)
        startTimezone = try Self.decodeZone(c, forKey: .startTimezone)
        endsAtLocal = try c.decodeIfPresent(String.self, forKey: .endsAt) == nil
            ? nil : try Self.decodeLocal(c, forKey: .endsAt)
        endsAtUtc = try c.decodeIfPresent(Date.self, forKey: .endsAtUtc)
        endTimezone = try Self.decodeZone(c, forKey: .endTimezone)
        imageUrl = try c.decodeIfPresent(String.self, forKey: .imageUrl)
        place = try c.decodeIfPresent(Place.self, forKey: .place)
        endPlace = try c.decodeIfPresent(Place.self, forKey: .endPlace)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    /// Decodes a naive wall clock like "2026-11-01T11:00:00" (fractional seconds
    /// ignored) into a floating UTC date. Decoded as a string so the decoder's ISO 8601
    /// date strategy, which needs a `Z`/offset, never sees it.
    private static func decodeLocal(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> Date {
        let string = try c.decode(String.self, forKey: key)
        guard let date = localFormatter.date(from: String(string.prefix(19))) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Unrecognized local date-time: \(string)")
        }
        return date
    }

    private static let localFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static func decodeZone(_ c: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) throws -> TimeZone? {
        guard let identifier = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
        return TimeZone(identifier: identifier)
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
