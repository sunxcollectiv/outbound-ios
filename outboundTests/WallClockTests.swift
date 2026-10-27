//
//  WallClockTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct WallClockTests {
    private struct Span: Decodable {
        let end: Date?
        init(from decoder: Decoder) throws {
            end = try decoder.container(keyedBy: CodingKeys.self).decodeWallClockIfPresent(forKey: .end)
        }
        private enum CodingKeys: String, CodingKey { case end }
    }

    private func decode(_ json: String) throws -> Date? {
        try JSONDecoder().decode(Span.self, from: Data(json.utf8)).end
    }

    @Test func optionalWallClockIsNilWhenNullOrMissing() throws {
        #expect(try decode(#"{"end": null}"#) == nil)
        #expect(try decode("{}") == nil)
    }

    @Test func wallClockKeepsTheWrittenTimeIgnoringFractionalSeconds() throws {
        // Floating: the wall clock's components are held as UTC.
        let end = try decode(#"{"end": "2026-11-12T09:00:00.123"}"#)
        #expect(end == ISO8601DateFormatter().date(from: "2026-11-12T09:00:00Z"))
    }

    private static let november = ISO8601DateFormatter().date(from: "2026-11-15T12:00:00Z")!
    private static let july = ISO8601DateFormatter().date(from: "2026-07-15T12:00:00Z")!

    private func code(_ id: String, _ date: Date = november) -> String {
        WallClock.zoneAbbreviation(TimeZone(identifier: id)!, at: date)
    }

    @Test func usesUSCodesAndTracksDaylightSaving() {
        #expect(code("America/New_York") == "EST")
        #expect(code("America/New_York", Self.july) == "EDT")
    }

    @Test func findsCodesFromOtherEnglishLocales() {
        #expect(code("Australia/Melbourne") == "AEDT")
        #expect(code("Asia/Kolkata") == "IST")
    }

    @Test func fallsBackToGMTOffsetWithoutACode() {
        #expect(code("Asia/Tokyo") == "GMT+9")
    }

    @Test func keepsBSTForLondonOnly() {
        #expect(code("Europe/London", Self.july) == "BST")
        #expect(code("Asia/Dhaka") != "BST")
    }
}
