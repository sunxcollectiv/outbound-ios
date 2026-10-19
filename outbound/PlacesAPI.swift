//
//  PlacesAPI.swift
//  outbound
//

import Foundation

/// `PlaceRead` from the backend — an internal place in our own database. Registered
/// from a Google place id via `POST /places`, which stores it and hands back this
/// record; the backend enriches it (address, coords, …) afterward. The `id` is what
/// trip items reference as `place_id` / `end_place_id`.
///
/// Only the fields the app currently uses are decoded; extra keys (area, google_data,
/// timestamps, …) are ignored, and enriched fields may be null right after creation.
struct Place: Codable, Identifiable, Equatable {
    let id: String
    /// Null right after creation — the backend enriches name/address/coords later.
    let name: String?
    let category: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let timezone: String?
    let photoUrl: String?
    let googlePlaceId: String?
    /// The venue's cover photo, resolved from Google by the backend. Nil when the place
    /// has no usable photo.
    let coverPhoto: CoverPhoto?

    /// The place's IANA timezone, if the backend has resolved one.
    var timeZone: TimeZone? {
        timezone.flatMap(TimeZone.init(identifier:))
    }
}

/// `CoverPhoto` on `PlaceRead`: a Google place photo the backend has already resolved.
///
/// `url` embeds an API key and redirects to a short-lived CDN image, so it's for the
/// current render only: never persist it, rewrite it, or re-host the bytes. A fresh one
/// comes with the next fetch of the place. Google requires showing `attributions`
/// wherever the image appears.
struct CoverPhoto: Codable, Equatable {
    let url: URL
    let attributions: [Attribution]
    /// Advisory only: the server owns refreshing the photo.
    let isStale: Bool?

    /// A photographer credit; link the name to `uri` when present. Google can omit the
    /// name, in which case there's nothing to show for this entry.
    struct Attribution: Codable, Equatable {
        let displayName: String?
        let uri: URL?
    }

    private enum CodingKeys: String, CodingKey { case url, attributions, isStale }

    /// Tolerates a missing `attributions` list as empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(URL.self, forKey: .url)
        attributions = try c.decodeIfPresent([Attribution].self, forKey: .attributions) ?? []
        isStale = try c.decodeIfPresent(Bool.self, forKey: .isStale)
    }
}

/// Request shapes for places.
///
///     POST /places  PlaceFromGoogle -> PlaceRead (201)
enum PlacesAPI {
    /// `PlaceFromGoogle` — body for `POST /places`. The one thing the client supplies
    /// to register a place is its Google place id; the backend fills in the rest.
    struct CreateRequest: Encodable {
        let googlePlaceId: String
    }

    static func create(googlePlaceId: String) -> Endpoint {
        Endpoint(path: "/places", method: .post, body: CreateRequest(googlePlaceId: googlePlaceId))
    }
}
