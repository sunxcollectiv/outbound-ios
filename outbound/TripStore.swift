//
//  TripStore.swift
//  outbound
//

import Foundation
import Observation

/// Loads and holds the signed-in user's trips for the list screen.
@Observable
final class TripStore {
    private(set) var trips: [Trip] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
    }

    /// Fetches the trip list from `GET /trips`.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            trips = try await api.send(TripsAPI.list, as: [Trip].self)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Inserts a just-created trip at the top so it shows without a full reload.
    func add(_ trip: Trip) {
        trips.insert(trip, at: 0)
    }
}
