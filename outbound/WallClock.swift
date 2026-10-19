//
//  WallClock.swift
//  outbound
//

import Foundation

/// Helpers for "floating" wall clocks: local times as written (e.g. "4:00 PM" in
/// Tokyo), held as dates whose UTC components are the wall clock. They must only be
/// formatted in UTC, and become a real moment only once read in a zone.
enum WallClock {
    /// A floating wall clock as written, e.g. "4:00 PM".
    static func text(_ local: Date, _ style: Date.FormatStyle) -> String {
        var style = style
        style.timeZone = .gmt
        return local.formatted(style)
    }

    /// A floating wall clock reinterpreted as a real moment in `zone`.
    static func instant(of local: Date, in zone: TimeZone) -> Date {
        var floating = Calendar(identifier: .gregorian)
        floating.timeZone = .gmt
        var target = Calendar(identifier: .gregorian)
        target.timeZone = zone
        let components = floating.dateComponents([.year, .month, .day, .hour, .minute, .second], from: local)
        return target.date(from: components) ?? local
    }

    /// A short code for a zone at a given moment (handles DST), e.g. "EST"/"EDT".
    ///
    /// Uses `TimeZone.abbreviation(for:)` so we get three-letter codes rather than the
    /// "GMT+11"-style text `.specificName(.short)` falls back to for some zones. Zones
    /// that have no code of their own still surface as a GMT offset here; that's the one
    /// remaining case to tidy up as we extend coverage.
    static func zoneAbbreviation(_ zone: TimeZone, at date: Date) -> String {
        zone.abbreviation(for: date) ?? zone.identifier
    }

    /// Parses a naive wall clock like "2026-11-01T11:00:00" (fractional seconds ignored).
    fileprivate static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .gmt
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()
}

/// Something that runs from a start to an optional end, each a wall clock with its own
/// zone, as the server sends them: the wall clock (`starts_at`, no offset) and, when
/// there's a zone, the same moment as a true UTC instant (`starts_at_utc`).
///
/// Display the wall clocks with `startText`/`endText`; order by
/// `startInstant(fallbackZone:)`, which prefers the true instant and reads a zoneless
/// wall clock in the given zone.
protocol WallClockSpan {
    /// The start wall clock as written (`starts_at`), as a floating UTC date.
    var startsAtLocal: Date { get }
    /// The start moment as a true instant (`starts_at_utc`); nil when zoneless.
    var startsAtUtc: Date? { get }
    /// The zone the start wall clock is printed in; nil when none is attached (missing
    /// or unrecognized), in which case no zone is shown.
    var startTimezone: TimeZone? { get }
    /// The end wall clock as written (`ends_at`); nil iff there's no end.
    var endsAtLocal: Date? { get }
    /// The end moment as a true instant (`ends_at_utc`); nil without an end or zone.
    var endsAtUtc: Date? { get }
    /// The zone for the end wall clock; nil without an end or when zoneless.
    var endTimezone: TimeZone? { get }
}

extension WallClockSpan {
    /// The start wall clock as written, e.g. "4:00 PM".
    func startText(_ style: Date.FormatStyle) -> String {
        WallClock.text(startsAtLocal, style)
    }

    /// The end wall clock as written, or nil when there's no end.
    func endText(_ style: Date.FormatStyle) -> String? {
        endsAtLocal.map { WallClock.text($0, style) }
    }

    /// The true start instant, or when zoneless its wall clock read in `fallbackZone`
    /// (the trip day's zone, else the device's).
    func startInstant(fallbackZone: TimeZone) -> Date {
        startsAtUtc ?? WallClock.instant(of: startsAtLocal, in: fallbackZone)
    }

    /// Like `startInstant(fallbackZone:)` for the end; nil when there's no end.
    func endInstant(fallbackZone: TimeZone) -> Date? {
        guard let endsAtLocal else { return nil }
        return endsAtUtc ?? WallClock.instant(of: endsAtLocal, in: fallbackZone)
    }

    /// A short zone label for the start, e.g. "PDT" or "JST", or nil when there's no zone.
    var startZoneAbbreviation: String? {
        startTimezone.map { WallClock.zoneAbbreviation($0, at: startsAtUtc ?? startsAtLocal) }
    }

    /// A short zone label for the end, or nil when there's no end or zone.
    var endZoneAbbreviation: String? {
        guard let endsAtLocal, let endTimezone else { return nil }
        return WallClock.zoneAbbreviation(endTimezone, at: endsAtUtc ?? endsAtLocal)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a naive wall clock like "2026-11-01T11:00:00" into a floating UTC date.
    /// Read as a string so the decoder's ISO 8601 date strategy, which needs a `Z` or
    /// offset, never sees it.
    func decodeWallClock(forKey key: Key) throws -> Date {
        let string = try decode(String.self, forKey: key)
        guard let date = WallClock.formatter.date(from: String(string.prefix(19))) else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Unrecognized local date-time: \(string)")
        }
        return date
    }

    /// Like `decodeWallClock(forKey:)`, nil when the key is missing or null.
    func decodeWallClockIfPresent(forKey key: Key) throws -> Date? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeWallClock(forKey: key)
    }

    /// An IANA zone identifier as a `TimeZone`; nil when missing, null or unrecognized.
    func decodeTimeZoneIfPresent(forKey key: Key) throws -> TimeZone? {
        try decodeIfPresent(String.self, forKey: key).flatMap(TimeZone.init(identifier:))
    }
}
