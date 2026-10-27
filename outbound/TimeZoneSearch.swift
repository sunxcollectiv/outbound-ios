//
//  TimeZoneSearch.swift
//  outbound
//

import Foundation

/// Finds time zones by what people type: a city ("tokyo", "new york"), a region
/// ("europe/lon") or an abbreviation ("JST"), and labels them for display.
enum TimeZoneSearch {
    /// The city part of a zone's identifier, e.g. "New York" for America/New_York.
    static func city(_ zone: TimeZone) -> String {
        (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    /// A friendly label for a zone, e.g. "Tokyo (JST)", using the abbreviation in
    /// effect at `date` (so EST vs EDT is right for the item's day).
    static func label(_ zone: TimeZone, at date: Date = .now) -> String {
        "\(city(zone)) (\(WallClock.zoneAbbreviation(zone, at: date)))"
    }

    /// Up to `limit` zones matching `query`, best first: cities starting with it, then
    /// abbreviations equal to it, then identifiers containing it anywhere. Empty for a
    /// blank query.
    static func matches(
        _ query: String,
        at date: Date = .now,
        limit: Int = 4,
        identifiers: [String] = TimeZone.knownTimeZoneIdentifiers
    ) -> [TimeZone] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        let zones = identifiers.compactMap(TimeZone.init(identifier:))

        func rank(_ zone: TimeZone) -> Int? {
            let city = city(zone).lowercased()
            let identifier = zone.identifier.lowercased().replacingOccurrences(of: "_", with: " ")
            if city.hasPrefix(needle) { return 0 }
            if WallClock.zoneAbbreviation(zone, at: date).lowercased() == needle { return 1 }
            if identifier.contains(needle) { return 2 }
            return nil
        }

        return zones
            .compactMap { zone in rank(zone).map { (zone, $0) } }
            .sorted { ($0.1, city($0.0)) < ($1.1, city($1.0)) }
            .prefix(limit)
            .map(\.0)
    }
}
