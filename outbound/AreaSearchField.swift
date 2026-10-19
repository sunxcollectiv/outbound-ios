//
//  AreaSearchField.swift
//  outbound
//

import SwiftUI

/// A geographic area a trip covers (a city, region, or neighbourhood), e.g. "Kyoto".
/// Placeholder shape until the backend's areas API lands.
struct Area: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    /// Broader context shown under the name, e.g. "Kansai, Japan".
    var subtitle: String?
}

/// Looks up areas matching a typed query.
protocol AreaSearching {
    func search(_ query: String) async throws -> [Area]
}

/// Filters a fixed in-memory list. Stands in for the areas API until it exists.
struct StubAreaSearch: AreaSearching {
    var areas: [Area] = Self.sampleAreas

    func search(_ query: String) async throws -> [Area] {
        areas.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || ($0.subtitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    static let sampleAreas: [Area] = [
        Area(id: "tokyo", name: "Tokyo", subtitle: "Kantō, Japan"),
        Area(id: "kyoto", name: "Kyoto", subtitle: "Kansai, Japan"),
        Area(id: "osaka", name: "Osaka", subtitle: "Kansai, Japan"),
        Area(id: "hokkaido", name: "Hokkaido", subtitle: "Japan"),
        Area(id: "paris", name: "Paris", subtitle: "Île-de-France, France"),
        Area(id: "provence", name: "Provence", subtitle: "France"),
        Area(id: "lisbon", name: "Lisbon", subtitle: "Portugal"),
        Area(id: "amalfi", name: "Amalfi Coast", subtitle: "Campania, Italy"),
        Area(id: "tuscany", name: "Tuscany", subtitle: "Italy"),
        Area(id: "nyc", name: "New York City", subtitle: "New York, USA"),
        Area(id: "big-sur", name: "Big Sur", subtitle: "California, USA"),
        Area(id: "mexico-city", name: "Mexico City", subtitle: "Mexico"),
    ]
}

/// A text field with autosuggest for picking an `Area`. Typing shows matching areas;
/// picking one fills the field and reports it through `selection`. Typing again
/// clears the selection until another suggestion is picked.
struct AreaSearchField: View {
    let placeholder: String
    @Binding var selection: Area?
    var search: any AreaSearching = StubAreaSearch()

    @State private var text: String
    @State private var suggestions: [Area] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    /// Set when we fill the text from a suggestion, so the resulting change doesn't
    /// immediately kick off another search.
    @State private var isFillingFromSuggestion = false
    @FocusState private var isFocused: Bool

    init(_ placeholder: String, selection: Binding<Area?>, search: any AreaSearching = StubAreaSearch()) {
        self.placeholder = placeholder
        _selection = selection
        self.search = search
        _text = State(initialValue: selection.wrappedValue?.name ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "map")
                    .foregroundStyle(Color.black.opacity(0.45))
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in onTextChanged(newValue) }
                if !text.isEmpty {
                    Button("Clear", systemImage: "xmark.circle.fill", action: clear)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Color.black.opacity(0.35))
                        .buttonStyle(.plain)
                }
            }
            .appField()

            results

            if let selection, let subtitle = selection.subtitle {
                Label(subtitle, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(Color.appForeground.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The autosuggest list shown beneath the field.
    @ViewBuilder
    private var results: some View {
        if isSearching || !suggestions.isEmpty {
            VStack(spacing: 0) {
                if isSearching && suggestions.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching areas…")
                            .font(.footnote)
                            .foregroundStyle(Color.appForeground.opacity(0.7))
                        Spacer()
                    }
                    .padding(14)
                }

                ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, area in
                    Button {
                        select(area)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(area.name)
                                .font(.subheadline.weight(.medium))
                            if let subtitle = area.subtitle {
                                Text(subtitle)
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

    /// Debounces input changes and runs a search, unless the change came from picking
    /// a suggestion.
    private func onTextChanged(_ newValue: String) {
        if isFillingFromSuggestion {
            isFillingFromSuggestion = false
            return
        }
        guard isFocused else { return }

        // Typing invalidates the current selection.
        selection = nil

        searchTask?.cancel()
        let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            suggestions = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let results = (try? await search.search(query)) ?? []
            guard !Task.isCancelled else { return }
            suggestions = results
            isSearching = false
        }
    }

    private func select(_ area: Area) {
        searchTask?.cancel()
        if text != area.name { isFillingFromSuggestion = true }
        text = area.name
        selection = area
        suggestions = []
        isSearching = false
        isFocused = false
    }

    private func clear() {
        searchTask?.cancel()
        if !text.isEmpty { isFillingFromSuggestion = true }
        text = ""
        selection = nil
        suggestions = []
        isSearching = false
    }
}
