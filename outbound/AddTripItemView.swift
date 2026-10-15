//
//  AddTripItemView.swift
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
/// Pass an existing `item` to edit it; omit it to create a new one. `dayTimeZones`
/// are the zones of the day being added to (the first is the default for new items).
struct AddTripItemView: View {
    let tripId: String

    @Environment(\.dismiss) private var dismiss

    /// The item being edited, or `nil` when creating a new one.
    private let item: TripItem?

    /// The zones of the day this item is being added to; the first is the default.
    private let dayTimeZones: [TimeZone]

    /// Called with the created or updated item after a successful save.
    var onSaved: (TripItem) -> Void

    @State private var kind: TripItemKind
    @State private var scope: TripItemScope
    @State private var title: String
    @State private var startsAt: Date
    @State private var hasEndTime: Bool
    @State private var endsAt: Date
    @State private var startZone: TimeZone
    /// The end zone; `nil` means "follow the start zone" until the user or a place sets it.
    @State private var endZone: TimeZone?
    @State private var notes: String
    @State private var activeField: TimeField?
    @State private var isSaving = false
    @State private var errorMessage: String?

    /// The place for this item, picked via the title search → sent as `place_id`.
    @State private var startPlace: Place?
    /// The start place's time zone from Google, used to drive `startZone` when picked.
    @State private var startPlaceZone: TimeZone?
    /// The destination place for transit items → sent as `end_place_id`. The text it
    /// searches on is kept separately since it isn't the item's title.
    @State private var endPlace: Place?
    @State private var endPlaceText = ""
    /// The destination place's time zone from Google, used to drive `endZone`.
    @State private var endPlaceZone: TimeZone?

    private enum TimeField { case start, end }

    private let api = APIClient.shared

    private var isEditing: Bool { item != nil }
    private var startLabel: String { kind == .lodging ? "Check-in" : "Starts" }
    private var endLabel: String { kind == .lodging ? "Check-out" : "Ends" }

    /// The zone actually used for the end: an explicit choice, else the start zone.
    private var effectiveEndZone: TimeZone { endZone ?? startZone }

    init(tripId: String, item: TripItem? = nil, dayTimeZones: [TimeZone] = [], onSaved: @escaping (TripItem) -> Void = { _ in }) {
        self.tripId = tripId
        self.item = item
        self.dayTimeZones = dayTimeZones
        self.onSaved = onSaved
        _kind = State(initialValue: item?.kind ?? .activity)
        _scope = State(initialValue: item?.scope ?? .group)
        _title = State(initialValue: item?.title ?? "")
        _hasEndTime = State(initialValue: item?.endsAt != nil)
        _notes = State(initialValue: item?.notes ?? "")
        // Load the item's wall clock onto the device-zone canvas (so the picker shows
        // the same numbers), or start from "now" for a new item.
        let start = Self.wallClock(of: item?.startsAt, in: item?.startTimezone) ?? Date()
        _startsAt = State(initialValue: start)
        _endsAt = State(initialValue: Self.wallClock(of: item?.endsAt, in: item?.endTimezone) ?? start)
        _startZone = State(initialValue: item?.startTimezone ?? dayTimeZones.first ?? .current)
        _endZone = State(initialValue: item?.endTimezone)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
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

                        PlaceSearchField(
                            placeholder: kind == .transit ? "Title or search origin" : "Title or search a place",
                            text: $title,
                            resolvedPlace: $startPlace,
                            resolvedTimeZone: $startPlaceZone
                        )

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

                            zoneNote(startZone)

                            Divider().overlay(Color.appForeground.opacity(0.2))

                            Toggle(kind == .lodging ? "Set check-out time" : "Set end time", isOn: $hasEndTime.animation())
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
                                zoneNote(effectiveEndZone)
                            }
                        }
                        .padding(14)
                        .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))

                        TextField("Notes (optional)", text: $notes, axis: .vertical)
                            .lineLimit(3...6)
                            .appField()

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(24)
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
        }
        .appTheme()
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
           Self.instant(of: endsAt, in: effectiveEndZone) < Self.instant(of: startsAt, in: startZone) {
            errorMessage = "End time can't be before the start time."
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
                let endZoneId = hasEndTime ? effectiveEndZone.identifier : nil
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
                        startTimezone: startZone.identifier,
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
                        startTimezone: startZone.identifier,
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
    AddTripItemView(tripId: "sample")
}
