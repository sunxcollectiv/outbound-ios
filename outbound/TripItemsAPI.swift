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

/// What kind of place a stay is at, matching the server's `LodgingType`.
enum LodgingType: String, Codable, CaseIterable, Identifiable {
    case hotel
    case vacationRental = "vacation_rental"
    case hostel
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .hotel: "Hotel"
        case .vacationRental: "Vacation rental"
        case .hostel: "Hostel"
        case .other: "Other"
        }
    }

    /// A shorter label for tight spots (the form's picker).
    var shortLabel: String {
        switch self {
        case .vacationRental: "Rental"
        default: label
        }
    }

    var systemImage: String {
        switch self {
        case .hotel: "building.2.fill"
        case .vacationRental: "house.fill"
        case .hostel: "bed.double.fill"
        case .other: "ellipsis"
        }
    }
}

/// `LodgingRead` / `LodgingDetails` — a stay's details beyond its check-in/check-out
/// (the item's times), property (the item's place), people (its participants) and
/// rooms (the item's `rooms`). Every field is optional: an imported booking states
/// what it states, a hand-entered stay may have none.
///
/// The server replaces these whole on a PATCH, so an edit sends every field back,
/// not just the ones the form shows.
struct LodgingDetails: Equatable, Codable {
    var propertyType: LodgingType?
    /// The property's own number, as printed.
    var phone: String?
    /// The last moment the stay can be cancelled free of charge: a wall clock at the
    /// property (the stay's check-in zone), as a floating UTC date like the item's times.
    var freeCancellationUntil: Date?

    init(propertyType: LodgingType? = nil, phone: String? = nil, freeCancellationUntil: Date? = nil) {
        self.propertyType = propertyType
        self.phone = phone
        self.freeCancellationUntil = freeCancellationUntil
    }

    /// Whether nothing is known about the stay, so there's nothing to store.
    var isEmpty: Bool { self == LodgingDetails() }

    private enum CodingKeys: String, CodingKey {
        case propertyType, phone, freeCancellationUntil
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Leniently, so a type added on the server doesn't break the whole item.
        propertyType = (try? c.decodeIfPresent(String.self, forKey: .propertyType)).flatMap { $0.flatMap(LodgingType.init) }
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        freeCancellationUntil = try? c.decodeWallClockIfPresent(forKey: .freeCancellationUntil)
    }

    /// Nil fields are sent as `null` (the server's defaults anyway), keeping the body
    /// a faithful copy of the whole object it replaces. Only these keys: the server
    /// rejects any others.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(propertyType, forKey: .propertyType)
        try c.encode(phone, forKey: .phone)
        try c.encode(freeCancellationUntil.map(WallClock.naiveString), forKey: .freeCancellationUntil)
    }
}

/// `LodgingRoomRead` — one room of a stay, in the booking's order. Every detail is
/// optional; an imported booking may list rooms with only a type, or nothing at all.
struct LodgingRoom: Identifiable, Equatable, Decodable {
    let id: String
    var position: Int = 0
    /// A name for the room, e.g. "Kids' room".
    var label: String?
    var roomNumber: String?
    /// As the booking names it, e.g. "Deluxe King, City View".
    var roomType: String?
    var guests: Int?
    /// The room's own reference, when the booking gives each room one.
    var confirmationNumber: String?
    /// Trip-member ids of who's in it (match against `participants[].member.id`).
    var occupants: [String] = []
    /// Added in the app and not on the server yet, so its `id` is only a local one
    /// (never sent: the server gives a new room its own).
    var isNew = false

    private enum CodingKeys: String, CodingKey {
        case id, position, label, roomNumber, roomType, guests, confirmationNumber, occupants
    }

    init(id: String, position: Int = 0, label: String? = nil, roomNumber: String? = nil, roomType: String? = nil, guests: Int? = nil, confirmationNumber: String? = nil, occupants: [String] = [], isNew: Bool = false) {
        self.id = id
        self.position = position
        self.label = label
        self.roomNumber = roomNumber
        self.roomType = roomType
        self.guests = guests
        self.confirmationNumber = confirmationNumber
        self.occupants = occupants
        self.isNew = isNew
    }

    /// A blank room to add, with a local id.
    static func new() -> LodgingRoom {
        LodgingRoom(id: UUID().uuidString, isNew: true)
    }

    /// Whether the room says nothing at all, so there's no point keeping it.
    var isBlank: Bool {
        [label, roomNumber, roomType, confirmationNumber].allSatisfy { Self.nonBlank($0) == nil }
            && guests == nil && occupants.isEmpty
    }

    /// The room with its text fields trimmed, and blank ones cleared to nil.
    var tidied: LodgingRoom {
        var room = self
        room.label = Self.trimmed(label)
        room.roomNumber = Self.trimmed(roomNumber)
        room.roomType = Self.trimmed(roomType)
        room.confirmationNumber = Self.trimmed(confirmationNumber)
        return room
    }

    private static func trimmed(_ text: String?) -> String? {
        nonBlank(text?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        position = try c.decodeIfPresent(Int.self, forKey: .position) ?? 0
        label = try c.decodeIfPresent(String.self, forKey: .label)
        roomNumber = try c.decodeIfPresent(String.self, forKey: .roomNumber)
        roomType = try c.decodeIfPresent(String.self, forKey: .roomType)
        guests = try c.decodeIfPresent(Int.self, forKey: .guests)
        confirmationNumber = try c.decodeIfPresent(String.self, forKey: .confirmationNumber)
        occupants = try c.decodeIfPresent([String].self, forKey: .occupants) ?? []
    }

    /// What to call the room: its label, else its number ("Room 412"), else its
    /// place in the list ("Room 1", counting from `number`).
    func title(number: Int) -> String {
        if let label = Self.nonBlank(label) { return label }
        if let roomNumber = Self.nonBlank(roomNumber) { return "Room \(roomNumber)" }
        return "Room \(number)"
    }

    /// The line beside or under the title: the room type, then how many guests,
    /// e.g. "1 King Bed · 1 guest"; nil when the booking says neither.
    var summary: String? {
        let parts = [Self.nonBlank(roomType), guests.map { $0 == 1 ? "1 guest" : "\($0) guests" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func nonBlank(_ text: String?) -> String? {
        guard let text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return text
    }
}

extension LodgingDetails {
    /// The free-cancellation deadline as written at the property, with the stay's
    /// zone when it has one, e.g. "Tue, Dec 29 at 11:59 PM GMT+7".
    func cancellationText(zone: TimeZone?) -> String? {
        guard let until = freeCancellationUntil else { return nil }
        let text = WallClock.text(until, .dateTime.weekday().month().day().hour().minute())
        guard let zone else { return text }
        return "\(text) \(WallClock.zoneAbbreviation(zone, at: WallClock.instant(of: until, in: zone)))"
    }

    /// Whether the free-cancellation deadline has gone by, read in the stay's zone
    /// (the device's when it has none). False when there's no deadline.
    func cancellationHasPassed(zone: TimeZone?, now: Date = .now) -> Bool {
        guard let until = freeCancellationUntil else { return false }
        return WallClock.instant(of: until, in: zone ?? .current) <= now
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
    /// A stay's details; nil for other kinds, a stay with none, and a redacted one.
    var lodging: LodgingDetails? = nil
    /// A stay's rooms, in order; empty for other kinds and a stay that lists none.
    var rooms: [LodgingRoom] = []

    /// What sort of item this is, for badges: a stay's property type when known
    /// ("Hotel"), else its kind ("Lodging").
    var typeLabel: String {
        kind == .lodging ? lodging?.propertyType?.label ?? kind.label : kind.label
    }
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
    var transitMode: TransitMode?
    var confirmationNumber: String?

    /// The leg's label from its carrier and flight number, e.g. "Qantas QF 12"; nil
    /// when it has neither.
    var label: String? {
        let parts = [carrier, flightNumber].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private enum CodingKeys: String, CodingKey {
        case id, position, startsAt, startsAtUtc, startTimezone
        case endsAt, endsAtUtc, endTimezone, place, endPlace, carrier, flightNumber
        case transitMode, confirmationNumber
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
        transitMode = (try? c.decodeIfPresent(String.self, forKey: .transitMode)).flatMap { $0.flatMap(TransitMode.init) }
        confirmationNumber = try c.decodeIfPresent(String.self, forKey: .confirmationNumber)
    }
}

extension TripItem: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id, tripId, kind, visibility, redacted, title, displayTitle, notes, tags
        case startTimezone, endTimezone
        case startsAt, endsAt, startsAtUtc, endsAtUtc
        case imageUrl, place, endPlace, createdAt, updatedAt, segments, createdBy, participants
        case transitMode, lodging, rooms
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
        // Leniently too: a malformed details object shouldn't hide the stay.
        lodging = (try? c.decodeIfPresent(LodgingDetails.self, forKey: .lodging)) ?? nil
        rooms = ((try? c.decodeIfPresent([LodgingRoom].self, forKey: .rooms)).flatMap { $0 } ?? [])
            .sorted { $0.position < $1.position }
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
        /// The item's own start; nil for a transit sent as `segments`, whose span the
        /// server takes from its legs.
        let startsAt: String?
        let startTimezone: String?
        let endsAt: String?
        let endTimezone: String?
        let placeId: String?
        let endPlaceId: String?
        /// Transit only; omitted when nil. Never `mixed`, which the server derives.
        var transitMode: TransitMode? = nil
        /// A transit's legs, in order. When set, the item's own times, places and mode
        /// are left out: the server takes them from the legs.
        var segments: [SegmentRequest]? = nil
        /// Lodging only: the stay's details. Omitted when nil.
        var lodging: LodgingDetails? = nil
        /// Lodging only: its rooms, in order, with who's in each. Omitted when nil.
        var rooms: [RoomRequest]? = nil
        /// Exactly who the item is for; nobody is implied. Omitted when nil, which makes
        /// the item just for its creator.
        var participants: [ParticipantRequest]? = nil
        /// Tell the trip's other members about the new item. Omitted unless true.
        var notifyMembers: Bool? = nil
    }

    /// `TransitSegmentCreate` — one leg of a transit, with its own times, zones,
    /// places and mode; nil values are omitted. Every leg is sent on each save (they
    /// replace the old ones), so the booking details are carried along too.
    struct SegmentRequest: Encodable, Equatable {
        let startsAt: String
        let startTimezone: String?
        let endsAt: String?
        let endTimezone: String?
        let placeId: String?
        let endPlaceId: String?
        let transitMode: TransitMode?
        var carrier: String? = nil
        var flightNumber: String? = nil
        var confirmationNumber: String? = nil
    }

    /// `LodgingRoomSet` — one room of a stay, as sent. `id` is only for a room the
    /// server already has; a new one goes without. Nil fields are omitted, which the
    /// server takes as empty.
    struct RoomRequest: Encodable, Equatable {
        var id: String? = nil
        var label: String? = nil
        var roomNumber: String? = nil
        var roomType: String? = nil
        var guests: Int? = nil
        var confirmationNumber: String? = nil
        /// Trip-member ids of who's in it. Anyone not on the stay yet is added to it.
        var occupants: [String] = []

        init(id: String? = nil, label: String? = nil, roomNumber: String? = nil, roomType: String? = nil, guests: Int? = nil, confirmationNumber: String? = nil, occupants: [String] = []) {
            self.id = id
            self.label = label
            self.roomNumber = roomNumber
            self.roomType = roomType
            self.guests = guests
            self.confirmationNumber = confirmationNumber
            self.occupants = occupants
        }

        /// A room as sent, leaving out the local id of one added in the app.
        init(_ room: LodgingRoom) {
            self.init(
                id: room.isNew ? nil : room.id,
                label: room.label,
                roomNumber: room.roomNumber,
                roomType: room.roomType,
                guests: room.guests,
                confirmationNumber: room.confirmationNumber,
                occupants: room.occupants
            )
        }
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
        /// The item's own start; nil for a transit sent as `segments`, whose span the
        /// server takes from its legs.
        let startsAt: String?
        let startTimezone: String?
        let endsAt: String?
        let endTimezone: String?
        let placeId: String?
        let endPlaceId: String?
        /// Omitted when nil, keeping the current mode.
        var transitMode: TransitMode? = nil
        /// Replaces a transit's legs; see `CreateRequest.segments`.
        var segments: [SegmentRequest]? = nil
        /// Replaces a stay's details whole when sent (only when `sendsLodging`).
        var lodging: LodgingDetails? = nil
        /// Whether to send `lodging` at all: false leaves the stored details as they
        /// are; true sends it, a nil one as `null`, clearing them.
        var sendsLodging = false
        /// Replaces a stay's rooms when sent (only when `sendsRooms`): rooms with an
        /// `id` are kept and updated, new ones made, any left out dropped, and an
        /// empty list clears them. Left out, the stored rooms stay as they are.
        var rooms: [RoomRequest]? = nil
        var sendsRooms = false
        var participants: [ParticipantRequest]? = nil
        /// Tell the trip's other members what changed. Omitted unless true.
        var notifyMembers: Bool? = nil
        /// Send a nil title or place id as an explicit `null`, clearing it, rather than
        /// omitting it. For kinds that go by a title or a place (a lodging, an
        /// activity), so removing either one clears it.
        var nullsTitleAndPlace = false

        private enum CodingKeys: String, CodingKey {
            case kind, visibility, title, notes, startsAt, startTimezone, endsAt, endTimezone, placeId, endPlaceId
            case transitMode, segments, lodging, rooms, participants, notifyMembers
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encodeIfPresent(visibility, forKey: .visibility)
            try encode(title, forKey: .title, in: &c)
            try c.encodeIfPresent(notes, forKey: .notes)
            if let segments {
                // The server rejects the item's own span alongside its legs.
                try c.encode(segments, forKey: .segments)
            } else {
                try c.encodeIfPresent(startsAt, forKey: .startsAt)
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
            }
            if sendsLodging {
                try c.encode(lodging, forKey: .lodging)
            }
            if sendsRooms {
                // An empty list, not null, clears them: always a list when sent.
                try c.encode(rooms ?? [], forKey: .rooms)
            }
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
    init(_ create: TripItemsAPI.CreateRequest, nullsTitleAndPlace: Bool = false, sendsLodging: Bool = false, sendsRooms: Bool = false) {
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
            segments: create.segments,
            lodging: create.lodging,
            sendsLodging: sendsLodging,
            rooms: create.rooms,
            sendsRooms: sendsRooms,
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
