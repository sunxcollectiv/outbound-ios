//
//  TripItemFormScaffold.swift
//  outbound
//

import SwiftUI

/// What a kind calls its start and end, e.g. a lodging's check-in and check-out.
struct TripItemTimeLabels {
    let start: String
    let end: String
    /// Shown when saving without a start, which the API requires.
    let missingStart: String
    /// Whether the date popup lets the end be left empty.
    var endIsOptional = false
    /// Whether the date popup offers setting the end as a duration after the start.
    var offersEndDurations = false
}

/// The layout every trip item form shares: who it's for and who sees it, the title
/// (left out for kinds named by their place search or by the server), the kind's own
/// place fields (`places`), the start/end times (a transit's legs show their own),
/// notes, and the pinned Save/Delete bar. The per-kind forms supply their places and
/// time labels.
struct TripItemFormScaffold<Places: View>: View {
    @Bindable var draft: TripItemDraft
    let timeLabels: TripItemTimeLabels
    /// Called with the created or updated item after a successful save.
    let onSaved: (TripItem) -> Void
    /// Called after the item being edited is deleted.
    let onDeleted: () -> Void
    @ViewBuilder let places: () -> Places

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth

    @State private var showingMemberPicker = false
    /// Which date row's popup is open, if any.
    @State private var editingTimeField: TimeField?
    /// The sheet's bottom safe area (the home indicator's strip), measured so the
    /// bottom bar can sit partway into it.
    @State private var homeIndicatorInset: CGFloat = 0

    private enum TimeField { case start, end }

    /// Scroll target for the error banner, so a failed save brings it into view.
    private static var errorAnchor: String { "error" }

    init(draft: TripItemDraft, timeLabels: TripItemTimeLabels, onSaved: @escaping (TripItem) -> Void, onDeleted: @escaping () -> Void, @ViewBuilder places: @escaping () -> Places) {
        self.draft = draft
        self.timeLabels = timeLabels
        self.onSaved = onSaved
        self.onDeleted = onDeleted
        self.places = places
        // SwiftUI can't color segmented picker labels, so set them on the underlying
        // UISegmentedControl: light labels to read on the dark gray sheet, dark on the
        // white selected pill. This is app-wide, but this is the only segmented picker.
        let segments = UISegmentedControl.appearance()
        segments.setTitleTextAttributes([.foregroundColor: UIColor(Color.appForeground)], for: .normal)
        segments.setTitleTextAttributes([.foregroundColor: UIColor.black], for: .selected)
    }

    private var currentUserId: String? { auth.currentUser?.id }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sheetBackground.ignoresSafeArea()
                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        // Who it's for and who else sees it read as one group, so the
                        // picker sits tight under the members row with no label of its own.
                        VStack(alignment: .leading, spacing: 8) {
                            membersRow
                            Picker("Visibility", selection: $draft.visibility) {
                                ForEach(TripItemVisibility.allCases) { visibility in
                                    Text(visibility.label).tag(visibility)
                                }
                            }
                            .pickerStyle(.segmented)
                            Text(draft.visibility.explanation)
                                .font(.caption)
                                .foregroundStyle(Color.appForeground.opacity(0.7))
                        }

                        if draft.hasTitleField {
                            TextField("Title", text: $draft.title)
                                .textInputAutocapitalization(.never)
                                .appField()
                        }

                        places()
                            // Above the blocks below, so floating suggestions cover them.
                            .zIndex(1)

                        // A transit's legs show their own times, within `places`.
                        if !draft.hasLegs {
                            HStack(spacing: 8) {
                                TripItemTimeBlock(title: timeLabels.start, placeholder: "Add start", date: $draft.startsAt, zone: $draft.startZone) {
                                    openTimePicker(.start)
                                }
                                TripItemTimeBlock(title: timeLabels.end, placeholder: "Add end", date: $draft.endsAt, zone: $draft.endZone) {
                                    openTimePicker(.end)
                                }
                            }
                        }

                        // Sits right under the times (the usual cause) rather than at the
                        // bottom, where the keyboard hides it and Save looks unresponsive.
                        if let errorMessage = draft.errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                                .background(Color.red.opacity(0.75), in: .rect(cornerRadius: appFieldCornerRadius))
                                .id(Self.errorAnchor)
                        }

                        TextField("Notes (optional)", text: $draft.notes, axis: .vertical)
                            .lineLimit(3...6)
                            .appField()
                    }
                    .padding(24)
                }
                .onChange(of: draft.errorScrollTrigger) {
                    withAnimation { proxy.scrollTo(Self.errorAnchor, anchor: .center) }
                }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
            .foregroundStyle(Color.appForeground)
            .navigationTitle(draft.isEditing ? "Edit \(draft.kind.label)" : "New \(draft.kind.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.sheetBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .accessibilityLabel("Close")
                    }
                }
            }
            .task { await draft.prefillPlaceNames() }
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { homeIndicatorInset = $0 }
        .overlay { memberPickerPopup }
        .overlay { timePickerPopup }
        .appTheme()
        .onAppear { draft.seedSelectedMembers(currentUserId: currentUserId) }
    }

    // MARK: - Members

    /// A one-line row summarizing who the item is for; tapping it opens the picker.
    private var membersRow: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { showingMemberPicker = true }
        } label: {
            HStack {
                Text("Members")
                Spacer()
                Text(draft.memberSelection(currentUserId: currentUserId).summary(of: draft.selectedMemberIds ?? []))
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
            DimmedPopup(onClose: closeMemberPicker) {
                ItemMembersPopup(
                    members: draft.members,
                    currentUserId: currentUserId,
                    selectedIds: Binding { draft.selectedMemberIds ?? [] } set: { draft.selectedMemberIds = $0 },
                    onClose: closeMemberPicker
                )
            }
        }
    }

    // MARK: - Times

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
            DimmedPopup(onClose: closeTimePicker) {
                DateTimePopup(
                    field: editingTimeField == .start ? .start : .end,
                    startPlaceholder: timeLabels.start,
                    endPlaceholder: timeLabels.end,
                    endIsOptional: timeLabels.endIsOptional,
                    defaultEndHour: draft.defaultEndHour,
                    offersEndDurations: timeLabels.offersEndDurations,
                    tripDates: draft.tripDates,
                    start: $draft.startsAt,
                    end: $draft.endsAt,
                    startZone: $draft.startZone,
                    endZone: $draft.endZone,
                    viewedDay: draft.viewedDay,
                    onClose: closeTimePicker
                )
            }
        }
    }

    // MARK: - Bottom bar

    private var bottomBar: some View {
        FormBottomBar(
            notifyLabel: draft.canNotifyMembers(currentUserId: currentUserId)
                ? (draft.isEditing ? "Notify members of changes" : "Notify members")
                : nil,
            notifyMembers: $draft.notifyMembers,
            saveTitle: draft.isEditing ? "Save" : "Add \(draft.kind.label)",
            canSave: draft.hasName,
            isSaving: draft.isSaving,
            onSave: save,
            delete: draft.isEditing
                ? FormBottomBar.Delete(
                    title: "Delete \(draft.kind.label)",
                    confirmation: "Delete this \(draft.kind.label.lowercased())?",
                    message: "This can't be undone.",
                    action: delete
                )
                : nil,
            isDeleting: draft.isDeleting,
            homeIndicatorInset: homeIndicatorInset,
            background: .sheetBackground
        )
    }

    private func save() {
        Task {
            guard let saved = await draft.save(currentUserId: currentUserId, missingStartMessage: timeLabels.missingStart) else { return }
            onSaved(saved)
            dismiss()
        }
    }

    private func delete() {
        Task {
            guard await draft.delete() else { return }
            onDeleted()
            dismiss()
        }
    }
}

/// A labelled place search, the building block of each kind's place fields. The
/// label is left off when a form has just the one place.
struct TripItemPlaceField: View {
    var label: String?
    let placeholder: String
    @Binding var text: String
    @Binding var place: Place?
    @Binding var timeZone: TimeZone?
    /// Offers taking the text as typed, with no place; see `PlaceSearchField.typedEntry`.
    var typedEntry: Binding<String?>? = nil
    /// Floats the suggestions over the form; see `PlaceSearchField.floatingResults`.
    var floatingResults: PlaceSearchField.FloatingResults? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let label {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground.opacity(0.8))
            }
            PlaceSearchField(
                placeholder: placeholder,
                text: $text,
                resolvedPlace: $place,
                resolvedTimeZone: $timeZone,
                typedEntry: typedEntry,
                floatingResults: floatingResults
            )
        }
    }
}

/// The frame shared by the side-by-side blocks (a start and end time, a transit's
/// origin and destination): the label on top with a clear button once there's a
/// value, a thin rule, then the block's content. Tapping the block calls `onTap`.
struct TripItemBlock<Content: View>: View {
    let title: String
    /// Whether the block holds a value, showing the clear button and a lighter fill.
    let isSet: Bool
    let onClear: () -> Void
    let onTap: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The label and clear button sit in their own header above a thin rule,
            // a little tighter than the content below.
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
                Spacer(minLength: 4)
                if isSet {
                    Button {
                        withAnimation { onClear() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color.appForeground.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(title)")
                }
            }
            // Fixed to the clear button's height, so the header (and the block) is the
            // same height with or without it.
            .frame(height: 22)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)

            Rectangle()
                .fill(Color.appForeground.opacity(0.12))
                .frame(height: 1)

            content()
                .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // A shade darker while empty, so an unset block reads as a slot to fill.
        .background(Color.appForeground.opacity(isSet ? 0.08 : 0.04), in: .rect(cornerRadius: appFieldCornerRadius))
        // A tap gesture rather than a Button, so the clear button inside stays its own
        // target instead of nesting a button in a button.
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
    }
}

/// One of the side-by-side start/end blocks: the date (or a placeholder) and the time
/// with its zone's short code. The time line always keeps its space, so both blocks
/// stay the same height whether or not they're set. Tapping the block calls `onTap`.
struct TripItemTimeBlock: View {
    let title: String
    let placeholder: String
    @Binding var date: Date?
    @Binding var zone: TimeZone?
    let onTap: () -> Void

    var body: some View {
        TripItemBlock(
            title: title,
            isSet: date != nil,
            // Clearing a time clears everything about it, its zone included.
            onClear: {
                date = nil
                zone = nil
            },
            onTap: onTap
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let date {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                    } else {
                        Text(placeholder)
                            .foregroundStyle(Color.appForeground.opacity(0.45))
                    }
                }
                .font(.body.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

                // The time with its zone's short code beside it (e.g. "12:00 PM EST"); a
                // blank line holds its place when there's no time yet.
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let date {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.appForeground.opacity(0.85))
                        if let zone {
                            Text(WallClock.zoneAbbreviation(zone, at: date))
                                .font(.caption2)
                                .foregroundStyle(Color.appForeground.opacity(0.6))
                        }
                    } else {
                        Text(" ")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .lineLimit(1)
            }
        }
    }
}
