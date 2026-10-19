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
}
