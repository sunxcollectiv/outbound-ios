//
//  TripsAPI.swift
//  outbound
//

import Foundation

/// `TripRead` from the backend.
struct Trip: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var description: String?
    /// Calendar dates in "yyyy-MM-dd" form (the API's `date` type — no time component),
    /// so they're kept as strings rather than `Date`.
    var startDate: String
    var endDate: String
    var coverImageUrl: String?
    /// The areas (countries/cities) this trip covers, in order. Optional so trips
    /// still decode from a backend that doesn't send the field yet.
    var areas: [Area]?
    /// Ids of `areas` that have no photos yet. The trip is usable as is; the client
    /// asks `POST /areas/refresh-photos` for these and patches the areas in.
    var areasMissingPhotos: [String]?
    var ownerId: String?
    /// Everyone on the trip, owner included, in the order they were added. Optional so
    /// trips still decode from a backend that doesn't send the field yet.
    var members: [TripMember]?
    let createdAt: Date
    let updatedAt: Date
}

enum TripRole: String, Codable {
    /// Posts group items and manages members.
    case organizer
    /// Adds their own items and RSVPs.
    case member
}

/// `TripMemberRead` — a person on the trip, by email. `user` is nil until someone
/// with that email has an account.
struct TripMember: Codable, Identifiable, Equatable {
    let id: String
    var email: String
    var user: User?
    var role: TripRole
}

extension Trip {
    /// Parses the API's "yyyy-MM-dd" calendar dates.
    private static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let monthDay = Date.FormatStyle.dateTime.month(.abbreviated).day()
    private static let monthDayYear = Date.FormatStyle.dateTime.month(.abbreviated).day().year()

    /// A human-readable date range, e.g. "Nov 1 – Nov 5, 2026".
    var dateRangeText: String {
        guard let start = Self.isoDate.date(from: startDate),
              let end = Self.isoDate.date(from: endDate) else {
            return "\(startDate) – \(endDate)"
        }
        let sameYear = Calendar.current.component(.year, from: start) == Calendar.current.component(.year, from: end)
        let startText = (sameYear ? Self.monthDay : Self.monthDayYear).format(start)
        return "\(startText) – \(Self.monthDayYear.format(end))"
    }

    /// Today as a "yyyy-MM-dd" date in the device's time zone, for comparing with trip
    /// dates (which sort correctly as strings).
    static func isoDateString(for date: Date = .now) -> String {
        isoDate.string(from: date)
    }

    /// Splits trips into upcoming (including any in progress), soonest first, and past
    /// (ended before `today`), most recent first.
    static func upcomingAndPast(_ trips: [Trip], today: String = isoDateString()) -> (upcoming: [Trip], past: [Trip]) {
        let upcoming = trips
            .filter { $0.endDate >= today }
            .sorted { ($0.startDate, $0.endDate) < ($1.startDate, $1.endDate) }
        let past = trips
            .filter { $0.endDate < today }
            .sorted { ($0.startDate, $0.endDate) > ($1.startDate, $1.endDate) }
        return (upcoming, past)
    }
}

#if DEBUG
extension Trip {
    static let sample = Trip(
        id: "sample",
        title: "Tokyo",
        description: "Autumn trip through Shinjuku",
        startDate: "2026-11-01",
        endDate: "2026-11-05",
        coverImageUrl: nil,
        createdAt: .now,
        updatedAt: .now
    )
}
#endif

/// Request shapes for the trips endpoints.
///
///     GET   /trips             -> [TripRead]
///     POST  /trips  TripCreate -> TripRead (201)
///     PATCH /trips/{id} TripUpdate -> TripRead
enum TripsAPI {
    /// `TripCreate` — body for `POST /trips`. An optional `timezone` (IANA) seeds every
    /// day of the trip with that zone, so items can be added without picking a zone each
    /// time; it's sent on creation and left nil for edits (PATCH doesn't take it).
    /// The same shape is reused for edits via `update`.
    ///
    /// `areaIds` replaces the trip's whole set of areas. Nil keys are omitted, so on
    /// an edit leave it nil to keep the existing areas untouched.
    ///
    /// `members` lists everyone besides the creator. On an edit it replaces the
    /// roster, matched by email (the owner is always kept); leave it nil to keep the
    /// roster untouched.
    struct CreateRequest: Encodable {
        let title: String
        let description: String?
        let startDate: String
        let endDate: String
        var timezone: String?
        var areaIds: [String]?
        var members: [MemberRequest]?
    }

    /// `TripMemberCreate`. A nil `role` lets the server default to `member`.
    struct MemberRequest: Encodable, Equatable {
        let email: String
        var role: TripRole?
    }

    static let list = Endpoint(path: "/trips")

    static func create(_ body: CreateRequest) -> Endpoint {
        Endpoint(path: "/trips", method: .post, body: body)
    }

    static func update(id: String, _ body: CreateRequest) -> Endpoint {
        Endpoint(path: "/trips/\(id)", method: .patch, body: body)
    }
}
