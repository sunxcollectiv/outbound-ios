//
//  PricingStore.swift
//  outbound
//

import Foundation
import Observation

/// The rate tables (`/pricing/schedule`). No sign-in needed.
enum PricingAPI {
    /// The schedule new trips are priced under.
    static let current = Endpoint(path: "/pricing/schedule", requiresAuth: false, cachesResponse: true)

    /// One schedule by its key, e.g. the one an older trip is still priced under. 404
    /// for a key the server doesn't know.
    static func schedule(key: String) -> Endpoint {
        Endpoint(path: "/pricing/schedule", query: [URLQueryItem(name: "key", value: key)], requiresAuth: false, cachesResponse: true)
    }
}

/// The pricing schedules, from the server and kept on disk, so prices can be shown and
/// worked out offline.
///
/// There can be several: rates are versioned, and each trip stays on the schedule it
/// was created under. `current` is the one new trips get; others are loaded by key as
/// they're needed (from a quote's `schedule`, or a trip's `priceSchedule`).
@Observable
final class PricingStore {
    /// Every schedule loaded so far, by key.
    private(set) var schedules: [String: PricingSchedule] = [:]
    /// The key of the schedule new trips get, once known.
    private(set) var currentKey: String?
    /// Keys that couldn't be loaded from the server or disk.
    private(set) var unavailableKeys: Set<String> = []
    /// Whether the current schedule couldn't be loaded and none was saved.
    private(set) var currentUnavailable = false

    private let api: APIClient

    init(api: APIClient = .shared) {
        self.api = api
        if let saved = api.cached(PricingAPI.current, as: PricingSchedule.self) {
            currentKey = saved.key
            schedules[saved.key] = saved
        }
    }

    /// The schedule new trips are priced under.
    var current: PricingSchedule? { currentKey.flatMap { schedules[$0] } }

    /// The schedule with `key`, or the current one for nil. Nil until it's loaded.
    func schedule(key: String?) -> PricingSchedule? {
        guard let key else { return current }
        return schedules[key]
    }

    /// The schedule `trip` is priced under: the one it names, or nil when it doesn't
    /// name one (a server that doesn't send `price_schedule`) or that one isn't loaded.
    /// Never assumes the current one, which would misprice an older trip.
    func schedule(for trip: Trip) -> PricingSchedule? {
        trip.priceSchedule.flatMap { schedules[$0] }
    }

    /// Whether `key` (nil: the current schedule) couldn't be loaded.
    func isUnavailable(key: String?) -> Bool {
        key.map { unavailableKeys.contains($0) } ?? currentUnavailable
    }

    /// Fetches the current schedule, keeping the saved copy if the server can't be reached.
    func loadCurrent() async {
        do {
            let loaded = try await api.send(PricingAPI.current, as: PricingSchedule.self)
            schedules[loaded.key] = loaded
            currentKey = loaded.key
            currentUnavailable = false
        } catch {
            currentUnavailable = current == nil
        }
    }

    /// Makes sure the schedule with `key` (nil: the current one) is loaded: from disk if
    /// it was saved, otherwise from the server. A schedule never changes once
    /// published, so a saved one isn't fetched again.
    func load(key: String?) async {
        guard let key else {
            await loadCurrent()
            return
        }
        guard schedules[key] == nil else { return }
        let endpoint = PricingAPI.schedule(key: key)
        if let saved = api.cached(endpoint, as: PricingSchedule.self) {
            schedules[key] = saved
            return
        }
        do {
            schedules[key] = try await api.send(endpoint, as: PricingSchedule.self)
            unavailableKeys.remove(key)
        } catch {
            unavailableKeys.insert(key)
        }
    }

    /// Loads the schedules `trips` are priced under, for any that aren't loaded yet.
    func load(for trips: [Trip]) async {
        for key in Set(trips.compactMap(\.priceSchedule)) {
            await load(key: key)
        }
    }
}
