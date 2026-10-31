//
//  AreaPickerSheet.swift
//  outbound
//

import SwiftUI

/// Looks up areas matching a typed query.
protocol AreaSearching {
    func search(_ query: String) async throws -> [Area]
}

/// Searches areas through `GET /areas`.
struct APIAreaSearch: AreaSearching {
    var api = APIClient.shared

    func search(_ query: String) async throws -> [Area] {
        try await api.send(AreasAPI.search(query), as: [Area].self)
    }
}

/// Modal for adding an area: a search field with results beneath it. Picking a
/// result reports it through `onPick` and closes the sheet.
struct AreaPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Ids of areas already added, left out of the results.
    var excludedIds: Set<String> = []
    var search: any AreaSearching = APIAreaSearch()
    var onPick: (Area) -> Void

    @State private var text = ""
    @State private var results: [Area] = []
    @State private var isSearching = false
    /// Whether a search has finished for the current text, so "no results" only shows
    /// after one has actually run.
    @State private var hasSearched = false
    @State private var searchTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        searchField
                        resultsList
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .overlay(alignment: .bottom) {
                // Part of the trip form, so the offline pill keeps the form's wording,
                // 8pt over the bottom safe area (or the keyboard).
                Color.clear
                    .frame(height: 8)
                    .offlinePillAnchor(isForm: true)
                    .allowsHitTesting(false)
            }
            .foregroundStyle(Color.appForeground)
            .navigationTitle("Add Area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .appTheme()
        .onAppear { isFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Color.black.opacity(0.45))
            TextField("Search cities and countries", text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($isFocused)
                .onChange(of: text) { _, newValue in onTextChanged(newValue) }
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Color.black.opacity(0.35))
                    .buttonStyle(.plain)
            }
        }
        .appField()
    }

    @ViewBuilder
    private var resultsList: some View {
        let visible = results.filter { !excludedIds.contains($0.id) }
        if isSearching && visible.isEmpty {
            HStack(spacing: 8) {
                ProgressView()
                Text("Searching areas…")
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(Color.appForeground.opacity(0.7))
            .padding(.horizontal, 4)
        } else if hasSearched && visible.isEmpty {
            Text("No matching areas")
                .font(.footnote)
                .foregroundStyle(Color.appForeground.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
        } else if !visible.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, area in
                    Button {
                        onPick(area)
                        dismiss()
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

                    if index < visible.count - 1 {
                        Divider().overlay(Color.appForeground.opacity(0.15))
                    }
                }
            }
            .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
        }
    }

    /// Debounces input changes and runs a search.
    private func onTextChanged(_ newValue: String) {
        searchTask?.cancel()
        hasSearched = false
        let query = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            let found = (try? await search.search(query)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
            hasSearched = true
        }
    }
}
