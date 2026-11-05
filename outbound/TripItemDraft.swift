//
//  TripItemDraft.swift
//  outbound
//

import Foundation
import Observation

/// The editable state behind every trip item form, whatever its kind: who it's for,
/// its title, times, places and notes, plus saving and deleting it.
///
/// Times are held as wall clocks on a neutral canvas (the device zone), so the
/// numbers the user sees are what gets sent as the naive `starts_at`/`ends_at`.
/// The zone is chosen separately, so changing it keeps the wall time and only moves
/// the underlying instant — matching the server's "right time, wrong zone" fix.
///
/// Built with an existing `item` to edit it, or without one to create a new item of
/// `kind`. A new item starts with no time zones; each side gets one only when it's
/// picked (or comes from a place).
@Observable
final class TripItemDraft {
    let kind: TripItemKind

    /// The item being edited, or `nil` when creating a new one.
    let item: TripItem?

    /// The trip an edited item is on, or the one a new item goes to when its date
    /// isn't in `tripsByDate`.
    private let fallbackTripId: String
    /// The roster for `fallbackTripId`.
    private let fallbackMembers: [TripMember]
    /// For a new item: the trip owning each itinerary day ("yyyy-MM-dd"), so the item
    /// is saved to whichever of the user's trips its start date falls in. Empty for
    /// an edit, which stays on the item's trip.
    private let tripsByDate: [String: Trip]

    /// The trip this item saves to: an edited item's own, or for a new one the trip
    /// owning its start date.
    var tripId: String { targetTrip?.id ?? fallbackTripId }

    /// Everyone on that trip, offered in the "who's going" popup.
    var members: [TripMember] { targetTrip?.members ?? fallbackMembers }

    /// The trip owning a new item's start date, when it isn't the fallback.
    private var targetTrip: Trip? {
        guard item == nil, let start = hasLegs ? legs.first?.startsAt : startsAt else { return nil }
        return tripsByDate[Self.dayKey.string(from: start)]
    }

    /// The day a wall clock on the device-zone canvas falls on, as itinerary days name it.
    private static let dayKey: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    /// The trip's first through last day, shown in the date popup's calendar.
    let tripDates: ClosedRange<Date>?

    /// The itinerary day the form was opened from, marked in the date popup's calendar.
    let viewedDay: Date?

    /// What people who aren't going see of the item.
    var visibility: TripItemVisibility
    /// Ids of the trip members this item is for, toggled in the popup. Nil until
    /// seeded on appear, once the signed-in user is known. Kept by email underneath, so
    /// when a new item's date moves it to another trip, everyone also on that trip
    /// stays selected (as their member row there).
    var selectedMemberIds: Set<String>? {
        get { selectedEmails.map { emails in Set(members.filter { emails.contains($0.email) }.map(\.id)) } }
        set { selectedEmails = newValue.map { ids in Set(members.filter { ids.contains($0.id) }.map(\.email)) } }
    }
    private var selectedEmails: Set<String>?
    /// The selection the item was opened with, so an edit only re-sends who's in when
    /// it changed.
    private var originalMemberIds: Set<String>?
    var title: String
    /// The start wall clock; nil once cleared, which blocks saving (a start is required).
    var startsAt: Date?
    /// The end wall clock; nil means the item has no end time.
    var endsAt: Date?
    /// The start zone, when one is known (the item's, a picked place's, or the trip's
    /// default). nil shows no zone and saves the item without one.
    var startZone: TimeZone?
    /// The end zone; `nil` means "follow the start zone" until the user or a place sets it.
    var endZone: TimeZone?
    var notes: String
    /// Whether saving tells the trip's other members about the new or changed item.
    var notifyMembers = false

    /// The place for this item, picked via the location search → sent as `place_id`.
    var startPlace: Place?
    /// The text the location field searches on, kept separate from the item's title.
    var startPlaceText: String
    /// The start place's time zone from Google; a picked place's zone becomes `startZone`.
    var startPlaceZone: TimeZone? {
        didSet { if let startPlaceZone { startZone = startPlaceZone } }
    }
    /// A transit's legs, in order; empty for other kinds. Each has its own places,
    /// times and mode, and the item's own start, end and place fields go unused.
    var legs: [TransitLeg] = []

    /// A stay's property type (hotel, vacation rental, …); nil when not picked.
    /// Unused for other kinds.
    var propertyType: LodgingType?

    private(set) var isSaving = false
    private(set) var isDeleting = false
    var errorMessage: String?
    /// Bumped on every failed save so the error scrolls into view even when unchanged.
    private(set) var errorScrollTrigger = 0

    private let api = APIClient.shared

    var isEditing: Bool { item != nil }

    /// Whether this kind is made of legs, each with its own places and times (a transit).
    var hasLegs: Bool { kind == .transit }

    /// Whether a title or a place is enough to save this kind, the server calling it
    /// by its place's name when it has no title. An edit then sends both, nulls
    /// included, so removing either one clears it.
    var titleOrPlace: Bool { kind == .lodging || kind == .activity }

    /// Whether this kind is named by its place search alone: a picked place, or a
    /// name taken as typed (`typedName`), never both. A lodging is called what the
    /// hotel is, so its form leaves out the title field.
    var namedByPlaceSearch: Bool { kind == .lodging }

    /// Whether the server names this kind itself (a transit, from its route), so its
    /// form has no title field and saving needs no name.
    var namedByServer: Bool { kind == .transit }

    /// Whether the form has a title field to type a name in.
    var hasTitleField: Bool { !namedByPlaceSearch && !namedByServer }

    /// For `namedByPlaceSearch` kinds, the name taken as typed in the place search,
    /// with no place behind it; saved as the title. Nil while a place is picked or
    /// nothing is.
    var typedName: String?

    init(tripId: String, kind: TripItemKind, members: [TripMember] = [], tripsByDate: [String: Trip] = [:], tripDates: ClosedRange<Date>? = nil, item: TripItem? = nil, defaultDate: Date? = nil, viewedDay: Date? = nil) {
        fallbackTripId = tripId
        self.kind = item?.kind ?? kind
        fallbackMembers = members
        self.tripsByDate = tripsByDate
        self.tripDates = tripDates
        self.item = item
        self.viewedDay = viewedDay ?? defaultDate
        visibility = item?.visibility ?? .open
        title = item?.title ?? ""
        // Prefill the location fields with the existing place names (if the backend has
        // enriched them), leaving `startPlace` nil so an untouched edit keeps
        // the current places. Names that are still null get filled from Google on appear.
        startPlaceText = item?.place?.name ?? ""
        // (Kind checks spelled out: computed properties can't be read mid-init.)
        if self.kind == .lodging || self.kind == .activity {
            // The item's place counts as picked, so an untouched edit still has one
            // (an edit sends it, and a missing one clears it).
            startPlace = item?.place
            // A lodging with no place goes by its title, shown as the typed name.
            if self.kind == .lodging, item?.place == nil, let title = item?.title, !title.isEmpty {
                typedName = title
                startPlaceText = title
            }
        }
        notes = item?.notes ?? ""
        propertyType = item?.lodging?.propertyType
        // Load the item's wall clock onto the device-zone canvas (so the rows show
        // the same numbers), or for a new item start on the day being viewed at the
        // current time-of-day (falling back to "now" when no day was supplied).
        // `startsAtLocal` is a floating UTC date, so reading it in UTC gives the wall clock.
        startsAt = Self.wallClock(of: item?.startsAtLocal, in: .gmt)
            ?? Self.canvasStart(onDay: defaultDate, hour: Self.defaultStartHour(for: self.kind))
            ?? Self.roundedToMinuteInterval(Date())
        endsAt = Self.wallClock(of: item?.endsAtLocal, in: .gmt)
        startZone = item?.startTimezone
        endZone = item?.endTimezone

        if self.kind == .transit {
            if let segments = item?.segments, !segments.isEmpty {
                legs = segments.map(TransitLeg.init)
            } else {
                // A new transit (or one saved without legs) starts as one leg from the
                // item's own ends.
                legs = [TransitLeg(
                    transitMode: item?.transitMode == .mixed ? nil : item?.transitMode,
                    startPlace: item?.place,
                    startPlaceText: item?.place?.name ?? "",
                    endPlace: item?.endPlace,
                    endPlaceText: item?.endPlace?.name ?? "",
                    startsAt: startsAt,
                    endsAt: endsAt,
                    startZone: startZone,
                    endZone: endZone
                )]
            }
        }
    }

    // MARK: - Legs

    /// Adds a leg after the last, picking up where it arrives.
    func addLeg() {
        legs.append(legs.last?.next() ?? TransitLeg(startsAt: startsAt))
    }

    /// Removes a leg, as long as another is left.
    func removeLeg(_ leg: TransitLeg) {
        guard legs.count > 1 else { return }
        legs.removeAll { $0.id == leg.id }
    }

    /// The title to save: the typed name for `namedByPlaceSearch` kinds (nil when
    /// they have a place instead), the title field for kinds that have one, else nil
    /// (left out, so an edit keeps the server's name).
    private var titleToSave: String? {
        let name = (namedByPlaceSearch ? typedName ?? "" : hasTitleField ? title : "")
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// Whether the item is named enough to save: a title, or for `titleOrPlace`
    /// kinds, a picked place instead. Kinds the server names need neither.
    var hasName: Bool {
        namedByServer || titleToSave != nil || (titleOrPlace && startPlace != nil)
    }

    // MARK: - Members

    func memberSelection(currentUserId: String?) -> ItemMemberSelection {
        ItemMemberSelection(members: members, currentUserId: currentUserId)
    }

    func seedSelectedMembers(currentUserId: String?) {
        guard selectedMemberIds == nil else { return }
        let seeded = memberSelection(currentUserId: currentUserId).initialSelection(for: item)
        selectedMemberIds = seeded
        originalMemberIds = seeded
    }

    /// The `participants` to send: exactly who's selected. Nil leaves them to the
    /// server — on an edit when the selection is unchanged, and when there's no roster
    /// to pick from (a new item is then just for its creator).
    private func participantsToSave(currentUserId: String?) -> [TripItemsAPI.ParticipantRequest]? {
        guard !members.isEmpty, let selected = selectedMemberIds else { return nil }
        if item != nil, selected == originalMemberIds { return nil }
        return memberSelection(currentUserId: currentUserId).participants(for: selected)
    }

    /// Only offered when someone else on the trip has an account to be notified.
    func canNotifyMembers(currentUserId: String?) -> Bool {
        members.contains { $0.user != nil && $0.user?.id != currentUserId }
    }

    // MARK: - Saving

    /// Validates and saves the item, returning it once the server has it. Returns nil
    /// when validation fails or the request errors, with `errorMessage` set.
    /// `missingStartMessage` is shown when there's no start, which the API requires.
    func save(currentUserId: String?, missingStartMessage: String) async -> TripItem? {
        guard hasName else { return nil }
        // A transit's legs carry its times; other kinds have their own.
        var segments: [TripItemsAPI.SegmentRequest]?
        if hasLegs {
            guard let requests = legRequests(missingStartMessage: missingStartMessage) else { return nil }
            segments = requests
        } else {
            guard let startsAt else {
                fail(missingStartMessage)
                return nil
            }
            // Validate ordering on instants, not wall clocks, so cross-zone items are allowed.
            if let endsAt,
               // An end without a zone is taken to be in the start's zone, just for this check.
               Self.instant(of: endsAt, in: endZone ?? startZone ?? .gmt) < Self.instant(of: startsAt, in: startZone ?? .gmt) {
                fail("End time can't be before the start time.")
                return nil
            }
        }
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
        // Left out alongside legs, whose span the server takes as the item's.
        let span = segments == nil
        let startWall = span ? startsAt.map(Self.naiveString(from:)) : nil
        let endWall = span ? endsAt.map(Self.naiveString(from:)) : nil
        let startZoneId = span ? startZone?.identifier : nil
        let endZoneId = span && endsAt != nil ? endZone?.identifier : nil
        let participants = participantsToSave(currentUserId: currentUserId)
        // Sent only when ticked, so saves work on servers that don't take it.
        let notify: Bool? = canNotifyMembers(currentUserId: currentUserId) && notifyMembers ? true : nil

        let body = TripItemsAPI.CreateRequest(
            kind: kind,
            visibility: visibility,
            title: titleToSave,
            notes: resolvedNotes,
            startsAt: startWall,
            startTimezone: startZoneId,
            endsAt: endWall,
            endTimezone: endZoneId,
            placeId: span ? startPlace?.id : nil,
            endPlaceId: nil,
            segments: segments,
            lodging: lodgingToSave,
            participants: participants,
            notifyMembers: notify
        )
        // On an edit, place ids are omitted when nil, so not touching the place search
        // leaves the existing places unchanged; same for participants when the member
        // selection didn't change. A `titleOrPlace` kind sends both, nulls included,
        // so whichever it has replaces the other.
        let endpoint = if let item {
            TripItemsAPI.update(tripId: tripId, itemId: item.id, TripItemsAPI.UpdateRequest(body, nullsTitleAndPlace: titleOrPlace, sendsLodging: lodgingChanged))
        } else {
            TripItemsAPI.create(tripId: tripId, body)
        }
        do {
            return try await api.send(endpoint, as: TripItem.self)
        } catch {
            fail(error.localizedDescription)
            return nil
        }
    }

    // MARK: - Lodging details

    /// The stay's details with the form's property type, keeping whatever else the
    /// server has (room, guests, phone, …: an imported booking fills them in), since
    /// a PATCH replaces them whole. Nil for other kinds, and when nothing is known.
    var lodgingToSave: LodgingDetails? {
        guard kind == .lodging else { return nil }
        var details = item?.lodging ?? LodgingDetails()
        details.propertyType = propertyType
        return details.isEmpty ? nil : details
    }

    /// The rooms row's summary: who and how much the booking is for ("1 guest ·
    /// 1 room"), else the room type, else "No details".
    var roomSummary: String {
        let lodging = item?.lodging
        let roomType = lodging?.roomType.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        return lodging?.occupancyText ?? roomType ?? "No details"
    }

    /// Whether an edit changes the stay's details, so they're sent (a nil one as
    /// `null`, clearing them). Untouched, they're left out and stay as stored.
    var lodgingChanged: Bool {
        kind == .lodging && propertyType != item?.lodging?.propertyType
    }

    /// Every leg as sent, or nil (with `errorMessage` set) when one has no departure
    /// or arrives before it departs. With one leg, the messages don't number it.
    private func legRequests(missingStartMessage: String) -> [TripItemsAPI.SegmentRequest]? {
        var requests: [TripItemsAPI.SegmentRequest] = []
        for (index, leg) in legs.enumerated() {
            let segment = legs.count > 1 ? "segment \(index + 1)" : nil
            guard let request = leg.request else {
                fail(segment.map { "Add a departure time for \($0)." } ?? missingStartMessage)
                return nil
            }
            if leg.endsBeforeStart {
                fail(segment.map { "The arrival for \($0) can't be before its departure." }
                    ?? "End time can't be before the start time.")
                return nil
            }
            requests.append(request)
        }
        return requests
    }

    /// Deletes the item being edited, returning whether it worked (with
    /// `errorMessage` set when it didn't).
    func delete() async -> Bool {
        guard let item else { return false }
        errorMessage = nil
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await api.send(TripItemsAPI.delete(tripId: tripId, itemId: item.id))
            return true
        } catch {
            fail(error.localizedDescription)
            return false
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        errorScrollTrigger += 1
    }

    /// Fills the location fields with the place names from Google when editing. The
    /// backend enriches its own place name asynchronously, so `item.place?.name` is
    /// often still null here; Google's copy is reliably available. Only fills a field
    /// left empty by the backend, and leaves it untouched on failure. Safe against
    /// re-triggering a search: the fields aren't focused when this runs.
    func prefillPlaceNames() async {
        if !hasLegs, startPlaceText.isEmpty, let name = await Self.googleName(of: item?.place) {
            startPlaceText = name
        }
        for leg in legs {
            if leg.startPlaceText.isEmpty, let name = await Self.googleName(of: leg.startPlace) {
                leg.startPlaceText = name
            }
            if leg.endPlaceText.isEmpty, let name = await Self.googleName(of: leg.endPlace) {
                leg.endPlaceText = name
            }
        }
    }

    private static func googleName(of place: Place?) async -> String? {
        guard let gid = place?.googlePlaceId else { return nil }
        return try? await GooglePlacesClient.shared.placeDetails(placeId: gid).name
    }

    // MARK: - Wall-clock helpers
    //
    // The pickers hold wall clocks on a neutral canvas: the device zone. Reading or
    // writing the wall-clock components in that same zone leaves the printed numbers
    // untouched regardless of which zone the item is actually in.

    /// A formatter producing naive ISO 8601 (no offset) from a canvas date.
    private static let naiveFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter
    }()

    private static let canvasComponents: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]

    /// Naive wall clock (no offset) for a canvas date, e.g. "2026-04-08T16:00:00".
    static func naiveString(from canvasDate: Date) -> String {
        naiveFormatter.string(from: canvasDate)
    }

    /// A new item's default canvas start: `day`'s calendar date at 12:00 PM. Returns
    /// nil when no day is given, so callers can fall back to now.
    private static func canvasStart(onDay day: Date?, hour: Int) -> Date? {
        guard let day else { return nil }
        var canvas = Calendar(identifier: .gregorian)
        canvas.timeZone = .current
        var parts = canvas.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = 0
        return canvas.date(from: parts)
    }

    /// The hour a new item starts at on its day: check-in time for a stay, else noon.
    private static func defaultStartHour(for kind: TripItemKind) -> Int {
        kind == .lodging ? 15 : 12
    }

    /// The hour an empty end opens on in the picker: check-out time for a stay. Nil
    /// opens on an hour after the start.
    var defaultEndHour: Int? {
        kind == .lodging ? 11 : nil
    }

    /// Minute step of the start/end time pickers.
    private static let minuteInterval = 15

    /// `date` rounded to the nearest `minuteInterval` mark, so a default value matches
    /// what the picker displays.
    private static func roundedToMinuteInterval(_ date: Date) -> Date {
        let step = TimeInterval(minuteInterval * 60)
        return Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / step).rounded() * step)
    }

    /// Places an item's wall clock (its instant read in `zone`) onto the device-zone
    /// canvas, so a picker bound to the result shows the same numbers.
    static func wallClock(of instant: Date?, in zone: TimeZone?) -> Date? {
        guard let instant, let zone else { return nil }
        var source = Calendar(identifier: .gregorian)
        source.timeZone = zone
        let components = source.dateComponents(canvasComponents, from: instant)
        var canvas = Calendar(identifier: .gregorian)
        canvas.timeZone = .current
        return canvas.date(from: components)
    }

    /// The true instant for a canvas wall clock reinterpreted in `zone`.
    static func instant(of canvasDate: Date, in zone: TimeZone) -> Date {
        var canvas = Calendar(identifier: .gregorian)
        canvas.timeZone = .current
        let components = canvas.dateComponents(canvasComponents, from: canvasDate)
        var target = Calendar(identifier: .gregorian)
        target.timeZone = zone
        return target.date(from: components) ?? canvasDate
    }
}
