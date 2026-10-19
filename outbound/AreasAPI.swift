//
//  AreasAPI.swift
//  outbound
//

import Foundation

/// `AreaRead` from the backend: a geographic area such as a country, city, region,
/// or neighborhood, e.g. "Kyoto".
///
/// Only the fields the app currently uses are decoded; extra keys (parent id,
/// timestamps, …) are ignored.
struct Area: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    /// Free-form kind, e.g. "country", "city", "neighborhood". Not an enum on the
    /// backend, so new kinds can appear without notice.
    let kind: String?
    /// The broader area this one sits in, e.g. the country a city is in.
    let parent: AreaRef?
    /// Curated photos, best first. Empty until the server has fetched some; a trip
    /// lists such areas in `areasMissingPhotos`. Optional so responses that leave the
    /// field out still decode.
    var photos: [AreaPhoto]?

    /// Context shown under the name in search results, e.g. "Japan" for Kyoto.
    var subtitle: String? { parent?.name }

    /// The photo to use as a cover, if the area has one.
    var coverPhoto: AreaPhoto? { photos?.first }
}

/// `AreaPhotoRead`: an Unsplash photo of an area. `url` hotlinks Unsplash's CDN, and
/// Unsplash requires crediting `attribution` (the photographer), linked to
/// `attributionUrl`, wherever the photo is shown.
struct AreaPhoto: Codable, Identifiable, Equatable {
    let id: String
    let url: URL
    let attribution: String?
    let attributionUrl: URL?
}

/// `AreaRef`: a compact reference to another area, enough to label it.
struct AreaRef: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String?
}

/// Request shapes for the areas endpoints.
///
///     GET  /areas?q=&kind=&limit=&offset=                    -> [AreaRead]
///     POST /areas/refresh-photos  AreaPhotosRefreshRequest   -> AreaPhotosRefreshResponse
enum AreasAPI {
    /// The most ids `POST /areas/refresh-photos` accepts in one request.
    static let refreshPhotosBatchLimit = 100

    /// `AreaPhotosRefreshRequest` — the ids trips flagged in `areas_missing_photos`.
    struct RefreshPhotosRequest: Encodable {
        let areaIds: [String]
    }

    /// `AreaPhotosRefreshResponse` — the requested areas keyed by id, after the
    /// server's best-effort photo fetch. Unknown ids are left out.
    struct RefreshPhotosResponse: Decodable {
        let areas: [String: Area]
    }

    /// Asks the server to fetch photos for up to `refreshPhotosBatchLimit` areas.
    static func refreshPhotos(areaIds: [String]) -> Endpoint {
        Endpoint(path: "/areas/refresh-photos", method: .post, body: RefreshPhotosRequest(areaIds: areaIds))
    }

    /// Text-searches areas by name, best match first. `kind` restricts results to one
    /// kind (e.g. "city").
    static func search(_ query: String, kind: String? = nil, limit: Int = 10) -> Endpoint {
        var items = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let kind { items.append(URLQueryItem(name: "kind", value: kind)) }
        return Endpoint(path: "/areas", query: items)
    }
}
