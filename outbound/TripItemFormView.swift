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

    /// The trip's first through last day, shown in the date popup's calendar.
    private let tripDates: ClosedRange<Date>?

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
    /// What people who aren't going see of the item.
    @State private var visibility: TripItemVisibility
    /// Ids of the trip members this item is for, toggled in the popup. Nil until
    /// seeded on appear, once the signed-in user is known.
    @State private var selectedMemberIds: Set<String>?
    /// The selection the item was opened with, so an edit only re-sends who's in when
    /// it changed.
    @State private var originalMemberIds: Set<String>?
    @State private var showingMemberPicker = false
    /// Which date row's popup is open, if any.
    @State private var editingTimeField: TimeField?
    @State private var title: String
    /// The start wall clock; nil once cleared, which blocks saving (a start is required).
    @State private var startsAt: Date?
    /// The end wall clock; nil means the item has no end time.
    @State private var endsAt: Date?
    /// The start zone, when one is known (the item's, a picked place's, or the trip's
    /// default). nil shows no zone and saves the item without one.
    @State private var startZone: TimeZone?
    /// The end zone; `nil` means "follow the start zone" until the user or a place sets it.
    @State private var endZone: TimeZone?
    @State private var notes: String
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
    private var startLabel: String {
        switch kind {
        case .lodging: "Check-in"
        case .transit: "Departs"
        case .activity: "Starts"
        }
    }
    private var endLabel: String {
        switch kind {
        case .lodging: "Check-out"
        case .transit: "Arrives"
        case .activity: "Ends"
        }
    }
    /// Shown when saving without a start, which the API requires.
    private var missingStartMessage: String {
        switch kind {
        case .lodging: "Add a check-in time."
        case .transit: "Add a departure time."
        case .activity: "Add a start time."
        }
    }

    /// Leads the date popup's date line, e.g. "Starts at" or "Departs at".
    private func popupTitle(for field: TimeField) -> String {
        switch (kind, field) {
        case (.lodging, .start): "Check-in at"
        case (.lodging, .end): "Check-out at"
        case (.transit, .start): "Departs at"
        case (.transit, .end): "Arrives at"
        case (.activity, .start): "Starts at"
        case (.activity, .end): "Ends at"
        }
    }

    /// The zone actually used for the end: an explicit choice, else the start zone.
    private var effectiveEndZone: TimeZone? { endZone ?? startZone }

    init(tripId: String, members: [TripMember] = [], tripDates: ClosedRange<Date>? = nil, item: TripItem? = nil, defaultZone: TimeZone? = nil, defaultDate: Date? = nil, defaultKind: TripItemKind = .activity, onSaved: @escaping (TripItem) -> Void = { _ in }, onDeleted: @escaping () -> Void = {}) {
        self.tripId = tripId
        self.members = members
        self.tripDates = tripDates
        self.item = item
        self.defaultZone = defaultZone
        self.defaultDate = defaultDate
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        _kind = State(initialValue: item?.kind ?? defaultKind)
        _visibility = State(initialValue: item?.visibility ?? .open)
        _title = State(initialValue: item?.title ?? "")
        // Prefill the location fields with the existing place names (if the backend has
        // enriched them), leaving `startPlace`/`endPlace` nil so an untouched edit keeps
        // the current places. Names that are still null get filled from Google on appear.
        _startPlaceText = State(initialValue: item?.place?.name ?? "")
        _endPlaceText = State(initialValue: item?.endPlace?.name ?? "")
        _notes = State(initialValue: item?.notes ?? "")
        // Load the item's wall clock onto the device-zone canvas (so the rows show
        // the same numbers), or for a new item start on the day being viewed at the
        // current time-of-day (falling back to "now" when no day was supplied).
        // `startsAtLocal` is a floating UTC date, so reading it in UTC gives the wall clock.
        let start = Self.wallClock(of: item?.startsAtLocal, in: .gmt)
            ?? Self.canvasStart(onDay: defaultDate)
            ?? Self.roundedToMinuteInterval(Date())
        _startsAt = State(initialValue: start)
        _endsAt = State(initialValue: Self.wallClock(of: item?.endsAtLocal, in: .gmt))
        _startZone = State(initialValue: item == nil ? defaultZone : item?.startTimezone)
        _endZone = State(initialValue: item?.endTimezone)
        // SwiftUI can't color segmented picker labels, so set them on the underlying
        // UISegmentedControl: light labels to read on the dark gray sheet, dark on the
        // white selected pill. This is app-wide, but these are the only segmented pickers.
        let segments = UISegmentedControl.appearance()
        segments.setTitleTextAttributes([.foregroundColor: UIColor(Color.appForeground)], for: .normal)
        segments.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sheetBackground.ignoresSafeArea()
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

                        // Who it's for and who else sees it read as one group, so the
                        // picker sits tight under the members row with no label of its own.
                        VStack(alignment: .leading, spacing: 8) {
                            membersRow
                            Picker("Visibility", selection: $visibility) {
                                ForEach(TripItemVisibility.allCases) { visibility in
                                    Text(visibility.label).tag(visibility)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(visibility.explanation)
                                .font(.caption)
                                .foregroundStyle(Color.appForeground.opacity(0.7))
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
                            VStack(spacing: 6) {
                                timeRow(title: startLabel, placeholder: "Add start", date: $startsAt, field: .start)
                                if startsAt != nil, let startZone { zoneNote(startZone) }
                            }
                            VStack(spacing: 6) {
                                timeRow(title: endLabel, placeholder: "Add end", date: $endsAt, field: .end)
                                if endsAt != nil, let effectiveEndZone { zoneNote(effectiveEndZone) }
                            }
                        }

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
            .toolbarBackground(Color.sheetBackground, for: .navigationBar)
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
        .overlay { timePickerPopup }
        .appTheme()
        .onAppear(perform: seedSelectedMembers)
    }

    private var memberSelection: ItemMemberSelection {
        ItemMemberSelection(members: members, currentUserId: auth.currentUser?.id)
    }

    private func seedSelectedMembers() {
        guard selectedMemberIds == nil else { return }
        let seeded = memberSelection.initialSelection(for: item)
        selectedMemberIds = seeded
        originalMemberIds = seeded
    }

    /// The `participants` to send: exactly who's selected. Nil leaves them to the
    /// server — on an edit when the selection is unchanged, and when there's no roster
    /// to pick from (a new item is then just for its creator).
    private var participantsToSave: [TripItemsAPI.ParticipantRequest]? {
        guard !members.isEmpty, let selected = selectedMemberIds else { return nil }
        if item != nil, selected == originalMemberIds { return nil }
        return memberSelection.participants(for: selected)
    }

    /// A one-line row summarizing who the item is for; tapping it opens the picker.
    private var membersRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { showingMemberPicker = true }
        } label: {
            HStack {
                Text("Members")
                Spacer()
                Text(memberSelection.summary(of: selectedMemberIds ?? []))
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
            popup(onClose: closeMemberPicker) {
                ItemMembersPopup(
                    members: members,
                    currentUserId: auth.currentUser?.id,
                    selectedIds: Binding { selectedMemberIds ?? [] } set: { selectedMemberIds = $0 },
                    onClose: closeMemberPicker
                )
            }
        }
    }

    private func openTimePicker(_ field: TimeField) {
        withAnimation(.snappy(duration: 0.25)) { editingTimeField = field }
    }

    private func closeTimePicker() {
        withAnimation(.snappy(duration: 0.2)) { editingTimeField = nil }
    }

    /// The open date popup for the tapped row over a dimmed form; tapping outside closes it.
    @ViewBuilder
    private var timePickerPopup: some View {
        if let editingTimeField {
            popup(onClose: closeTimePicker) {
                DateTimePopup(
                    title: popupTitle(for: editingTimeField),
                    tripDates: tripDates,
                    date: editingTimeField == .start ? $startsAt : $endsAt,
                    onClose: closeTimePicker
                )
            }
        }
    }

    /// A popup card centered over a dimmed backdrop; tapping the backdrop closes it.
    private func popup<Card: View>(onClose: @escaping () -> Void, @ViewBuilder card: () -> Card) -> some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
                .transition(.opacity)
            card()
                .transition(.scale(scale: 0.94).combined(with: .opacity))
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

    /// A boxed row like the members row: the label on the left, the date/time (or a
    /// placeholder) on the right, and a clear button once there's a value. Tapping the
    /// row opens its date popup.
    private func timeRow(title: String, placeholder: String, date: Binding<Date?>, field: TimeField) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Spacer()
            if let value = date.wrappedValue {
                Text(value, format: .dateTime.month().day().hour().minute())
                    .foregroundStyle(Color.appForeground.opacity(0.75))
                Button {
                    withAnimation { date.wrappedValue = nil }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appForeground.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear \(title)")
            } else {
                Text(placeholder)
                    .foregroundStyle(Color.appForeground.opacity(0.45))
            }
        }
        .padding(14)
        .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
        // A tap gesture rather than a Button, so the clear button inside stays its own
        // target instead of nesting a button in a button.
        .contentShape(Rectangle())
        .onTapGesture { openTimePicker(field) }
        .accessibilityAddTraits(.isButton)
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
        .padding(.horizontal, 4)
    }

    /// A friendly label for a zone, e.g. "Tokyo (JST)".
    private func zoneLabel(_ zone: TimeZone) -> String {
        let city = (zone.identifier.split(separator: "/").last.map(String.init) ?? zone.identifier)
            .replacingOccurrences(of: "_", with: " ")
        return "\(city) (\(WallClock.zoneAbbreviation(zone, at: startsAt ?? Date())))"
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        guard let startsAt else {
            errorMessage = missingStartMessage
            errorScrollTrigger += 1
            return
        }
        // Validate ordering on instants, not wall clocks, so cross-zone legs are allowed.
        if let endsAt,
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
                let endWall = endsAt.map(Self.naiveString(from:))
                let startZoneId = startZone?.identifier
                let endZoneId = endsAt != nil ? effectiveEndZone?.identifier : nil
                // End place only applies to transit (origin → destination).
                let endPlaceId = kind == .transit ? endPlace?.id : nil

                let endpoint: Endpoint
                if let item {
                    // Place ids are omitted when nil, so an edit that doesn't touch the
                    // place search leaves the existing places unchanged; same for
                    // participants when the member selection didn't change.
                    let body = TripItemsAPI.UpdateRequest(
                        kind: kind,
                        visibility: visibility,
                        title: trimmedTitle,
                        notes: resolvedNotes,
                        startsAt: startWall,
                        startTimezone: startZoneId,
                        endsAt: endWall,
                        endTimezone: endZoneId,
                        placeId: startPlace?.id,
                        endPlaceId: endPlaceId,
                        participants: participantsToSave
                    )
                    endpoint = TripItemsAPI.update(tripId: tripId, itemId: item.id, body)
                } else {
                    let body = TripItemsAPI.CreateRequest(
                        kind: kind,
                        visibility: visibility,
                        title: trimmedTitle,
                        notes: resolvedNotes,
                        startsAt: startWall,
                        startTimezone: startZoneId,
                        endsAt: endWall,
                        endTimezone: endZoneId,
                        placeId: startPlace?.id,
                        endPlaceId: endPlaceId,
                        participants: participantsToSave
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
    TripItemFormView(tripId: "sample", tripDates: .now ... .now.addingTimeInterval(3 * 86_400))
        .environment(AuthStore())
}
