//
//  TripsAPI.swift
//  outbound
//

import Foundation

/// `TripRead` from the backend.
struct Trip: Codable, Identifiable, Equatable {
    let id: String
    var title: String
    var description: String?
    /// Calendar dates in "yyyy-MM-dd" form (the API's `date` type — no time component),
    /// so they're kept as strings rather than `Date`.
    var startDate: String
    var endDate: String
    var coverImageUrl: String?
    let createdAt: Date
    let updatedAt: Date
}

/// Request shapes for the trips endpoints.
///
///     GET  /trips          -> [TripRead]
///     POST /trips  TripCreate -> TripRead (201)
enum TripsAPI {
    /// `TripCreate` — body for `POST /trips`. Timezone and locations are derived from
    /// the trip's items later, so only name, dates, and description are sent here.
    struct CreateRequest: Encodable {
        let title: String
        let description: String?
        let startDate: String
        let endDate: String
    }

    static let list = Endpoint(path: "/trips")

    static func create(_ body: CreateRequest) -> Endpoint {
        Endpoint(path: "/trips", method: .post, body: body)
    }
}
