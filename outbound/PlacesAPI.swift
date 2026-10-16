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

    /// The place's IANA timezone, if the backend has resolved one.
    var timeZone: TimeZone? {
        timezone.flatMap(TimeZone.init(identifier:))
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
