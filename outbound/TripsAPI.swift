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
    let createdAt: Date
    let updatedAt: Date
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
    struct CreateRequest: Encodable {
        let title: String
        let description: String?
        let startDate: String
        let endDate: String
        var timezone: String?
        var areaIds: [String]?
    }

    static let list = Endpoint(path: "/trips")

    static func create(_ body: CreateRequest) -> Endpoint {
        Endpoint(path: "/trips", method: .post, body: body)
    }

    static func update(id: String, _ body: CreateRequest) -> Endpoint {
        Endpoint(path: "/trips/\(id)", method: .patch, body: body)
    }
}
