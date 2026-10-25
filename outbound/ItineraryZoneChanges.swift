//
//  ItineraryZoneChanges.swift
//  outbound
//

import Foundation

/// Where the clock changes along a trip, e.g. landing after a flight across zones.
///
/// Cards show bare wall clocks, so a marker above the first entry in a new zone tells
/// you which clock the times from there on are in, until the next change. The trip is
/// walked in order across days, so a change carried overnight marks the top of the
/// next day. Zoneless entries take the current zone, so they never mark a change, and
/// zones that agree on the offset (New York and Toronto) count as the same clock.
enum ItineraryZoneChanges {
    /// The zone each marked entry's clock changes to, keyed by entry id. The trip's
    /// first zone isn't marked: there's no change to it.
    static func changes(in days: [ItineraryDay]) -> [String: TimeZone] {
        var changes: [String: TimeZone] = [:]
        var current: TimeZone?
        for entry in days.flatMap(\.entries) {
            guard let zone = entry.timeZone else { continue }
            if let current, !sameClock(current, zone, at: entry.displayInstant) {
                changes[entry.id] = zone
            }
            current = zone
        }
        return changes
    }

    private static func sameClock(_ a: TimeZone, _ b: TimeZone, at instant: Date) -> Bool {
        a.secondsFromGMT(for: instant) == b.secondsFromGMT(for: instant)
    }

    /// A zone's label for its marker, e.g. "Los Angeles · PST".
    static func label(for zone: TimeZone, at instant: Date) -> String {
        let city = (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
        return "\(city) · \(WallClock.zoneAbbreviation(zone, at: instant))"
    }
}
