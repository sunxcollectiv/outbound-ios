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

/// One calendar day of a trip, including any lodging that spans it and the day's entries.
struct ItineraryDay: Decodable, Identifiable {
    let date: String
    let dayNumber: Int
    let lodging: [LodgingStay]
    /// The day's items. A transit leg with a real arrival appears twice across the
    /// itinerary (departure and arrival entries sharing one `item.id`).
    let entries: [ItineraryEntry]

    var id: Int { dayNumber }

    private enum CodingKeys: String, CodingKey {
        case date, dayNumber, lodging
        case entries = "items"
    }

    /// Re-sorts `entries` by the wall clock shown on each card. The server orders by UTC
    /// instant, which zoneless items don't have, so they'd otherwise land after zoned
    /// ones regardless of time. Ties fall back to the instant (UTC for zoneless).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        dayNumber = try c.decode(Int.self, forKey: .dayNumber)
        lodging = try c.decode([LodgingStay].self, forKey: .lodging)
        entries = try c.decode([ItineraryEntry].self, forKey: .entries).sorted {
            ($0.displayLocal, $0.displayInstant) < ($1.displayLocal, $1.displayInstant)
        }
    }

    init(date: String, dayNumber: Int, lodging: [LodgingStay], entries: [ItineraryEntry]) {
        self.date = date
        self.dayNumber = dayNumber
        self.lodging = lodging
        self.entries = entries
    }

    /// The distinct items on this day (entries and lodging), one per record.
    var uniqueItems: [TripItem] {
        var seen = Set<String>()
        return (entries.map(\.item) + lodging.map(\.item)).filter { seen.insert($0.id).inserted }
    }

    /// The day's calendar date (local midnight), or nil if the string won't parse.
    /// Used to seed a new item's default date to the day being viewed.
    var calendarDate: Date? { Self.isoDate.date(from: date) }

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

/// Which end of a two-ended item an itinerary entry stands for: `departure`/`arrival`
/// for transit, `checkIn`/`checkOut` for lodging.
enum ItineraryPhase: String, Decodable {
    case departure
    case arrival
    case checkIn = "check_in"
    case checkOut = "check_out"

    /// Whether the entry sits at the item's end rather than its start.
    var isEnd: Bool { self == .arrival || self == .checkOut }

    var label: String {
        switch self {
        case .departure: "Departure"
        case .arrival: "Arrival"
        case .checkIn: "Check-in"
        case .checkOut: "Check-out"
        }
    }
}

/// `ItineraryEntry` — one element of a day's `items`: the trip item plus, for an item
/// with distinct ends, which end this entry stands for. `phase` is nil otherwise.
///
/// Transit with segments is laid out from its legs instead (see `ItineraryTimeline`);
/// the entry's phase only matters for transit without them.
struct ItineraryEntry: Decodable, Identifiable {
    let item: TripItem
    let phase: ItineraryPhase?

    /// Unique per entry: both ends of one item share `item.id`.
    var id: String { "\(item.id)|\(phase?.rawValue ?? "")" }

    private var isEnd: Bool { phase?.isEnd ?? false }

    /// The place this entry is at: the destination for an arrival, the lodging itself
    /// at check-out (its end place, if any), else the item's place.
    var place: Place? {
        switch phase {
        case .arrival: item.endPlace
        case .checkOut: item.endPlace ?? item.place
        default: item.place
        }
    }

    /// The wall clock this entry is shown (and sorted) at: the end for an end phase.
    var displayLocal: Date { isEnd ? (item.endsAtLocal ?? item.startsAtLocal) : item.startsAtLocal }

    /// The true moment of `displayLocal`, for tie-breaking (UTC for zoneless items).
    var displayInstant: Date {
        isEnd
            ? (item.endInstant(fallbackZone: .gmt) ?? item.startInstant(fallbackZone: .gmt))
            : item.startInstant(fallbackZone: .gmt)
    }

    /// The entry's wall clock as written, e.g. "4:00 PM".
    func timeText(_ style: Date.FormatStyle) -> String {
        isEnd ? (item.endText(style) ?? item.startText(style)) : item.startText(style)
    }

    init(item: TripItem, phase: ItineraryPhase? = nil) {
        self.item = item
        self.phase = phase
    }

    private enum CodingKeys: String, CodingKey {
        case item, phase
    }

    /// Also accepts the older flat shape (a bare `TripItemRead`), so the app keeps
    /// working against a server that hasn't shipped the wrapper.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.item) {
            item = try c.decode(TripItem.self, forKey: .item)
            phase = try c.decodeIfPresent(ItineraryPhase.self, forKey: .phase)
        } else {
            item = try TripItem(from: decoder)
            phase = nil
        }
    }
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
        func item(_ hour: Int, _ minute: Int, _ kind: TripItemKind, _ title: String, notes: String? = nil, tags: [String] = [], image: String? = nil) -> ItineraryEntry {
            var components = DateComponents()
            components.year = 2026; components.month = 11; components.day = 1
            components.hour = hour; components.minute = minute
            // Wall clocks are floating UTC dates (see `TripItem.startsAtLocal`).
            var floating = Calendar(identifier: .gregorian)
            floating.timeZone = .gmt
            let date = floating.date(from: components) ?? Date(timeIntervalSince1970: 0)
            return ItineraryEntry(item: TripItem(
                id: "\(title)", tripId: "sample", kind: kind, scope: .group,
                title: title, notes: notes, tags: tags, startsAtLocal: date, startsAtUtc: nil, startTimezone: nil,
                endsAtLocal: nil, endsAtUtc: nil, endTimezone: nil, imageUrl: image, createdAt: date, updatedAt: date)
            )
        }
        return [
            ItineraryDay(date: "2026-11-01", dayNumber: 1, lodging: [], entries: [
                item(12, 0, .lodging, "Early check-in confirmed", notes: "Standard check-in 15:00"),
                item(15, 0, .activity, "Sean Salim arrives", notes: "NH 106 · joins from Osaka"),
                item(18, 30, .activity, "Omoide Yokocho dinner", notes: "Nishi-Shinjuku 1-chome", tags: ["Reserved"], image: "https://example.com/yokocho.jpg"),
            ]),
            ItineraryDay(date: "2026-11-02", dayNumber: 2, lodging: [], entries: [
                item(9, 30, .activity, "Tsukiji breakfast", notes: "Outer market"),
            ]),
            ItineraryDay(date: "2026-11-03", dayNumber: 3, lodging: [], entries: []),
            ItineraryDay(date: "2026-11-04", dayNumber: 4, lodging: [], entries: [
                item(11, 0, .transit, "Shinkansen to Kyoto", notes: "Nozomi 221"),
            ]),
            ItineraryDay(date: "2026-11-05", dayNumber: 5, lodging: [], entries: []),
        ]
    }()
}
#endif
