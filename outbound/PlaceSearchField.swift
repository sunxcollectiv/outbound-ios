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
    /// When supplied, the suggestions open with a row for taking the text exactly as
    /// typed, with no place behind it; choosing it sets this to that text. Cleared,
    /// like `resolvedPlace`, as soon as the user types again.
    var typedEntry: Binding<String?>? = nil
    /// When set, the suggestions float over the content below while the field is
    /// focused, instead of pushing it down.
    var floatingResults: FloatingResults? = nil

    /// How floating suggestions are laid out.
    struct FloatingResults {
        /// The list's width; nil for the field's own. Wider lets a narrow field (say,
        /// half a row) open a list as wide as its row.
        var width: CGFloat? = nil
        /// The field edge a wider list lines up with.
        var edge: HorizontalEdge = .leading
    }

    @State private var suggestions: [PlaceSuggestion] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var selected: PlaceSuggestion?
    @State private var isResolving = false
    @State private var errorText: String?
    /// Whether the "use as typed" row is up: from typing until a row is chosen.
    @State private var offeringTypedEntry = false
    /// The field's height, to hang floating results just below it.
    @State private var fieldHeight: CGFloat = 0
    /// Set when we fill the text from a suggestion, so the resulting change doesn't
    /// immediately kick off another search.
    @State private var isFillingFromSuggestion = false
    /// Tracks whether the user is actively editing the field, so a programmatic change
    /// to `text` (e.g. prefilling an edit form) doesn't trigger a search or clear the
    /// current selection — only typing in the focused field searches.
    @FocusState private var isFocused: Bool

    private let places = GooglePlacesClient.shared
    private let api = APIClient.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                LocationPin()
                    .fill(Color.black.opacity(0.4), style: FillStyle(eoFill: true))
                    .frame(width: 14, height: 19)
                    .accessibilityHidden(true)
            }
            .appField()
            // The icon is part of the field: tapping it starts typing too.
            .contentShape(Rectangle())
            .onTapGesture { isFocused = true }
                .onChange(of: text) { _, newValue in onTextChanged(newValue) }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fieldHeight = $0 }
            // Hung 8pt below the field, so it covers what's below.
            .overlay(alignment: floatingResults?.edge == .trailing ? .topTrailing : .topLeading) {
                if let floatingResults, isFocused {
                    results
                        // Its own height, not the field's that the overlay offers.
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: floatingResults.width)
                        .offset(y: fieldHeight + 8)
                }
            }

            if floatingResults == nil {
                results
            }
            status
        }
    }

    /// The autocomplete suggestions list shown beneath the field.
    @ViewBuilder
    private var results: some View {
        if isSearching || !suggestions.isEmpty || showsTypedEntryRow {
            VStack(spacing: 0) {
                if showsTypedEntryRow {
                    typedEntryRow
                    if isSearching || !suggestions.isEmpty {
                        Divider().overlay(Color.appForeground.opacity(0.15))
                    }
                }

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
            .background(Color.appForeground.opacity(0.08))
            // Opaque when floating, so the form doesn't show through.
            .background(floatingResults == nil ? Color.clear : Color.sheetBackground)
            // Clipped so a row's own background keeps to the rounded corners.
            .clipShape(.rect(cornerRadius: appFieldCornerRadius))
            .shadow(color: .black.opacity(floatingResults == nil ? 0 : 0.35), radius: 16, y: 6)
        }
    }

    private var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var showsTypedEntryRow: Bool {
        typedEntry != nil && offeringTypedEntry && !trimmedText.isEmpty
    }

    /// Takes the text as typed instead of a suggestion, e.g. for a place Google
    /// doesn't know or a name that's no place at all.
    private var typedEntryRow: some View {
        Button(action: useTypedEntry) {
            // One wrapping line, with only the typed text at full strength.
            Text("Use \(Text(trimmedText).foregroundStyle(Color.appForeground)) without map location")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.appForeground.opacity(0.5))
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            // A shade lighter than the suggestions, to set it apart from the places.
            .background(Color.appForeground.opacity(0.06))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func useTypedEntry() {
        searchTask?.cancel()
        let entry = trimmedText
        // Only when trimming changes the text: an unchanged text fires no change to
        // consume the flag, which would then swallow the next keystroke.
        if text != entry {
            isFillingFromSuggestion = true
            text = entry
        }
        typedEntry?.wrappedValue = entry
        offeringTypedEntry = false
        suggestions = []
        isSearching = false
        isFocused = false
    }

    /// Small confirmation row reflecting the result of saving the picked place.
    @ViewBuilder
    private var status: some View {
        if typedEntry?.wrappedValue != nil {
            statusLabel("No map location", systemImage: "character.cursor.ibeam", tint: Color.appForeground.opacity(0.8))
        } else if isResolving {
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
            // One line beside a neighboring field, so the two stay level.
            .lineLimit(floatingResults == nil ? nil : 1)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Debounces input changes and runs a place search, unless the change came from
    /// picking a suggestion.
    private func onTextChanged(_ newValue: String) {
        if isFillingFromSuggestion {
            isFillingFromSuggestion = false
            return
        }

        // Ignore programmatic changes (e.g. prefilling an edit form): without focus
        // there's no user typing to autocomplete, and we mustn't clear the selection.
        guard isFocused else { return }

        // Typing invalidates any previously selected/resolved place.
        selected = nil
        resolvedPlace = nil
        resolvedTimeZone?.wrappedValue = nil
        typedEntry?.wrappedValue = nil
        offeringTypedEntry = true
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
        offeringTypedEntry = false
        suggestions = []
        isSearching = false
        // A narrow floating field would stay scrolled to the name's end while focused.
        if floatingResults != nil { isFocused = false }
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

/// A map marker: a round head tapering to a point at the bottom, with a hole in the
/// middle. Fill it with `eoFill` so the hole stays clear.
struct LocationPin: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let tip = CGPoint(x: rect.midX, y: rect.maxY)
        // Where the straight sides from the tip meet the head, either side of straight down.
        let spread = Angle(radians: acos(radius / (tip.y - center.y)))

        var path = Path()
        path.move(to: tip)
        path.addArc(center: center, radius: radius,
                    startAngle: .degrees(90) - spread, endAngle: .degrees(90) + spread,
                    clockwise: true)
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: center.x - radius * 0.4, y: center.y - radius * 0.4,
                                   width: radius * 0.8, height: radius * 0.8))
        return path
    }
}
