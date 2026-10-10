//
//  ItineraryAPI.swift
//  outbound
//

import Foundation

/// `Itinerary` from `GET /trips/{id}/itinerary`: the trip plus a day-by-day breakdown.
struct Itinerary: Decodable {
    let trip: Trip
    let days: [ItineraryDay]
}

/// One calendar day of a trip, including any lodging that spans it and the day's items.
struct ItineraryDay: Decodable, Identifiable {
    let date: String
    let dayNumber: Int
    let lodging: [LodgingStay]
    let items: [TripItem]

    var id: Int { dayNumber }

    /// The day's date formatted as e.g. "Sat, Nov 1".
    var displayDate: String {
        guard let parsed = Self.isoDate.date(from: date) else { return date }
        return Self.display.format(parsed)
    }

    private static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let display = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
}

/// A lodging item as it applies to one day (for the bar at the top of the day).
struct LodgingStay: Decodable {
    let item: TripItem
    let phase: LodgingPhase
}

enum LodgingPhase: String, Decodable {
    case checkIn = "check_in"
    case staying
    case checkOut = "check_out"

    var label: String {
        switch self {
        case .checkIn: "Check-in"
        case .staying: "Staying"
        case .checkOut: "Check-out"
        }
    }
}

extension TripsAPI {
    static func itinerary(tripId: String) -> Endpoint {
        Endpoint(path: "/trips/\(tripId)/itinerary")
    }
}
