//
//  PlaceSearchField.swift
//  outbound
//

import SwiftUI

/// A text field that doubles as a Google Places search. Typing shows autocomplete
/// suggestions; picking one fills the field, registers the place in our DB via
/// `POST /places`, and reports the resulting internal `Place` back through
/// `resolvedPlace` (its `id` is what a trip item references as `place_id`).
///
/// The registration fires on selection regardless of whether the surrounding form is
/// ultimately submitted.
struct PlaceSearchField: View {
    let placeholder: String
    @Binding var text: String
    /// The internal place created from the current selection, or `nil` when none is
    /// selected (e.g. the user typed free text instead of picking a suggestion).
    @Binding var resolvedPlace: Place?
    /// The selected place's IANA time zone, when callers want it (optional so other
    /// uses of this field don't have to supply a binding). Preferred from Google, with
    /// the backend place's zone as a fallback; cleared whenever the selection clears.
    var resolvedTimeZone: Binding<TimeZone?>? = nil

    @State private var suggestions: [PlaceSuggestion] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selected: PlaceSuggestion?
    @State private var isResolving = false
    @State private var errorText: String?
    /// Set when we fill the text from a suggestion, so the resulting change doesn't
    /// immediately kick off another search.
    @State private var isFillingFromSuggestion = false

    private let places = GooglePlacesClient.shared
    private let api = APIClient.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .appField()
                .onChange(of: text) { _, newValue in onTextChanged(newValue) }

            results
            status
        }
    }

    /// The autocomplete suggestions list shown beneath the field.
    @ViewBuilder
    private var results: some View {
        if isSearching || !suggestions.isEmpty {
            VStack(spacing: 0) {
                if isSearching && suggestions.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching places…")
                            .font(.footnote)
                            .foregroundStyle(Color.appForeground.opacity(0.7))
                        Spacer()
                    }
                    .padding(14)
                }

                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
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

                    if index < suggestions.count - 1 {
                        Divider().overlay(Color.appForeground.opacity(0.15))
                    }
                }
            }
            .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
        }
    }

    /// Small confirmation row reflecting the result of saving the picked place.
    @ViewBuilder
    private var status: some View {
        if isResolving {
            statusLabel("Saving place…", systemImage: "mappin.and.ellipse", tint: Color.appForeground.opacity(0.7))
        } else if resolvedPlace != nil {
            statusLabel(
                resolvedPlace?.address ?? selected?.secondaryText ?? "Place saved",
                systemImage: "checkmark.circle.fill",
                tint: Color.appForeground.opacity(0.8)
            )
        } else if let errorText {
            statusLabel(errorText, systemImage: "exclamationmark.triangle.fill", tint: .red)
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
    private func onTextChanged(_ newValue: String) {
        if isFillingFromSuggestion {
            isFillingFromSuggestion = false
            return
        }

        // Typing invalidates any previously selected/resolved place.
        selected = nil
        resolvedPlace = nil
        resolvedTimeZone?.wrappedValue = nil
        errorText = nil

        searchTask?.cancel()
        let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            suggestions = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            // Debounce so we don't fire a request on every keystroke.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let results = try await places.autocomplete(query)
                guard !Task.isCancelled else { return }
                suggestions = results
            } catch {
                guard !Task.isCancelled else { return }
                suggestions = []
            }
            isSearching = false
        }
    }

    /// Fills the text from a chosen suggestion, dismisses the list, and resolves the
    /// place into our own database.
    private func select(_ suggestion: PlaceSuggestion) {
        searchTask?.cancel()
        isFillingFromSuggestion = true
        text = suggestion.mainText
        selected = suggestion
        suggestions = []
        isSearching = false
        resolve(suggestion)
    }

    /// Sends the selected Google place to `POST /places` so the backend registers it in
    /// our places DB, and keeps the returned internal place.
    private func resolve(_ suggestion: PlaceSuggestion) {
        resolvedPlace = nil
        resolvedTimeZone?.wrappedValue = nil
        errorText = nil
        isResolving = true
        Task {
            defer { isResolving = false }
            do {
                let place = try await api.send(PlacesAPI.create(googlePlaceId: suggestion.placeId), as: Place.self)
                // Ignore if the user changed the selection while this was in flight.
                guard selected?.placeId == suggestion.placeId else { return }
                resolvedPlace = place

                // Pull the zone straight from Google (reliable immediately), falling
                // back to the backend place's zone if Google doesn't report one.
                if resolvedTimeZone != nil {
                    let googleZone = try? await places.placeTimeZone(placeId: suggestion.placeId)
                    guard selected?.placeId == suggestion.placeId else { return }
                    resolvedTimeZone?.wrappedValue = googleZone ?? place.timeZone
                }
            } catch {
                guard selected?.placeId == suggestion.placeId else { return }
                errorText = error.localizedDescription
            }
        }
    }
}
