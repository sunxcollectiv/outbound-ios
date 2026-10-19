//
//  ItineraryPlaces.swift
//  outbound
//

import Foundation

/// The itinerary's places, one record per place id, so every card showing a place —
/// an item's departure and arrival, a stay's check-in and check-out, a layover, the
/// same café on two days — reads the same copy.
///
/// The itinerary payload embeds a copy of a place in each item that references it.
/// Cards look their place up here by id instead of reading that embedded copy, so
/// patching a place (e.g. from `POST /places/refresh`) updates every card at once.
struct ItineraryPlaces: Equatable {
    private(set) var byId: [String: Place] = [:]

    init() {}

    /// Indexes every place the days reference. If the payload carries one id more
    /// than once, the first copy wins (they're the same server record).
    init(days: [ItineraryDay]) {
        byId = Dictionary(days.flatMap(\.places).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Replaces the stored copy of each given place (keyed by id) with the newer one.
    mutating func update(with places: [String: Place]) {
        byId.merge(places) { _, new in new }
    }

    /// The stored copy of `place`, matched by id; `place` itself if it isn't stored.
    func current(_ place: Place?) -> Place? {
        place.map { byId[$0.id] ?? $0 }
    }

    /// `item` with each of its places (and its legs' places) swapped for the stored copy.
    func resolving(_ item: TripItem) -> TripItem {
        var item = item
        item.place = current(item.place)
        item.endPlace = current(item.endPlace)
        for index in item.segments.indices {
            item.segments[index].place = current(item.segments[index].place)
            item.segments[index].endPlace = current(item.segments[index].endPlace)
        }
        return item
    }
}

extension ItineraryDay {
    /// Every place this day references: its entries' items and their legs, layover
    /// stops, and lodging. May repeat a place.
    var places: [Place] {
        let items = entries.map(\.item) + lodging.map(\.item)
        let itemPlaces = items.flatMap { item in
            [item.place, item.endPlace] + item.segments.flatMap { [$0.place, $0.endPlace] }
        }
        return (itemPlaces + entries.map(\.layoverPlace)).compactMap { $0 }
    }
}
