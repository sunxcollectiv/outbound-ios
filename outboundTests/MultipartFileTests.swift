//
//  MultipartFileTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

struct MultipartFileTests {
    @Test func bodyWrapsTheFileInOneBoundedPart() throws {
        let file = MultipartFile(field: "file", filename: "screenshot.png", contentType: "image/png", data: Data("PNGDATA".utf8))
        let (data, contentType) = file.body

        let boundary = try #require(contentType.split(separator: "boundary=").last.map(String.init))
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text == """
        --\(boundary)\r
        Content-Disposition: form-data; name="file"; filename="screenshot.png"\r
        Content-Type: image/png\r
        \r
        PNGDATA\r
        --\(boundary)--\r

        """)
    }
}
