//
//  PlaceCoverPhotoTests.swift
//  outboundTests
//

import Foundation
import Testing
@testable import outbound

/// How a `PlaceRead`'s server-resolved `cover_photo` decodes.
struct PlaceCoverPhotoTests {

    @Test func decodesTheCoverPhotoAndItsCredits() throws {
        let place = try decodePlace(coverPhoto: """
            {
              "url": "https://places.googleapis.com/v1/places/XYZ/photos/aaa/media?maxWidthPx=800&key=k",
              "attributions": [
                { "display_name": "Jane D", "uri": "https://maps.google.com/jane" },
                { "display_name": "Sam K" }
              ],
              "is_stale": false
            }
            """)

        let photo = try #require(place.coverPhoto)
        #expect(photo.url.absoluteString.hasPrefix("https://places.googleapis.com/v1/places/XYZ/photos/aaa/media"))
        #expect(photo.attributions.map(\.displayName) == ["Jane D", "Sam K"])
        #expect(photo.attributions.first?.uri == URL(string: "https://maps.google.com/jane"))
        #expect(photo.attributions.last?.uri == nil)
        #expect(photo.isStale == false)
    }

    @Test func aPlaceWithoutAPhotoHasNoCover() throws {
        #expect(try decodePlace(coverPhoto: "null").coverPhoto == nil)
        #expect(try decodePlace(coverPhoto: nil).coverPhoto == nil)
    }

    @Test func missingAttributionsReadAsNone() throws {
        let place = try decodePlace(coverPhoto: #"{ "url": "https://example.com/p.jpg" }"#)
        #expect(place.coverPhoto?.attributions == [])
    }

    @Test func aCreditWithoutANameStillDecodes() throws {
        let place = try decodePlace(coverPhoto: """
            { "url": "https://example.com/p.jpg", "attributions": [{ "display_name": null, "uri": null }], "is_stale": true }
            """)
        #expect(place.coverPhoto?.attributions.first?.displayName == nil)
        #expect(place.coverPhoto?.isStale == true)
    }

    // MARK: - Helpers

    /// Decodes a minimal `PlaceRead`, with `cover_photo` set to the given JSON (or left
    /// out entirely when nil), the way `APIClient` does.
    private func decodePlace(coverPhoto: String?) throws -> Place {
        let cover = coverPhoto.map { #", "cover_photo": \#($0)"# } ?? ""
        let json = #"{ "id": "p1", "name": "Blue Bottle Coffee"\#(cover) }"#
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Place.self, from: Data(json.utf8))
    }
}
