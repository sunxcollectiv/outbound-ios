//
//  TransitLeg.swift
//  outbound
//

import Foundation
import Observation

/// One leg of a transit being edited: how it moves, where it leaves from and arrives
/// at, and when, each end with its own zone. Times are canvas wall clocks, as in
/// `TripItemDraft`.
@Observable
final class TransitLeg: Identifiable {
    let id = UUID()

    var transitMode: TransitMode?

    /// The origin, picked via the place search → sent as `place_id`.
    var startPlace: Place?
    /// The text the origin field searches on.
    var startPlaceText: String
    /// The origin's time zone from Google; a picked place's zone becomes `startZone`.
    var startPlaceZone: TimeZone? {
        didSet { if let startPlaceZone { startZone = startPlaceZone } }
    }
    /// The destination → sent as `end_place_id`.
    var endPlace: Place?
    var endPlaceText: String
    /// The destination's time zone from Google; a picked place's zone becomes `endZone`.
    var endPlaceZone: TimeZone? {
        didSet { if let endPlaceZone { endZone = endPlaceZone } }
    }

    /// The departure; nil once cleared, which blocks saving.
    var startsAt: Date?
    /// The arrival; nil leaves the leg without one.
    var endsAt: Date?
    var startZone: TimeZone?
    var endZone: TimeZone?

    /// Booking details of a saved leg, which the form doesn't edit. Kept so a save,
    /// which replaces every leg, doesn't drop them.
    let carrier: String?
    let flightNumber: String?
    let confirmationNumber: String?

    init(
        transitMode: TransitMode? = nil,
        startPlace: Place? = nil,
        startPlaceText: String = "",
        endPlace: Place? = nil,
        endPlaceText: String = "",
        startsAt: Date? = nil,
        endsAt: Date? = nil,
        startZone: TimeZone? = nil,
        endZone: TimeZone? = nil,
        carrier: String? = nil,
        flightNumber: String? = nil,
        confirmationNumber: String? = nil
    ) {
        self.transitMode = transitMode
        self.startPlace = startPlace
        self.startPlaceText = startPlaceText
        self.endPlace = endPlace
        self.endPlaceText = endPlaceText
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.startZone = startZone
        self.endZone = endZone
        self.carrier = carrier
        self.flightNumber = flightNumber
        self.confirmationNumber = confirmationNumber
    }

    /// A saved leg, its places counting as picked so they're sent back as they are.
    /// `mixed` never applies to a single leg, but is dropped here all the same.
    convenience init(_ segment: TransitSegment) {
        self.init(
            transitMode: segment.transitMode == .mixed ? nil : segment.transitMode,
            startPlace: segment.place,
            startPlaceText: segment.place?.name ?? "",
            endPlace: segment.endPlace,
            endPlaceText: segment.endPlace?.name ?? "",
            // `startsAtLocal` is a floating UTC date, so reading it in UTC gives the wall clock.
            startsAt: TripItemDraft.wallClock(of: segment.startsAtLocal, in: .gmt),
            endsAt: TripItemDraft.wallClock(of: segment.endsAtLocal, in: .gmt),
            startZone: segment.startTimezone,
            endZone: segment.endTimezone,
            carrier: segment.carrier,
            flightNumber: segment.flightNumber,
            confirmationNumber: segment.confirmationNumber
        )
    }

    /// A new leg to follow this one: leaving from where this one arrives, when it
    /// arrives (or departs, without an arrival), by the same means.
    func next() -> TransitLeg {
        TransitLeg(
            transitMode: transitMode,
            startPlace: endPlace,
            startPlaceText: endPlaceText,
            startsAt: endsAt ?? startsAt,
            startZone: endsAt != nil ? endZone ?? startZone : startZone
        )
    }

    /// Whether this leg arrives before it departs, comparing instants so a leg can
    /// cross zones. An arrival with no zone is read in the departure's.
    var endsBeforeStart: Bool {
        guard let startsAt, let endsAt else { return false }
        return TripItemDraft.instant(of: endsAt, in: endZone ?? startZone ?? .gmt)
            < TripItemDraft.instant(of: startsAt, in: startZone ?? .gmt)
    }

    /// The leg as sent, or nil without a departure (which the server requires).
    var request: TripItemsAPI.SegmentRequest? {
        guard let startsAt else { return nil }
        return TripItemsAPI.SegmentRequest(
            startsAt: TripItemDraft.naiveString(from: startsAt),
            startTimezone: startZone?.identifier,
            endsAt: endsAt.map(TripItemDraft.naiveString(from:)),
            endTimezone: endsAt != nil ? endZone?.identifier : nil,
            placeId: startPlace?.id,
            endPlaceId: endPlace?.id,
            transitMode: transitMode == .mixed ? nil : transitMode,
            carrier: carrier,
            flightNumber: flightNumber,
            confirmationNumber: confirmationNumber
        )
    }
}
