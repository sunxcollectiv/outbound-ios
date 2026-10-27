//
//  TripCalendarGrid.swift
//  outbound
//

import Foundation

/// The days of a trip laid out as full Sunday–Saturday weeks. Days before the start
/// and after the end pad the first and last weeks so every row has seven days; those
/// padding days are marked as outside the trip.
struct TripCalendarGrid {
    struct Day: Identifiable, Equatable {
        /// Midnight of the day in the grid's calendar.
        let date: Date
        let isInTrip: Bool
        var id: Date { date }
    }

    let weeks: [[Day]]

    /// Builds the weeks covering `start` through `end` (inclusive, by calendar day).
    /// An `end` before `start` is treated as a one-day trip.
    init(start: Date, end: Date, calendar: Calendar = .sundayFirst) {
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = max(firstDay, calendar.startOfDay(for: end))
        // Back up to the Sunday on or before the start, and forward to the Saturday on
        // or after the end.
        let leading = (calendar.component(.weekday, from: firstDay) - calendar.firstWeekday + 7) % 7
        let trailing = 6 - (calendar.component(.weekday, from: lastDay) - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: firstDay),
              let gridEnd = calendar.date(byAdding: .day, value: trailing, to: lastDay) else {
            weeks = []
            return
        }

        var days: [Day] = []
        var date = gridStart
        while date <= gridEnd {
            days.append(Day(date: date, isInTrip: date >= firstDay && date <= lastDay))
            guard let next = calendar.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }
        weeks = stride(from: 0, to: days.count, by: 7).map { Array(days[$0..<min($0 + 7, days.count)]) }
    }

    /// One calendar month of a trip: the month's first day and a grid of just the trip
    /// days in that month (days of neighboring months pad the weeks, outside the trip).
    struct Month: Identifiable {
        let start: Date
        let grid: TripCalendarGrid
        var id: Date { start }
    }

    /// Splits `start` through `end` into a grid per calendar month it touches, in order.
    static func months(start: Date, end: Date, calendar: Calendar = .sundayFirst) -> [Month] {
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = max(firstDay, calendar.startOfDay(for: end))
        guard var monthStart = calendar.dateInterval(of: .month, for: firstDay)?.start else { return [] }

        var months: [Month] = []
        while monthStart <= lastDay {
            guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: monthStart),
                  let monthEnd = calendar.date(byAdding: .day, value: -1, to: nextMonth) else { break }
            let grid = TripCalendarGrid(start: max(firstDay, monthStart), end: min(lastDay, monthEnd), calendar: calendar)
            months.append(Month(start: monthStart, grid: grid))
            monthStart = nextMonth
        }
        return months
    }
}

extension Calendar {
    /// Gregorian in the device zone with weeks starting on Sunday, regardless of locale.
    static var sundayFirst: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.firstWeekday = 1
        return calendar
    }
}
