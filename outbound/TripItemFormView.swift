//
//  TripItemFormView.swift
//  outbound
//

import SwiftUI

/// Modal for manually adding or editing a trip item. Collects a kind, title,
/// start/end times with their time zones, and optional notes.
///
/// Times are entered as wall clocks on a neutral canvas (the device zone), so the
/// numbers the user sees are what gets sent as the naive `starts_at`/`ends_at`.
/// The zone is chosen separately, so changing it keeps the wall time and only moves
/// the underlying instant — matching the server's "right time, wrong zone" fix.
///
/// Pass an existing `item` to edit it; omit it to create a new one. `defaultZone`
/// is the zone a new item's start defaults to — the zone the traveler ends up in
/// after the chronologically last item, so a new item continues from there.
struct TripItemFormView: View {
    let tripId: String

    @Environment(\.dismiss) private var dismiss

    /// The item being edited, or `nil` when creating a new one.
    private let item: TripItem?

    /// The zone a new item's start defaults to (from the last item chronologically).
    private let defaultZone: TimeZone?

    /// The calendar day a new item's start defaults to (the day being viewed when add
    /// was tapped); the time-of-day defaults to now. `nil` falls back to today.
    private let defaultDate: Date?

    /// Called with the created or updated item after a successful save.
    var onSaved: (TripItem) -> Void

    @State private var kind: TripItemKind
    @State private var scope: TripItemScope
    @State private var title: String
    @State private var startsAt: Date
    @State private var hasEndTime: Bool
    @State private var endsAt: Date
    /// The start zone, when one is known (the item's, a picked place's, or the trip's
    /// default). nil shows no zone and saves the item without one.
    @State private var startZone: TimeZone?
    /// The end zone; `nil` means "follow the start zone" until the user or a place sets it.
    @State private var endZone: TimeZone?
    @State private var notes: String
    @State private var activeField: TimeField?
    @State private var isSaving = false
    @State private var errorMessage: String?
    /// Bumped on every failed save so the error scrolls into view even when unchanged.
    @State private var errorScrollTrigger = 0

    /// The place for this item, picked via the location search → sent as `place_id`.
    @State private var startPlace: Place?
    /// The text the location field searches on, kept separate from the item's title.
    @State private var startPlaceText: String
    /// The start place's time zone from Google, used to drive `startZone` when picked.
    @State private var startPlaceZone: TimeZone?
    /// The destination place for transit items → sent as `end_place_id`. The text it
    /// searches on is kept separately since it isn't the item's title.
    @State private var endPlace: Place?
    @State private var endPlaceText: String
    /// The destination place's time zone from Google, used to drive `endZone`.
    @State private var endPlaceZone: TimeZone?

    private enum TimeField { case start, end }

    /// Scroll target for the error banner, so a failed save brings it into view.
    private static let errorAnchor = "error"

    private let api = APIClient.shared

    private var isEditing: Bool { item != nil }
    private var startLabel: String { kind == .lodging ? "Check-in" : "Starts" }
    private var endLabel: String { kind == .lodging ? "Check-out" : "Ends" }

    /// The zone actually used for the end: an explicit choice, else the start zone.
    private var effectiveEndZone: TimeZone? { endZone ?? startZone }

    init(tripId: String, item: TripItem? = nil, defaultZone: TimeZone? = nil, defaultDate: Date? = nil, onSaved: @escaping (TripItem) -> Void = { _ in }) {
        self.tripId = tripId
        self.item = item
        self.defaultZone = defaultZone
        self.defaultDate = defaultDate
        self.onSaved = onSaved
        _kind = State(initialValue: item?.kind ?? .activity)
        _scope = State(initialValue: item?.scope ?? .group)
        _title = State(initialValue: item?.title ?? "")
        // Prefill the location fields with the existing place names (if the backend has
        // enriched them), leaving `startPlace`/`endPlace` nil so an untouched edit keeps
        // the current places. Names that are still null get filled from Google on appear.
        _startPlaceText = State(initialValue: item?.place?.name ?? "")
        _endPlaceText = State(initialValue: item?.endPlace?.name ?? "")
        _hasEndTime = State(initialValue: item?.endsAtLocal != nil)
        _notes = State(initialValue: item?.notes ?? "")
        // Load the item's wall clock onto the device-zone canvas (so the picker shows
        // the same numbers), or for a new item start on the day being viewed at the
        // current time-of-day (falling back to "now" when no day was supplied).
        // `startsAtLocal` is a floating UTC date, so reading it in UTC gives the wall clock.
        let start = Self.wallClock(of: item?.startsAtLocal, in: .gmt)
            ?? Self.canvasStart(onDay: defaultDate)
            ?? Self.roundedToMinuteInterval(Date())
        _startsAt = State(initialValue: start)
        _endsAt = State(initialValue: Self.wallClock(of: item?.endsAtLocal, in: .gmt) ?? start)
        _startZone = State(initialValue: item == nil ? defaultZone : item?.startTimezone)
        _endZone = State(initialValue: item?.endTimezone)
        // SwiftUI's DatePicker has no minute-interval option, so set it on the
        // underlying UIDatePicker. This is app-wide, but the only other pickers
        // (AddTripView) are date-only and unaffected.
        UIDatePicker.appearance().minuteInterval = Self.minuteInterval
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Type")
                                .font(.subheadline)
                                .foregroundStyle(Color.appForeground.opacity(0.8))
                            Picker("Type", selection: $kind) {
                                ForEach(TripItemKind.allCases) { kind in
                                    Text(kind.label).tag(kind)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Scope")
                                .font(.subheadline)
                                .foregroundStyle(Color.appForeground.opacity(0.8))
                            Picker("Scope", selection: $scope) {
                                ForEach(TripItemScope.allCases) { scope in
                                    Text(scope.label).tag(scope)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        TextField("Title", text: $title)
                            .textInputAutocapitalization(.words)
                            .appField()

                        VStack(alignment: .leading, spacing: 8) {
                            Text(kind == .transit ? "Origin" : "Location")
                                .font(.subheadline)
                                .foregroundStyle(Color.appForeground.opacity(0.8))
                            PlaceSearchField(
                                placeholder: kind == .transit ? "Search origin" : "Search a place",
                                text: $startPlaceText,
                                resolvedPlace: $startPlace,
                                resolvedTimeZone: $startPlaceZone
                            )
                        }

                        if kind == .transit {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Destination")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.appForeground.opacity(0.8))
                                PlaceSearchField(
                                    placeholder: "Search destination",
                                    text: $endPlaceText,
                                    resolvedPlace: $endPlace,
                                    resolvedTimeZone: $endPlaceZone
                                )
                            }
                        }

                        VStack(spacing: 8) {
                            timeRow(title: startLabel, date: startsAt, field: .start)
                            if activeField == .start {
                                DatePicker("", selection: $startsAt, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                                    .onChange(of: startsAt) { _, newValue in
                                        if endsAt < newValue { endsAt = newValue }
                                    }
                            }

                            if let startZone { zoneNote(startZone) }

                            Divider().overlay(Color.appForeground.opacity(0.2))

                            // The whole row flips the switch. On iOS 26 a bare Toggle in this
                            // scrolling sheet ignores taps (only a drag moves it), so the row
                            // handles the tap and the switch is just the indicator.
                            Button {
                                withAnimation { hasEndTime.toggle() }
                            } label: {
                                Toggle(kind == .lodging ? "Set check-out time" : "Set end time", isOn: .constant(hasEndTime))
                                    .allowsHitTesting(false)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if hasEndTime {
                                timeRow(title: endLabel, date: endsAt, field: .end)
                                if activeField == .end {
                                    // No wall-clock range: a westbound leg can land at an
                                    // earlier clock time than it departs. Ordering is checked
                                    // on instants in `save()`.
                                    DatePicker("", selection: $endsAt, displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.graphical)
                                        .labelsHidden()
                                }
                                if let effectiveEndZone { zoneNote(effectiveEndZone) }
                            }
                        }
                        .padding(14)
                        .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))

                        // Sits right under the times (the usual cause) rather than at the
                        // bottom, where the keyboard hides it and Save looks unresponsive.
                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.red.opacity(0.75), in: .rect(cornerRadius: appFieldCornerRadius))
                                .id(Self.errorAnchor)
                        }

                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .appField()
                    }
                    .padding(24)
                }
                .onChange(of: errorScrollTrigger) {
                    withAnimation { proxy.scrollTo(Self.errorAnchor, anchor: .center) }
                }
                }
            }
            .foregroundStyle(Color.appForeground)
            .navigationTitle(isEditing ? "Edit Item" : "New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(isEditing ? "Save" : "Add", action: save)
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
            // A chosen place is authoritative for the zone, so follow it when resolved.
            .onChange(of: startPlaceZone) { _, zone in
                if let zone { startZone = zone }
            }
            .onChange(of: endPlaceZone) { _, zone in
                if let zone { endZone = zone }
            }
            .task { await prefillPlaceNames() }
        }
        .appTheme()
    }

    /// Fills the location fields with the place names from Google when editing. The
    /// backend enriches its own place name asynchronously, so `item.place?.name` is
    /// often still null here; Google's copy is reliably available. Only fills a field
    /// left empty by the backend, and leaves it untouched on failure. Safe against
    /// re-triggering a search: the fields aren't focused when this runs.
    private func prefillPlaceNames() async {
        if startPlaceText.isEmpty, let gid = item?.place?.googlePlaceId,
           let name = try? await GooglePlacesClient.shared.placeDetails(placeId: gid).name {
            startPlaceText = name
        }
        if kind == .transit, endPlaceText.isEmpty, let gid = item?.endPlace?.googlePlaceId,
           let name = try? await GooglePlacesClient.shared.placeDetails(placeId: gid).name {
            endPlaceText = name
        }
    }

    /// A tappable row showing a date/time; tapping toggles the inline picker below it.
    private func timeRow(title: String, date: Date, field: TimeField) -> some View {
        Button {
            withAnimation { activeField = (activeField == field) ? nil : field }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(date, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(activeField == field ? Color.appAccent : Color.appForeground)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// A read-only caption noting the time zone a time is in, sitting under its row.
    /// Zone selection is driven by the picked place for now; manual choice comes later.
    private func zoneNote(_ zone: TimeZone) -> some View {
        HStack {
            Spacer()
            Text(zoneLabel(zone))
                .font(.caption)
                .foregroundStyle(Color.appForeground.opacity(0.6))
        }
    }

    /// A friendly label for a zone, e.g. "Tokyo (JST)".
    private func zoneLabel(_ zone: TimeZone) -> String {
        let city = (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
        return "\(city) (\(TripItem.zoneAbbreviation(zone, at: startsAt)))"
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        // Validate ordering on instants, not wall clocks, so cross-zone legs are allowed.
        if hasEndTime,
           Self.instant(of: endsAt, in: effectiveEndZone ?? .gmt) < Self.instant(of: startsAt, in: startZone ?? .gmt) {
            errorMessage = "End time can't be before the start time."
            errorScrollTrigger += 1
            return
        }
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedNotes = trimmedNotes.isEmpty ? nil : trimmedNotes
                let startWall = Self.naiveString(from: startsAt)
                let endWall = hasEndTime ? Self.naiveString(from: endsAt) : nil
                let startZoneId = startZone?.identifier
                let endZoneId = hasEndTime ? effectiveEndZone?.identifier : nil
                // End place only applies to transit (origin → destination).
                let endPlaceId = kind == .transit ? endPlace?.id : nil

                let endpoint: Endpoint
                if let item {
                    // The update endpoint has no `scope` field, so it isn't sent here.
                    // Place ids are omitted when nil, so an edit that doesn't touch the
                    // place search leaves the existing places unchanged.
                    let body = TripItemsAPI.UpdateRequest(
                        kind: kind,
                        title: trimmedTitle,
                        notes: resolvedNotes,
                        startsAt: startWall,
                        startTimezone: startZoneId,
                        endsAt: endWall,
                        endTimezone: endZoneId,
                        placeId: startPlace?.id,
                        endPlaceId: endPlaceId
                    )
                    endpoint = TripItemsAPI.update(tripId: tripId, itemId: item.id, body)
                } else {
                    let body = TripItemsAPI.CreateRequest(
                        kind: kind,
                        scope: scope,
                        title: trimmedTitle,
                        notes: resolvedNotes,
                        startsAt: startWall,
                        startTimezone: startZoneId,
                        endsAt: endWall,
                        endTimezone: endZoneId,
                        placeId: startPlace?.id,
                        endPlaceId: endPlaceId
                    )
                    endpoint = TripItemsAPI.create(tripId: tripId, body)
                }
                let saved = try await api.send(endpoint, as: TripItem.self)
                onSaved(saved)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                errorScrollTrigger += 1
            }
        }
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
    private static func naiveString(from canvasDate: Date) -> String {
        naiveFormatter.string(from: canvasDate)
    }

    /// A new item's default canvas start: `day`'s calendar date at 12:00 PM. Returns
    /// nil when no day is given, so callers can fall back to now.
    private static func canvasStart(onDay day: Date?) -> Date? {
        guard let day else { return nil }
        var canvas = Calendar(identifier: .gregorian)
        canvas.timeZone = .current
        var parts = canvas.dateComponents([.year, .month, .day], from: day)
        parts.hour = 12
        parts.minute = 0
        return canvas.date(from: parts)
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
    private static func wallClock(of instant: Date?, in zone: TimeZone?) -> Date? {
        guard let instant, let zone else { return nil }
        var source = Calendar(identifier: .gregorian)
        source.timeZone = zone
        let components = source.dateComponents(canvasComponents, from: instant)
        var canvas = Calendar(identifier: .gregorian)
        canvas.timeZone = .current
        return canvas.date(from: components)
    }

    /// The true instant for a canvas wall clock reinterpreted in `zone`.
    private static func instant(of canvasDate: Date, in zone: TimeZone) -> Date {
        var canvas = Calendar(identifier: .gregorian)
        canvas.timeZone = .current
        let components = canvas.dateComponents(canvasComponents, from: canvasDate)
        var target = Calendar(identifier: .gregorian)
        target.timeZone = zone
        return target.date(from: components) ?? canvasDate
    }
}

#Preview {
    TripItemFormView(tripId: "sample")
}
