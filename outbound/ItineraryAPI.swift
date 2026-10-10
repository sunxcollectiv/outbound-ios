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

    /// The abbreviated weekday in caps for the day picker, e.g. "THU".
    var weekdayShort: String {
        guard let parsed = Self.isoDate.date(from: date) else { return "" }
        return Self.weekday.format(parsed).uppercased()
    }

    /// The calendar day-of-month for the day picker, e.g. `1`.
    var dayOfMonth: Int {
        guard let parsed = Self.isoDate.date(from: date) else { return dayNumber }
        return Calendar(identifier: .gregorian).component(.day, from: parsed)
    }

    private static let isoDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let display = Date.FormatStyle.dateTime.weekday(.abbreviated).month(.abbreviated).day()
    private static let weekday = Date.FormatStyle.dateTime.weekday(.abbreviated)
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

#if DEBUG
extension ItineraryDay {
    /// A few sample days for previewing the paged itinerary design.
    static let sampleDays: [ItineraryDay] = {
        func item(_ hour: Int, _ minute: Int, _ kind: TripItemKind, _ title: String, notes: String? = nil, tags: [String] = [], image: String? = nil) -> TripItem {
            var components = DateComponents()
            components.year = 2026; components.month = 11; components.day = 1
            components.hour = hour; components.minute = minute
            let date = Calendar.current.date(from: components) ?? Date(timeIntervalSince1970: 0)
            return TripItem(
                id: "\(title)", tripId: "sample", kind: kind, scope: .group,
                title: title, notes: notes, tags: tags, startsAt: date, endsAt: nil,
                imageUrl: image, createdAt: date, updatedAt: date
            )
        }
        return [
            ItineraryDay(date: "2026-11-01", dayNumber: 1, lodging: [], items: [
                item(12, 0, .lodging, "Early check-in confirmed", notes: "Standard check-in 15:00"),
                item(15, 0, .activity, "Sean Salim arrives", notes: "NH 106 · joins from Osaka"),
                item(18, 30, .activity, "Omoide Yokocho dinner", notes: "Nishi-Shinjuku 1-chome", tags: ["Reserved"], image: "https://example.com/yokocho.jpg"),
            ]),
            ItineraryDay(date: "2026-11-02", dayNumber: 2, lodging: [], items: [
                item(9, 30, .activity, "Tsukiji breakfast", notes: "Outer market"),
            ]),
            ItineraryDay(date: "2026-11-03", dayNumber: 3, lodging: [], items: []),
            ItineraryDay(date: "2026-11-04", dayNumber: 4, lodging: [], items: [
                item(11, 0, .transit, "Shinkansen to Kyoto", notes: "Nozomi 221"),
            ]),
            ItineraryDay(date: "2026-11-05", dayNumber: 5, lodging: [], items: []),
        ]
    }()
}
#endif
