//
//  ItineraryTimeline.swift
//  outbound
//

import Foundation

/// One card on a day of the itinerary: an item entry as the server placed it, or a
/// stop along a transit booking's legs.
enum ItineraryCard: Identifiable {
    case entry(ItineraryEntry)
    case transit(TransitStop)

    var id: String {
        switch self {
        case .entry(let entry): "entry|\(entry.id)"
        case .transit(let stop): "stop|\(stop.id)"
        }
    }

    /// The trip item the card belongs to (for a stop, the booking it's part of).
    var item: TripItem {
        switch self {
        case .entry(let entry): entry.item
        case .transit(let stop): stop.item
        }
    }

    /// Orders a day's cards by the wall clock shown on them, then the true instant.
    fileprivate var sortKey: (Date, Date) {
        switch self {
        case .entry(let entry): (entry.displayLocal, entry.displayInstant)
        case .transit(let stop): (stop.local, stop.instant)
        }
    }
}

/// A point along a transit booking where the traveler is at a place: setting off on
/// the first leg, changing between legs, or arriving at the end of a leg.
struct TransitStop: Identifiable {
    enum Kind {
        case departure
        case arrival
        /// Arriving on one leg and leaving on the next, the same day.
        case layover

        var label: String {
            switch self {
            case .departure: "Departure"
            case .arrival: "Arrival"
            case .layover: "Layover"
            }
        }
    }

    /// The booking this stop is part of.
    let item: TripItem
    let kind: Kind
    /// The leg arriving here; nil for a departure.
    let inbound: TransitSegment?
    /// The leg leaving from here; nil for an arrival.
    let outbound: TransitSegment?
    /// The wall clock the stop is shown at (arrival time when arriving, else departure).
    let local: Date
    /// The true moment of `local` (UTC for zoneless legs), for ordering.
    let instant: Date

    var id: String { "\(item.id)|\(inbound?.id ?? "")|\(outbound?.id ?? "")" }

    /// Where the stop is: the inbound leg's destination, else the outbound leg's origin.
    var place: Place? { inbound?.endPlace ?? outbound?.place }

    /// The 1-based position of `segment` within its booking, and the leg count.
    func legIndex(of segment: TransitSegment) -> (number: Int, count: Int)? {
        guard let index = item.segments.firstIndex(where: { $0.id == segment.id }) else { return nil }
        return (index + 1, item.segments.count)
    }

    /// Time on the ground between legs at a layover; nil for other stops.
    var layoverDuration: Duration? {
        guard kind == .layover, let outbound else { return nil }
        let leaves = outbound.startsAtUtc ?? TripItem.instant(ofLocal: outbound.startsAtLocal, in: .gmt)
        return .seconds(max(leaves.timeIntervalSince(instant), 0))
    }

    /// The stop's wall clock as written, e.g. "4:00 PM".
    func timeText(_ style: Date.FormatStyle) -> String {
        Self.wallText(local, style)
    }

    /// The outbound leg's departure wall clock, e.g. "4:00 PM"; nil without one.
    func departureText(_ style: Date.FormatStyle) -> String? {
        outbound.map { Self.wallText($0.startsAtLocal, style) }
    }

    /// The stop's calendar date as "yyyy-MM-dd", matching `ItineraryDay.date`.
    var date: String { Self.dayFormatter.string(from: local) }

    /// The stops along `item`'s legs, in travel order: a departure, then between each
    /// pair of legs either a layover (same day) or a separate arrival and departure (an
    /// overnight connection), then a final arrival. Legs without an arrival time only
    /// contribute their departure.
    static func stops(for item: TripItem) -> [TransitStop] {
        let legs = item.segments
        guard let first = legs.first else { return [] }

        func departure(_ leg: TransitSegment) -> TransitStop {
            TransitStop(item: item, kind: .departure, inbound: nil, outbound: leg,
                        local: leg.startsAtLocal,
                        instant: leg.startsAtUtc ?? TripItem.instant(ofLocal: leg.startsAtLocal, in: .gmt))
        }
        func arrival(_ leg: TransitSegment, then next: TransitSegment? = nil, kind: Kind = .arrival) -> TransitStop? {
            guard let end = leg.endsAtLocal else { return nil }
            return TransitStop(item: item, kind: kind, inbound: leg, outbound: next,
                               local: end,
                               instant: leg.endsAtUtc ?? TripItem.instant(ofLocal: end, in: .gmt))
        }

        var stops = [departure(first)]
        for (inbound, outbound) in zip(legs, legs.dropFirst()) {
            if let end = inbound.endsAtLocal,
               dayFormatter.string(from: end) == dayFormatter.string(from: outbound.startsAtLocal),
               let layover = arrival(inbound, then: outbound, kind: .layover) {
                stops.append(layover)
            } else {
                if let landed = arrival(inbound) { stops.append(landed) }
                stops.append(departure(outbound))
            }
        }
        if let last = legs.last, let landed = arrival(last) { stops.append(landed) }
        return stops
    }

    private static func wallText(_ local: Date, _ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = .gmt
        return local.formatted(style)
    }

    /// Wall clocks are floating UTC dates, so their calendar date is read in UTC.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Builds each day's cards from the itinerary. Transit with segments is laid out from
/// its legs (each stop on the day its wall clock falls on); every other entry stays
/// where the server put it.
enum ItineraryTimeline {
    /// Cards keyed by `ItineraryDay.date`, each day sorted by the time shown.
    static func cards(for days: [ItineraryDay]) -> [String: [ItineraryCard]] {
        let dates = Set(days.map(\.date))
        var byDate: [String: [ItineraryCard]] = [:]
        var laidOut = Set<String>()

        for day in days {
            for entry in day.entries {
                let item = entry.item
                guard item.kind == .transit, !item.segments.isEmpty else {
                    byDate[day.date, default: []].append(.entry(entry))
                    continue
                }
                // A booking's entries (departure + arrival) all lay out the same legs.
                guard laidOut.insert(item.id).inserted else { continue }
                for stop in TransitStop.stops(for: item) {
                    // Fall back to the entry's day if the stop lands outside the trip's days.
                    let date = dates.contains(stop.date) ? stop.date : day.date
                    byDate[date, default: []].append(.transit(stop))
                }
            }
        }
        return byDate.mapValues { $0.sorted { $0.sortKey < $1.sortKey } }
    }
}
