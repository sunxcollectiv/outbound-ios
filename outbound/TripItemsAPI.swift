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

/// How a transit moves, matching the server's `TransitMode`. `mixed` only comes
/// back from the server, for a booking whose legs differ; it's never sent.
enum TransitMode: String, Codable, CaseIterable, Identifiable {
    case flight, train, bus, ferry
    case carRental = "car_rental"
    case other, mixed

    var id: String { rawValue }

    /// The modes a person can pick.
    static let pickable: [TransitMode] = [.flight, .train, .bus, .ferry, .carRental, .other]

    var label: String {
        switch self {
        case .flight: "Flight"
        case .train: "Train"
        case .bus: "Bus"
        case .ferry: "Ferry"
        case .carRental: "Car rental"
        case .other: "Other"
        case .mixed: "Mixed"
        }
    }

    var systemImage: String {
        switch self {
        case .flight: "airplane"
        case .train: "tram.fill"
        case .bus: "bus.fill"
        case .ferry: "ferry.fill"
        case .carRental: "car.fill"
        case .other: "ellipsis"
        case .mixed: "arrow.triangle.swap"
        }
    }
}

/// What people on the trip who aren't participants see of an item, matching
/// `TripItemVisibility`. Participants always see all of it.
enum TripItemVisibility: String, Codable, CaseIterable, Identifiable {
    /// Everything.
    case open
    /// That something is on, and when: its kind, title and times.
    case closed
    /// Nothing: the item doesn't exist for them.
    case `private`

    var id: String { rawValue }
    var label: String { rawValue.capitalized }

    /// What this means for people on the trip who aren't going, for the item form.
    var explanation: String {
        switch self {
        case .open: "Everyone on the trip can see all the details."
        case .closed: "Others see only the title and time."
        case .private: "Hidden from everyone who isn't going."
        }
    }
}

/// `TripItemRead` from the backend. `place`/`endPlace` are the associated places
/// (end place is used by transit for the destination).
///
/// Times are local wall time + an optional IANA zone, one zone per end of the item;
/// see `WallClockSpan` for how to display and order them.
struct TripItem: Identifiable, Equatable, WallClockSpan {
    let id: String
    let tripId: String
    var kind: TripItemKind
    var visibility: TripItemVisibility = .open
    /// True when the caller isn't a participant on a closed item: only its kind, title
    /// and times come through, and the other details are blanked.
    var redacted = false
    /// As written; nil when the item goes by its place (a lodging can).
    var title: String?
    /// What to call the item: its title, else its place's name, else its kind. The
    /// server works it out, and leaves out the place on a redacted item.
    var displayTitle: String
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
    /// Who added the item; nil once they've left the trip.
    var createdBy: User? = nil
    /// Who the item is for, each with an optional RSVP-style answer.
    var participants: [TripItemParticipant] = []
    /// How a transit moves; nil when unknown or for other kinds.
    var transitMode: TransitMode? = nil
}

enum RsvpStatus: String, Codable {
    case going, maybe, declined
}

/// `ParticipantRead` — one trip member an item is for, and their answer if any.
struct TripItemParticipant: Decodable, Equatable {
    var member: TripMember
    var status: RsvpStatus?
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
        case id, tripId, kind, visibility, redacted, title, displayTitle, notes, tags
        case startTimezone, endTimezone
        case startsAt, endsAt, startsAtUtc, endsAtUtc
        case imageUrl, place, endPlace, createdAt, updatedAt, segments, createdBy, participants
        case transitMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        tripId = try c.decode(String.self, forKey: .tripId)
        kind = try c.decode(TripItemKind.self, forKey: .kind)
        visibility = try c.decodeIfPresent(TripItemVisibility.self, forKey: .visibility) ?? .open
        redacted = try c.decodeIfPresent(Bool.self, forKey: .redacted) ?? false
        title = try c.decodeIfPresent(String.self, forKey: .title)
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
        createdBy = try c.decodeIfPresent(User.self, forKey: .createdBy)
        participants = try c.decodeIfPresent([TripItemParticipant].self, forKey: .participants) ?? []
        // Leniently, so a mode added on the server doesn't break the whole item.
        transitMode = (try? c.decodeIfPresent(String.self, forKey: .transitMode)).flatMap { $0.flatMap(TransitMode.init) }
        displayTitle = try c.decodeIfPresent(String.self, forKey: .displayTitle)
            ?? title ?? place?.name ?? kind.label
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
    /// `POST /places`); nil values are omitted from the JSON. A lodging may go
    /// without a title when it has a place.
    struct CreateRequest: Encodable {
        let kind: TripItemKind
        var visibility: TripItemVisibility? = nil
        let title: String?
        let notes: String?
        let startsAt: String
        let startTimezone: String?
        let endsAt: String?
        let endTimezone: String?
        let placeId: String?
        let endPlaceId: String?
        /// Transit only; omitted when nil. Never `mixed`, which the server derives.
        var transitMode: TransitMode? = nil
        /// Exactly who the item is for; nobody is implied. Omitted when nil, which makes
        /// the item just for its creator.
        var participants: [ParticipantRequest]? = nil
        /// Tell the trip's other members about the new item. Omitted unless true.
        var notifyMembers: Bool? = nil
    }

    /// `ParticipantSet` — one member an item is for, by their trip-member id. A nil
    /// `status` is omitted, keeping whatever answer they already had.
    struct ParticipantRequest: Encodable, Equatable {
        let memberId: String
        var status: RsvpStatus? = nil
    }

    /// `TripItemUpdate` — body for `PATCH /trips/{id}/items/{itemId}`. Every field is
    /// optional server-side. Nil place ids are omitted, leaving existing places
    /// untouched. A nil `endsAt` is sent as an explicit `null` to clear the end time;
    /// the server drops the end zone with it. `participants` is omitted when nil; when
    /// sent it replaces who the item is for (listed members keep their answers).
    /// A nil title is omitted too, unless `nullsTitleAndPlace`.
    struct UpdateRequest: Encodable {
        let kind: TripItemKind
        var visibility: TripItemVisibility? = nil
        let title: String?
        let notes: String?
        let startsAt: String
        let startTimezone: String?
        let endsAt: String?
        let endTimezone: String?
        let placeId: String?
        let endPlaceId: String?
        /// Omitted when nil, keeping the current mode.
        var transitMode: TransitMode? = nil
        var participants: [ParticipantRequest]? = nil
        /// Tell the trip's other members what changed. Omitted unless true.
        var notifyMembers: Bool? = nil
        /// Send a nil title or place id as an explicit `null`, clearing it, rather than
        /// omitting it. For kinds that go by a title or a place (a lodging, an
        /// activity), so removing either one clears it.
        var nullsTitleAndPlace = false

        private enum CodingKeys: String, CodingKey {
            case kind, visibility, title, notes, startsAt, startTimezone, endsAt, endTimezone, placeId, endPlaceId
            case transitMode, participants, notifyMembers
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encodeIfPresent(visibility, forKey: .visibility)
            try encode(title, forKey: .title, in: &c)
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
            try encode(placeId, forKey: .placeId, in: &c)
            try c.encodeIfPresent(endPlaceId, forKey: .endPlaceId)
            try c.encodeIfPresent(transitMode, forKey: .transitMode)
            try c.encodeIfPresent(participants, forKey: .participants)
            try c.encodeIfPresent(notifyMembers, forKey: .notifyMembers)
        }

        /// A nil `value` as `null` when `nullsTitleAndPlace`, else left out.
        private func encode(_ value: String?, forKey key: CodingKeys, in c: inout KeyedEncodingContainer<CodingKeys>) throws {
            if let value {
                try c.encode(value, forKey: key)
            } else if nullsTitleAndPlace {
                try c.encodeNil(forKey: key)
            }
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

    static func delete(tripId: String, itemId: String) -> Endpoint {
        Endpoint(path: "/trips/\(tripId)/items/\(itemId)", method: .delete)
    }
}

extension TripItemsAPI.UpdateRequest {
    /// An update carrying the same fields as `create`, so a form can build its body
    /// once for both. Kept in an extension to leave the memberwise init in place.
    init(_ create: TripItemsAPI.CreateRequest, nullsTitleAndPlace: Bool = false) {
        self.init(
            kind: create.kind,
            visibility: create.visibility,
            title: create.title,
            notes: create.notes,
            startsAt: create.startsAt,
            startTimezone: create.startTimezone,
            endsAt: create.endsAt,
            endTimezone: create.endTimezone,
            placeId: create.placeId,
            endPlaceId: create.endPlaceId,
            transitMode: create.transitMode,
            participants: create.participants,
            notifyMembers: create.notifyMembers,
            nullsTitleAndPlace: nullsTitleAndPlace
        )
    }
}

#if DEBUG
extension TripItem {
    static let sample = TripItem(
        id: "sample-item",
        tripId: "sample",
        kind: .activity,
        title: "Land at HND",
        displayTitle: "Land at HND",
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
