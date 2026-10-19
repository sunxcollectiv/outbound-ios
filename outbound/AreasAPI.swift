//
//  AreasAPI.swift
//  outbound
//

import Foundation

/// `AreaRead` from the backend: a geographic area such as a country, city, region,
/// or neighborhood, e.g. "Kyoto".
///
/// Only the fields the app currently uses are decoded; extra keys (photo, parent id,
/// timestamps, …) are ignored.
struct Area: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    /// Free-form kind, e.g. "country", "city", "neighborhood". Not an enum on the
    /// backend, so new kinds can appear without notice.
    let kind: String?
    /// The broader area this one sits in, e.g. the country a city is in.
    let parent: AreaRef?

    /// Context shown under the name in search results, e.g. "Japan" for Kyoto.
    var subtitle: String? { parent?.name }
}

/// `AreaRef`: a compact reference to another area, enough to label it.
struct AreaRef: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String?
}

/// Request shapes for the areas endpoints.
///
///     GET /areas?q=&kind=&limit=&offset= -> [AreaRead]
enum AreasAPI {
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
