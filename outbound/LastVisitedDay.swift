//
//  LastVisitedDay.swift
//  outbound
//

import Foundation

/// Remembers the day last viewed in each trip's itinerary, so reopening a trip soon
/// after lands back on that day. Kept in memory only, and forgotten an hour after the
/// trip was left.
enum LastVisitedDay {
    private static let lifetime: TimeInterval = 60 * 60

    private static var entries: [String: (dayNumber: Int, recordedAt: Date)] = [:]

    /// The day last viewed in the trip, unless it was recorded over an hour ago.
    static func dayNumber(for tripId: String) -> Int? {
        guard let entry = entries[tripId] else { return nil }
        guard Date.now.timeIntervalSince(entry.recordedAt) < lifetime else {
            entries[tripId] = nil
            return nil
        }
        return entry.dayNumber
    }

    static func record(_ dayNumber: Int, for tripId: String) {
        entries[tripId] = (dayNumber, .now)
    }
}
