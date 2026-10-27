//
//  ItineraryAPI.swift
//  outbound
//

import Foundation

/// `Itinerary` from `GET /trips/{id}/itinerary`: the trip plus a day-by-day breakdown.
struct Itinerary: Decodable {
    let trip: Trip
    let days: [ItineraryDay]
    /// Places whose Google data is due a refresh. The itinerary is usable as is; the
    /// client asks `POST /places/refresh` for these and patches its cards by id.
    let stalePlaceIds: [String]

    private enum CodingKeys: String, CodingKey { case trip, days, stalePlaceIds }

    /// Treats a missing `stale_place_ids` (an older server) as none.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        trip = try c.decode(Trip.self, forKey: .trip)
        days = try c.decode([ItineraryDay].self, forKey: .days)
        stalePlaceIds = try c.decodeIfPresent([String].self, forKey: .stalePlaceIds) ?? []
    }
}

/// One calendar day of a trip, including any lodging that spans it and the day's entries.
struct ItineraryDay: Decodable, Identifiable {
    let date: String
    let dayNumber: Int
    let lodging: [LodgingStay]
    /// The day's timeline. An item can appear more than once across the itinerary (its
    /// departure and arrival, check-in and check-out, layovers), sharing one `item.id`.
    let entries: [ItineraryEntry]

    var id: Int { dayNumber }

    private enum CodingKeys: String, CodingKey {
        case date, dayNumber, lodging
        case entries = "items"
    }

    /// Re-sorts `entries` for display; see `ordered(_:)`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        dayNumber = try c.decode(Int.self, forKey: .dayNumber)
        lodging = try c.decode([LodgingStay].self, forKey: .lodging)
        entries = Self.ordered(try c.decode([ItineraryEntry].self, forKey: .entries))
    }

    /// A day's entries in display order: by the wall clock shown on each card, ties
    /// broken by the instant (UTC for zoneless). The server orders by UTC instant,
    /// which zoneless items don't have, so they'd otherwise land after zoned ones
    /// regardless of time.
    ///
    /// A transit's entries (departure, layovers, arrival) then stay together in travel
    /// order, at the spot of its first entry on the day. Wall clocks in different zones
    /// don't compare, so sorted alone a layover could land before its own departure,
    /// and nothing else happens between legs anyway.
    static func ordered(_ entries: [ItineraryEntry]) -> [ItineraryEntry] {
        let sorted = entries.sorted {
            ($0.displayLocal, $0.displayInstant) < ($1.displayLocal, $1.displayInstant)
        }
        let transit = Dictionary(grouping: sorted.filter { $0.item.kind == .transit }, by: \.item.id)
            .mapValues { $0.sorted { $0.travelOrder < $1.travelOrder } }
        var placed = Set<String>()
        return sorted.flatMap { entry -> [ItineraryEntry] in
            guard let group = transit[entry.item.id] else { return [entry] }
            return placed.insert(entry.item.id).inserted ? group : []
        }
    }

    init(date: String, dayNumber: Int, lodging: [LodgingStay], entries: [ItineraryEntry]) {
        self.date = date
        self.dayNumber = dayNumber
        self.lodging = lodging
        self.entries = entries
    }

    /// This day without any entries or lodging for the given item, e.g. once it's deleted.
    func removing(itemId: String) -> ItineraryDay {
        ItineraryDay(
            date: date,
            dayNumber: dayNumber,
            lodging: lodging.filter { $0.item.id != itemId },
            entries: entries.filter { $0.item.id != itemId }
        )
    }

    /// The distinct items on this day (entries and lodging), one per record.
    var uniqueItems: [TripItem] {
        var seen = Set<String>()
        return (entries.map(\.item) + lodging.map(\.item)).filter { seen.insert($0.id).inserted }
    }

    /// The day's calendar date (local midnight), or nil if the string won't parse.
    /// Used to seed a new item's default date to the day being viewed.
    var calendarDate: Date? { Self.isoDate.date(from: date) }

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

    private static let weekday = Date.FormatStyle.dateTime.weekday(.abbreviated)
}

/// Which spot of an item an itinerary entry stands for: `departure`/`arrival` (and a
/// `layover` between legs) for transit, `checkIn`/`checkOut` for lodging.
enum ItineraryPhase: String, Decodable {
    case departure
    case arrival
    case layover
    case checkIn = "check_in"
    case checkOut = "check_out"

    var label: String {
        switch self {
        case .departure: "Departure"
        case .arrival: "Arrival"
        case .layover: "Layover"
        case .checkIn: "Check-in"
        case .checkOut: "Check-out"
        }
    }
}

/// `ItineraryEntry` — one card in a day's timeline. The server derives these: an item
/// with distinct ends gets one entry per end (`phase`), and a multi-leg transit also
/// gets a `layover` entry per stop between legs, carrying where and how long. Every
/// entry of an item shares `item.id`; the item is there for reference. `phase` is nil
/// for items with a single spot.
struct ItineraryEntry: Decodable, Identifiable {
    let item: TripItem
    let phase: ItineraryPhase?
    /// The place waited at, for a `layover` entry.
    let layoverPlace: Place?
    /// How long the layover lasts, in minutes, for a `layover` entry.
    let layoverMinutes: Int?
    /// The stop's zone, for a `layover` entry.
    let layoverTimezone: TimeZone?

    /// Unique per entry: an item's entries share `item.id`, and a transit can have
    /// several layovers.
    var id: String { "\(item.id)|\(phase?.rawValue ?? "")|\(layoverPlace?.id ?? "")" }

    private var isEnd: Bool { phase == .arrival || phase == .checkOut }

    /// The place this entry is at: the destination for an arrival, the stop for a
    /// layover, the lodging itself at check-out (its end place, if any), else the
    /// item's place.
    var place: Place? {
        switch phase {
        case .arrival: item.endPlace
        case .layover: layoverPlace
        case .checkOut: item.endPlace ?? item.place
        default: item.place
        }
    }

    /// For a layover, the leg that lands at the stop. The entry carries no time of its
    /// own, so the stop's arrival (and the onward departure) are read off the legs.
    var layoverInbound: TransitSegment? {
        guard phase == .layover, let stop = layoverPlace?.id else { return nil }
        return item.segments.dropLast().first { $0.endPlace?.id == stop }
    }

    /// For a layover, the leg that leaves the stop.
    var layoverOutbound: TransitSegment? {
        guard let inbound = layoverInbound,
              let index = item.segments.firstIndex(of: inbound),
              item.segments.indices.contains(index + 1) else { return nil }
        return item.segments[index + 1]
    }

    /// The zone this entry's wall clock is read in: the stop's for a layover, the end's
    /// for an end phase (a check-out falling back to the stay's start zone), else the
    /// start's. Nil for a zoneless item.
    var timeZone: TimeZone? {
        switch phase {
        case .layover: layoverTimezone ?? layoverInbound?.endTimezone
        case .arrival: item.endTimezone
        case .checkOut: item.endTimezone ?? item.startTimezone
        default: item.startTimezone
        }
    }

    /// Where this entry falls along its item: the departure, then each layover by the
    /// leg landing there, then the arrival.
    var travelOrder: Int {
        switch phase {
        case .departure, .checkIn, nil: 0
        case .layover: 1 + (layoverInbound.flatMap { item.segments.firstIndex(of: $0) } ?? 0)
        case .arrival, .checkOut: Int.max
        }
    }

    /// The leg this entry is about, for its carrier/flight label: the first leg at a
    /// departure, the last at an arrival, the onward leg at a layover.
    var segment: TransitSegment? {
        switch phase {
        case .departure: item.segments.first
        case .arrival: item.segments.last
        case .layover: layoverOutbound
        default: nil
        }
    }

    /// The wall clock this entry is shown (and sorted) at: the landing at the stop for
    /// a layover, the end for an end phase, else the start.
    var displayLocal: Date { moment.local }

    /// The true moment of `displayLocal`, for tie-breaking (UTC for zoneless items).
    var displayInstant: Date { moment.instant }

    private var moment: (local: Date, instant: Date) {
        // The span whose end this entry sits at, if any: the leg landing at a layover,
        // or the item itself for an end phase.
        let endOf: (any WallClockSpan)? = if let inbound = layoverInbound { inbound } else if isEnd { item } else { nil }
        if let endOf, let end = endOf.endsAtLocal, let instant = endOf.endInstant(fallbackZone: .gmt) {
            return (end, instant)
        }
        return (item.startsAtLocal, item.startInstant(fallbackZone: .gmt))
    }

    /// The entry's wall clock as written, e.g. "4:00 PM".
    func timeText(_ style: Date.FormatStyle) -> String {
        WallClock.text(displayLocal, style)
    }

    /// When the onward leg leaves a layover, e.g. "11:40 AM"; nil otherwise.
    func layoverDepartureText(_ style: Date.FormatStyle) -> String? {
        layoverOutbound?.startText(style)
    }

    init(item: TripItem, phase: ItineraryPhase? = nil, layoverPlace: Place? = nil, layoverMinutes: Int? = nil, layoverTimezone: TimeZone? = nil) {
        self.item = item
        self.phase = phase
        self.layoverPlace = layoverPlace
        self.layoverMinutes = layoverMinutes
        self.layoverTimezone = layoverTimezone
    }

    private enum CodingKeys: String, CodingKey {
        case item, phase, layoverPlace, layoverMinutes, layoverTimezone
    }

    /// Also accepts the older flat shape (a bare `TripItemRead`), so the app keeps
    /// working against a server that hasn't shipped the wrapper.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.item) {
            item = try c.decode(TripItem.self, forKey: .item)
            phase = try c.decodeIfPresent(ItineraryPhase.self, forKey: .phase)
            layoverPlace = try c.decodeIfPresent(Place.self, forKey: .layoverPlace)
            layoverMinutes = try c.decodeIfPresent(Int.self, forKey: .layoverMinutes)
            layoverTimezone = try c.decodeTimeZoneIfPresent(forKey: .layoverTimezone)
        } else {
            item = try TripItem(from: decoder)
            phase = nil
            layoverPlace = nil
            layoverMinutes = nil
            layoverTimezone = nil
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

    /// Where the phase falls in a day, for ordering a changeover day's stays: leaving
    /// one before arriving at the next.
    var dayOrder: Int {
        switch self {
        case .checkOut: 0
        case .staying: 1
        case .checkIn: 2
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
                id: "\(title)", tripId: "sample", kind: kind,
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
