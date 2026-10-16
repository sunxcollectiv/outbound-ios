//
//  TripDaysAPI.swift
//  outbound
//

import Foundation

/// `TripDayRead` — one row per calendar date of a trip. Created with the trip and kept
/// in sync with its dates. Its `timezones` seed the zone picker when adding items to a
/// day (the first entry is the default for new items).
///
/// The itinerary endpoint doesn't carry these fields yet, so the client loads days
/// alongside the itinerary and joins on `date`.
struct TripDay: Decodable, Identifiable {
    let date: String
    let dayNumber: Int
    let name: String?
    let timezones: [String]
    let place: Place?

    var id: String { date }

    /// The day's zones as `TimeZone` values, dropping any the device can't resolve.
    var timeZones: [TimeZone] {
        timezones.compactMap(TimeZone.init(identifier:))
    }
}

/// Request shapes for a trip's days.
///
///     GET   /trips/{id}/days                   -> [TripDayRead]
///     PATCH /trips/{id}/days/{YYYY-MM-DD}       -> TripDayRead (organizers only)
enum TripDaysAPI {
    /// `TripDayUpdate` — body for `PATCH /trips/{id}/days/{date}`. All fields optional;
    /// `timezones` may be `[]` but not null. Only non-nil fields are sent.
    struct UpdateRequest: Encodable {
        var name: String?
        var timezones: [String]?
        var placeId: String?
    }

    static func list(tripId: String) -> Endpoint {
        Endpoint(path: "/trips/\(tripId)/days")
    }

    static func update(tripId: String, date: String, _ body: UpdateRequest) -> Endpoint {
        Endpoint(path: "/trips/\(tripId)/days/\(date)", method: .patch, body: body)
    }
}
