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

    /// Everyone on the trip, offered in the "who's going" popup.
    private let members: [TripMember]

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth

    /// The item being edited, or `nil` when creating a new one.
    private let item: TripItem?

    /// The zone a new item's start defaults to (from the last item chronologically).
    private let defaultZone: TimeZone?

    /// The calendar day a new item's start defaults to (the day being viewed when add
    /// was tapped); the time-of-day defaults to now. `nil` falls back to today.
    private let defaultDate: Date?

    /// Called with the created or updated item after a successful save.
    var onSaved: (TripItem) -> Void

    /// Called after the item being edited is deleted.
    var onDeleted: () -> Void

    @State private var kind: TripItemKind
    /// Ids of the trip members this item is for, toggled in the popup. Nil until
    /// seeded on appear, once the signed-in user is known.
    @State private var selectedMemberIds: Set<String>?
    /// The selection the item was opened with, so an edit only re-sends who's in when
    /// it changed.
    @State private var originalMemberIds: Set<String>?
    @State private var showingMemberPicker = false
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
    /// Showing the confirmation before an existing item is deleted.
    @State private var confirmingDelete = false
    @State private var isDeleting = false
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

    init(tripId: String, members: [TripMember] = [], item: TripItem? = nil, defaultZone: TimeZone? = nil, defaultDate: Date? = nil, defaultKind: TripItemKind = .activity, onSaved: @escaping (TripItem) -> Void = { _ in }, onDeleted: @escaping () -> Void = {}) {
        self.tripId = tripId
        self.members = members
        self.item = item
        self.defaultZone = defaultZone
        self.defaultDate = defaultDate
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _kind = State(initialValue: item?.kind ?? defaultKind)
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
        // (TripFormView) are date-only and unaffected.
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

                        membersRow

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

                        if isEditing {
                            deleteButton
                        }
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
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isDeleting)
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
        .overlay { memberPickerPopup }
        .appTheme()
        .onAppear(perform: seedSelectedMembers)
    }

    /// The signed-in user's row on this trip, if they're on it.
    private var currentMember: TripMember? {
        members.first { $0.user?.id != nil && $0.user?.id == auth.currentUser?.id }
    }

    /// The member a personal item belongs to: its creator, or the signed-in user for a
    /// new item. The server always keeps them in, so their row can't be unchecked.
    private var ownerMember: TripMember? {
        guard let ownerId = item.map({ $0.createdBy?.id }) ?? auth.currentUser?.id else { return nil }
        return members.first { $0.user?.id == ownerId }
    }

    /// A new or group item starts with everyone; a personal one with whoever's in.
    private func seedSelectedMembers() {
        guard selectedMemberIds == nil else { return }
        let seeded: Set<String>
        if let item, item.scope == .personal {
            let joined = item.participants.filter { $0.status != .declined }.map(\.member.id)
            seeded = Set(joined + [ownerMember?.id].compactMap { $0 })
        } else {
            seeded = Set(members.map(\.id))
        }
        selectedMemberIds = seeded
        originalMemberIds = seeded
    }

    /// How the selection is saved. Everyone, picked by an organizer, is a group item
    /// (only organizers may post those); any other pick is a personal item for the
    /// chosen members. On an edit, nil when the selection is unchanged, so the item's
    /// scope and RSVPs are left alone.
    private var membersToSave: (scope: TripItemScope, participants: [TripItemsAPI.ParticipantRequest]?)? {
        // Without a roster (a backend that doesn't send members) keep the old default.
        guard !members.isEmpty, let selected = selectedMemberIds else {
            return item == nil ? (.group, nil) : nil
        }
        if item != nil, selected == originalMemberIds { return nil }
        if selected.count == members.count, currentMember?.role == .organizer {
            return (.group, nil)
        }
        // Roster order, so the request is stable.
        let going = members.filter { selected.contains($0.id) }
            .map { TripItemsAPI.ParticipantRequest(memberId: $0.id, status: .going) }
        return (.personal, going)
    }

    /// "Everyone", "Just you", "You and 2 others", or a head count without you.
    private var membersSummary: String {
        let selected = selectedMemberIds ?? []
        let includesYou = currentMember.map { selected.contains($0.id) } ?? false
        let others = selected.count - (includesYou ? 1 : 0)
        // A trip without a loaded roster only has the user creating the item.
        if members.isEmpty { return "Just you" }
        if selected.isEmpty { return "No one" }
        if selected.count == members.count && members.count > 1 { return "Everyone" }
        switch (includesYou, others) {
        case (true, 0): return "Just you"
        case (true, 1): return "You and 1 other"
        case (true, _): return "You and \(others) others"
        case (false, 1): return "1 person"
        case (false, _): return "\(others) people"
        }
    }

    /// A one-line row summarizing who the item is for; tapping it opens the picker.
    private var membersRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { showingMemberPicker = true }
        } label: {
            HStack {
                Text("Members")
                Spacer()
                Text(membersSummary)
                    .foregroundStyle(Color.appForeground.opacity(0.75))
            }
            .padding(14)
            .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func closeMemberPicker() {
        withAnimation(.snappy(duration: 0.2)) { showingMemberPicker = false }
    }

    /// The open member picker over a dimmed form; tapping outside closes it.
    @ViewBuilder
    private var memberPickerPopup: some View {
        if showingMemberPicker {
            ZStack {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .onTapGesture { closeMemberPicker() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                ItemMembersPopup(
                    members: members,
                    currentUserId: auth.currentUser?.id,
                    lockedId: ownerMember?.id,
                    selectedIds: Binding { selectedMemberIds ?? [] } set: { selectedMemberIds = $0 },
                    onClose: closeMemberPicker
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
    }

    /// Deletes an existing item, after a confirmation since it can't be undone.
    private var deleteButton: some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Group {
                if isDeleting {
                    ProgressView().tint(.white)
                } else {
                    Label("Delete Item", systemImage: "trash")
                }
            }
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(14)
                // The error banner's red: plain red text is hard to read on terracotta.
                .background(Color.red.opacity(0.75), in: .rect(cornerRadius: appFieldCornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isDeleting)
        .padding(.top, 12)
        .confirmationDialog("Delete this item?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete)
        } message: {
            Text("This can't be undone.")
        }
    }

    private func delete() {
        guard let item else { return }
        errorMessage = nil
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await api.send(TripItemsAPI.delete(tripId: tripId, itemId: item.id))
                onDeleted()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                errorScrollTrigger += 1
            }
        }
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
        return "\(city) (\(WallClock.zoneAbbreviation(zone, at: startsAt)))"
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
                    // Place ids are omitted when nil, so an edit that doesn't touch the
                    // place search leaves the existing places unchanged; same for scope
                    // and participants when the member selection didn't change.
                    let members = membersToSave
                    let body = TripItemsAPI.UpdateRequest(
                        kind: kind,
                        title: trimmedTitle,
                        notes: resolvedNotes,
                        startsAt: startWall,
                        startTimezone: startZoneId,
                        endsAt: endWall,
                        endTimezone: endZoneId,
                        placeId: startPlace?.id,
                        endPlaceId: endPlaceId,
                        scope: members?.scope,
                        participants: members?.participants
                    )
                    endpoint = TripItemsAPI.update(tripId: tripId, itemId: item.id, body)
                } else {
                    let members = membersToSave
                    let body = TripItemsAPI.CreateRequest(
                        kind: kind,
                        scope: members?.scope ?? .group,
                        title: trimmedTitle,
                        notes: resolvedNotes,
                        startsAt: startWall,
                        startTimezone: startZoneId,
                        endsAt: endWall,
                        endTimezone: endZoneId,
                        placeId: startPlace?.id,
                        endPlaceId: endPlaceId,
                        participants: members?.participants
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
        .environment(AuthStore())
}
