//
//  TripCalendarGridTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct TripCalendarGridTests {
    private let calendar = Calendar.sundayFirst

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func dayNumbers(_ week: [TripCalendarGrid.Day]) -> [Int] {
        week.map { calendar.component(.day, from: $0.date) }
    }

    @Test func midweekTripFitsOneFullWeek() {
        // Nov 3, 2026 is a Tuesday.
        let grid = TripCalendarGrid(start: day(2026, 11, 3), end: day(2026, 11, 6), calendar: calendar)
        #expect(grid.weeks.count == 1)
        #expect(dayNumbers(grid.weeks[0]) == [1, 2, 3, 4, 5, 6, 7])
        #expect(grid.weeks[0].map(\.isInTrip) == [false, false, true, true, true, true, false])
    }

    @Test func tripSpanningWeeksPadsBothEnds() {
        // Saturday Nov 7 through Monday Nov 9.
        let grid = TripCalendarGrid(start: day(2026, 11, 7), end: day(2026, 11, 9), calendar: calendar)
        #expect(grid.weeks.count == 2)
        #expect(grid.weeks.allSatisfy { $0.count == 7 })
        #expect(dayNumbers(grid.weeks[0]) == [1, 2, 3, 4, 5, 6, 7])
        #expect(dayNumbers(grid.weeks[1]) == [8, 9, 10, 11, 12, 13, 14])
        #expect(grid.weeks.flatMap { $0 }.filter(\.isInTrip).count == 3)
    }

    @Test func paddingCrossesMonthBoundaries() {
        // Tuesday Dec 1 back to Sunday Nov 29; Thursday Dec 31 on to Saturday Jan 2.
        let grid = TripCalendarGrid(start: day(2026, 12, 1), end: day(2026, 12, 31), calendar: calendar)
        #expect(grid.weeks.first?.first?.date == day(2026, 11, 29))
        #expect(grid.weeks.last?.last?.date == day(2027, 1, 2))
        #expect(grid.weeks.allSatisfy { $0.count == 7 })
    }

    @Test func fullSundayToSaturdayTripHasNoPadding() {
        let grid = TripCalendarGrid(start: day(2026, 11, 1), end: day(2026, 11, 7), calendar: calendar)
        #expect(grid.weeks.count == 1)
        #expect(grid.weeks[0].allSatisfy { $0.isInTrip })
    }

    @Test func singleMonthTripIsOneSection() {
        let months = TripCalendarGrid.months(start: day(2026, 11, 11), end: day(2026, 11, 19), calendar: calendar)
        #expect(months.map(\.start) == [day(2026, 11, 1)])
        #expect(months[0].grid.weeks.flatMap { $0 }.filter(\.isInTrip).count == 9)
    }

    @Test func tripAcrossMonthsSplitsIntoSections() {
        // Dec 23, 2026 through Jan 14, 2027.
        let months = TripCalendarGrid.months(start: day(2026, 12, 23), end: day(2027, 1, 14), calendar: calendar)
        #expect(months.map(\.start) == [day(2026, 12, 1), day(2027, 1, 1)])

        let december = months[0].grid.weeks.flatMap { $0 }
        #expect(december.filter(\.isInTrip).map(\.date).first == day(2026, 12, 23))
        #expect(december.filter(\.isInTrip).map(\.date).last == day(2026, 12, 31))
        // The last December week runs into January, which pads it outside the trip.
        #expect(december.last?.date == day(2027, 1, 2))
        #expect(december.last?.isInTrip == false)

        let january = months[1].grid.weeks.flatMap { $0 }
        #expect(january.filter(\.isInTrip).map(\.date).first == day(2027, 1, 1))
        #expect(january.filter(\.isInTrip).map(\.date).last == day(2027, 1, 14))
        #expect(january.first?.date == day(2026, 12, 27))
        #expect(january.first?.isInTrip == false)
        #expect(months.allSatisfy { $0.grid.weeks.allSatisfy { $0.count == 7 } })
    }

    @Test func tripTouchingThreeMonthsHasThreeSections() {
        let months = TripCalendarGrid.months(start: day(2026, 10, 30), end: day(2026, 12, 2), calendar: calendar)
        #expect(months.map(\.start) == [day(2026, 10, 1), day(2026, 11, 1), day(2026, 12, 1)])
        #expect(months[1].grid.weeks.flatMap { $0 }.filter(\.isInTrip).count == 30)
    }

    @Test func endBeforeStartIsOneDay() {
        let grid = TripCalendarGrid(start: day(2026, 11, 4), end: day(2026, 11, 2), calendar: calendar)
        #expect(grid.weeks.count == 1)
        #expect(grid.weeks[0].filter(\.isInTrip).map(\.date) == [day(2026, 11, 4)])
    }
}
