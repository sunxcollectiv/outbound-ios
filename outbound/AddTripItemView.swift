//
//  AddTripItemView.swift
//  outbound
//

import SwiftUI

/// Modal for manually adding or editing a trip item. Collects a kind, title,
/// start/end times, and optional notes. Locations come later, derived separately.
/// Pass an existing `item` to edit it; omit it to create a new one.
struct AddTripItemView: View {
    let tripId: String

    @Environment(\.dismiss) private var dismiss

    /// The item being edited, or `nil` when creating a new one.
    private let item: TripItem?

    /// Called with the created or updated item after a successful save.
    var onSaved: (TripItem) -> Void

    @State private var kind: TripItemKind
    @State private var scope: TripItemScope
    @State private var title: String
    @State private var startsAt: Date
    @State private var hasEndTime: Bool
    @State private var endsAt: Date
    @State private var notes: String
    @State private var activeField: TimeField?
    @State private var isSaving = false
    @State private var errorMessage: String?

    // Place search for the title field, powered by Google Places Autocomplete.
    @State private var placeSuggestions: [PlaceSuggestion] = []
    @State private var isSearchingPlaces = false
    @State private var placeSearchTask: Task<Void, Never>?
    /// The place picked from the suggestions, kept for wiring item locations later.
    @State private var selectedPlace: PlaceSuggestion?
    /// The internal place created from the selection via `POST /places`.
    /// Its `id` is what a trip item will reference as `place_id` once that's wired up.
    @State private var resolvedPlace: Place?
    @State private var isResolvingPlace = false
    @State private var placeError: String?
    /// Set when we fill the title from a suggestion, so the resulting title change
    /// doesn't immediately kick off another search.
    @State private var isFillingFromSuggestion = false

    private enum TimeField { case start, end }

    private let api = APIClient.shared
    private let places = GooglePlacesClient.shared

    private var isEditing: Bool { item != nil }
    private var startLabel: String { kind == .lodging ? "Check-in" : "Starts" }
    private var endLabel: String { kind == .lodging ? "Check-out" : "Ends" }

    init(tripId: String, item: TripItem? = nil, onSaved: @escaping (TripItem) -> Void = { _ in }) {
        self.tripId = tripId
        self.item = item
        self.onSaved = onSaved
        _kind = State(initialValue: item?.kind ?? .activity)
        _scope = State(initialValue: item?.scope ?? .group)
        _title = State(initialValue: item?.title ?? "")
        _startsAt = State(initialValue: item?.startsAt ?? Date())
        _hasEndTime = State(initialValue: item?.endsAt != nil)
        _endsAt = State(initialValue: item?.endsAt ?? item?.startsAt ?? Date())
        _notes = State(initialValue: item?.notes ?? "")
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

                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Title or search a place", text: $title)
                                .textInputAutocapitalization(.words)
                                .autocorrectionDisabled()
                                .appField()
                                .onChange(of: title) { _, newValue in
                                    onTitleChanged(newValue)
                                }

                            placeSearchResults
                            placeStatus
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

                            Divider().overlay(Color.appForeground.opacity(0.2))

                            Toggle(kind == .lodging ? "Set check-out time" : "Set end time", isOn: $hasEndTime.animation())
                            if hasEndTime {
                                timeRow(title: endLabel, date: endsAt, field: .end)
                                if activeField == .end {
                                    DatePicker("", selection: $endsAt, in: startsAt..., displayedComponents: [.date, .hourAndMinute])
                                        .datePickerStyle(.graphical)
                                        .labelsHidden()
                                }
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

    /// The autocomplete suggestions list shown beneath the title field.
    @ViewBuilder
    private var placeSearchResults: some View {
        if isSearchingPlaces || !placeSuggestions.isEmpty {
            VStack(spacing: 0) {
                if isSearchingPlaces && placeSuggestions.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching places…")
                            .font(.footnote)
                            .foregroundStyle(Color.appForeground.opacity(0.7))
                        Spacer()
                    }
                    .padding(14)
                }

                ForEach(Array(placeSuggestions.enumerated()), id: \.element.id) { index, suggestion in
                    Button {
                        select(suggestion)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.mainText)
                                .font(.subheadline.weight(.medium))
                            if let secondary = suggestion.secondaryText {
                                Text(secondary)
                                    .font(.caption)
                                    .foregroundStyle(Color.appForeground.opacity(0.7))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if index < placeSuggestions.count - 1 {
                        Divider().overlay(Color.appForeground.opacity(0.15))
                    }
                }
            }
            .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
        }
    }

    /// Small confirmation row shown after a place is picked, reflecting the result of
    /// saving it to our places DB.
    @ViewBuilder
    private var placeStatus: some View {
        if isResolvingPlace {
            statusLabel("Saving place…", systemImage: "mappin.and.ellipse", tint: Color.appForeground.opacity(0.7))
        } else if let resolvedPlace {
            statusLabel(
                resolvedPlace.address ?? selectedPlace?.secondaryText ?? "Place saved",
                systemImage: "checkmark.circle.fill",
                tint: Color.appForeground.opacity(0.8)
            )
        } else if let placeError {
            statusLabel(placeError, systemImage: "exclamationmark.triangle.fill", tint: .red)
        }
    }

    private func statusLabel(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Debounces input changes and runs a place search, unless the change came from
    /// picking a suggestion.
    private func onTitleChanged(_ newValue: String) {
        if isFillingFromSuggestion {
            isFillingFromSuggestion = false
            return
        }

        // Typing invalidates any previously selected/resolved place.
        selectedPlace = nil
        resolvedPlace = nil
        placeError = nil

        placeSearchTask?.cancel()
        let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            placeSuggestions = []
            isSearchingPlaces = false
            return
        }

        isSearchingPlaces = true
        placeSearchTask = Task {
            // Debounce so we don't fire a request on every keystroke.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let results = try await places.autocomplete(query)
                guard !Task.isCancelled else { return }
                placeSuggestions = results
            } catch {
                guard !Task.isCancelled else { return }
                placeSuggestions = []
            }
            isSearchingPlaces = false
        }
    }

    /// Fills the title from a chosen suggestion, dismisses the list, and resolves the
    /// place into our own database.
    private func select(_ suggestion: PlaceSuggestion) {
        placeSearchTask?.cancel()
        isFillingFromSuggestion = true
        title = suggestion.mainText
        selectedPlace = suggestion
        placeSuggestions = []
        isSearchingPlaces = false
        resolvePlace(suggestion)
    }

    /// Sends the selected Google place to `POST /places` so the backend registers it in
    /// our places DB, and keeps the returned internal place. This fires on selection
    /// regardless of whether the item is ultimately saved.
    private func resolvePlace(_ suggestion: PlaceSuggestion) {
        resolvedPlace = nil
        placeError = nil
        isResolvingPlace = true
        Task {
            defer { isResolvingPlace = false }
            do {
                let place = try await api.send(PlacesAPI.create(googlePlaceId: suggestion.placeId), as: Place.self)
                // Ignore if the user changed the selection while this was in flight.
                guard selectedPlace?.placeId == suggestion.placeId else { return }
                resolvedPlace = place
            } catch {
                guard selectedPlace?.placeId == suggestion.placeId else { return }
                placeError = error.localizedDescription
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        guard !trimmedTitle.isEmpty else { return }
        if hasEndTime && endsAt < startsAt {
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
                let resolvedEnd = hasEndTime ? endsAt : nil

                let endpoint: Endpoint
                if let item {
                    // The update endpoint has no `scope` field, so it isn't sent here.
                    let body = TripItemsAPI.UpdateRequest(
                        kind: kind,
                        title: trimmedTitle,
                        notes: resolvedNotes,
                        startsAt: startsAt,
                        endsAt: resolvedEnd
                    )
                    endpoint = TripItemsAPI.update(tripId: tripId, itemId: item.id, body)
                } else {
                    let body = TripItemsAPI.CreateRequest(
                        kind: kind,
                        scope: scope,
                        title: trimmedTitle,
                        notes: resolvedNotes,
                        startsAt: startsAt,
                        endsAt: resolvedEnd
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
}

#Preview {
    AddTripItemView(tripId: "sample")
}
