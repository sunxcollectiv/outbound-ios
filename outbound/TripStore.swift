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
    /// The background fetch of missing area photos, replaced by each load.
    private var photoRefresh: Task<Void, Never>?

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
            // The list is already showing; photos patch in when they arrive, and the
            // load (and pull-to-refresh) doesn't wait for them.
            refreshAreaPhotos(for: trips)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Inserts a just-created trip at the top so it shows without a full reload.
    func add(_ trip: Trip) {
        trips.insert(trip, at: 0)
        refreshAreaPhotos(for: [trip])
    }

    /// Asks the server for photos of the areas these trips flagged as missing them (in
    /// batches of `AreasAPI.refreshPhotosBatchLimit`), patching each batch in as it
    /// lands. Runs in the background so callers don't wait on it. Best-effort: a
    /// failed batch leaves its areas without photos.
    private func refreshAreaPhotos(for trips: [Trip]) {
        var seen = Set<String>()
        let ids = trips.flatMap { $0.areasMissingPhotos ?? [] }.filter { seen.insert($0).inserted }
        guard !ids.isEmpty else { return }

        photoRefresh?.cancel()
        photoRefresh = Task { [api] in
            for start in stride(from: 0, to: ids.count, by: AreasAPI.refreshPhotosBatchLimit) {
                let batch = Array(ids[start..<min(start + AreasAPI.refreshPhotosBatchLimit, ids.count)])
                guard let response = try? await api.send(
                    AreasAPI.refreshPhotos(areaIds: batch),
                    as: AreasAPI.RefreshPhotosResponse.self
                ) else { continue }
                guard !Task.isCancelled else { return }
                patchAreas(response.areas)
            }
        }
    }

    /// Swaps refreshed areas into every trip that has them, and drops those that now
    /// have photos from the trip's missing list.
    private func patchAreas(_ refreshed: [String: Area]) {
        for index in trips.indices {
            guard let areas = trips[index].areas else { continue }
            trips[index].areas = areas.map { refreshed[$0.id] ?? $0 }
            trips[index].areasMissingPhotos?.removeAll { refreshed[$0]?.coverPhoto != nil }
        }
    }
}
