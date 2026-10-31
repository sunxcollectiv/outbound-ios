//
//  TripStore.swift
//  outbound
//

import Foundation
import Observation

/// Loads and holds the signed-in user's trips for the list screen.
///
/// Starts from the copy saved by the last load, so the list shows at once and still
/// shows offline; `load()` then replaces it with the server's.
@Observable
final class TripStore {
    private(set) var trips: [Trip]
    private(set) var isLoading = false
    var errorMessage: String?
    /// Whether `trips` is the saved copy and the last try to refresh it failed: the
    /// server couldn't be reached, so what's showing may be out of date.
    private(set) var isShowingSavedCopy = false
    /// When the saved copy now showing was fetched, for telling how out of date it is.
    private(set) var savedDate: Date?

    private let api: APIClient
    /// Where saved trips and their photos are kept, for clearing out unused ones.
    private let cache: ResponseCache
    /// The background fetch of missing area photos, replaced by each load.
    private var photoRefresh: Task<Void, Never>?
    /// The background save of upcoming trips' itineraries, replaced by each load.
    private var itinerarySave: Task<Void, Never>?

    /// How long a saved itinerary counts as fresh, so reloading the list doesn't
    /// re-download every upcoming trip each time.
    private static let itineraryFreshness: TimeInterval = 15 * 60

    init(api: APIClient = .shared, cache: ResponseCache = .shared) {
        self.api = api
        self.cache = cache
        trips = api.cached(TripsAPI.list, as: [Trip].self) ?? []
        savedDate = trips.isEmpty ? nil : api.cachedDate(for: TripsAPI.list)
    }

    /// Fetches the trip list from `GET /trips`.
    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            trips = try await api.send(TripsAPI.list, as: [Trip].self)
            errorMessage = nil
            isShowingSavedCopy = false
            savedDate = nil
            // The list is already showing; photos patch in when they arrive, and the
            // load (and pull-to-refresh) doesn't wait for them.
            refreshAreaPhotos(for: trips)
            removeUnusedSavedCopies()
            saveUpcomingItineraries()
        } catch {
            errorMessage = error.localizedDescription
            isShowingSavedCopy = savedDate != nil
        }
    }

    /// Swaps in an edited trip so its card updates without a full reload.
    func update(_ trip: Trip) {
        guard let index = trips.firstIndex(where: { $0.id == trip.id }) else { return }
        trips[index] = trip
        saveTrips()
        refreshAreaPhotos(for: [trip])
    }

    /// Drops a just-deleted trip so its card goes without a full reload.
    func remove(id: String) {
        trips.removeAll { $0.id == id }
        saveTrips()
    }

    /// Inserts a just-created trip at the top so it shows without a full reload.
    func add(_ trip: Trip) {
        trips.insert(trip, at: 0)
        saveTrips()
        refreshAreaPhotos(for: [trip])
    }

    /// Saves the list as changed here over the server's last copy, so an edit made
    /// just before losing the connection is what shows offline.
    private func saveTrips() {
        api.storeCached(trips, for: TripsAPI.list)
    }

    /// Deletes what's saved that no trip on the list uses any more: the itineraries of
    /// trips that were deleted or that the user was taken off, and cover photos an
    /// area has since replaced. Run after a load, when the list is the server's own.
    private func removeUnusedSavedCopies() {
        var kept: Set<String> = [TripsAPI.list.cacheKey]
        for trip in trips {
            kept.insert(TripsAPI.itinerary(tripId: trip.id).cacheKey)
            if let photo = trip.areaCoverPhoto {
                kept.insert(PlaceImageCache.diskKey(for: photo.url))
            }
        }
        cache.removeAll(except: kept)
    }

    /// Downloads the itineraries of upcoming and in-progress trips in the background,
    /// one at a time, so each opens offline even if it hasn't been opened lately (the
    /// itinerary endpoint saves its response). Ones saved in the last
    /// `itineraryFreshness` are skipped. Best-effort: a failed fetch keeps the older copy.
    private func saveUpcomingItineraries() {
        let upcoming = Trip.upcomingAndPast(trips).upcoming
        itinerarySave?.cancel()
        itinerarySave = Task { [api] in
            for trip in upcoming {
                let endpoint = TripsAPI.itinerary(tripId: trip.id)
                if let saved = api.cachedDate(for: endpoint), Date.now.timeIntervalSince(saved) < Self.itineraryFreshness {
                    continue
                }
                try? await api.send(endpoint)
                guard !Task.isCancelled else { return }
            }
        }
    }

    /// Asks the server for photos of the areas these trips flagged as missing them (in
    /// batches of `AreasAPI.refreshPhotosBatchLimit`), patching each batch in as it
    /// lands. Only each trip's first area is asked for, since that's the only one a
    /// card shows. Runs in the background so callers don't wait on it. Best-effort: a
    /// failed batch leaves its areas without photos.
    private func refreshAreaPhotos(for trips: [Trip]) {
        var seen = Set<String>()
        let ids = trips
            .compactMap { trip -> String? in
                guard let first = trip.areas?.first?.id,
                      trip.areasMissingPhotos?.contains(first) == true else { return nil }
                return first
            }
            .filter { seen.insert($0).inserted }
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
        saveTrips()
    }
}
