//
//  DateTimePopupTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct DateTimePopupTests {
    private let calendar = Calendar.sundayFirst
    private let day = Calendar.sundayFirst.date(from: DateComponents(year: 2026, month: 12, day: 23))!

    private func hourAndMinute(_ date: Date?) -> [Int]? {
        date.map { [calendar.component(.hour, from: $0), calendar.component(.minute, from: $0)] }
    }

    @Test func morningAndAfternoonHours() {
        #expect(hourAndMinute(DateTimePopup.date(on: day, hour: 9, minute: 15, isPM: false, calendar: calendar)) == [9, 15])
        #expect(hourAndMinute(DateTimePopup.date(on: day, hour: 3, minute: 30, isPM: true, calendar: calendar)) == [15, 30])
    }

    @Test func twelveAMIsMidnightAndTwelvePMIsNoon() {
        #expect(hourAndMinute(DateTimePopup.date(on: day, hour: 12, minute: 0, isPM: false, calendar: calendar)) == [0, 0])
        #expect(hourAndMinute(DateTimePopup.date(on: day, hour: 12, minute: 45, isPM: true, calendar: calendar)) == [12, 45])
    }

    @Test func keepsTheDay() {
        let date = DateTimePopup.date(on: day, hour: 11, minute: 45, isPM: true, calendar: calendar)
        #expect(date.map { calendar.isDate($0, inSameDayAs: day) } == true)
    }
}
