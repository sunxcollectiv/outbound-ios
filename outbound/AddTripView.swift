//
//  AddTripView.swift
//  outbound
//

import SwiftUI

/// Modal for manually creating or editing a trip. Collects a name, start/end dates,
/// and an optional description. Timezone and locations come later, derived from trip
/// items. Pass an existing `trip` to edit it; omit it to create a new one.
struct AddTripView: View {
    @Environment(\.dismiss) private var dismiss

    /// The trip being edited, or `nil` when creating a new one.
    private let trip: Trip?

    /// Called with the created or updated trip after a successful save.
    var onSaved: (Trip) -> Void

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var description: String
    @State private var activeField: DateField?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private enum DateField { case start, end }

    private let api = APIClient.shared

    private var isEditing: Bool { trip != nil }

    init(trip: Trip? = nil, onSaved: @escaping (Trip) -> Void = { _ in }) {
        self.trip = trip
        self.onSaved = onSaved
        _title = State(initialValue: trip?.title ?? "")
        _description = State(initialValue: trip?.description ?? "")
        _startDate = State(initialValue: trip.flatMap { Self.apiDateFormatter.date(from: $0.startDate) } ?? Date())
        _endDate = State(initialValue: trip.flatMap { Self.apiDateFormatter.date(from: $0.endDate) } ?? Date())
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        TextField("Trip name", text: $title)
                            .textInputAutocapitalization(.words)
                            .appField()

                        VStack(alignment: .leading, spacing: 6) {
                            VStack(spacing: 8) {
                                dateRow(title: "Start", date: startDate, field: .start)
                                if activeField == .start {
                                    DatePicker("", selection: $startDate, displayedComponents: .date)
                                        .datePickerStyle(.graphical)
                                        .labelsHidden()
                                        .onChange(of: startDate) { _, newValue in
                                            if endDate < newValue { endDate = newValue }
                                            withAnimation { activeField = nil }
                                        }
                                }
                                Divider().overlay(Color.appForeground.opacity(0.2))
                                dateRow(title: "End", date: endDate, field: .end)
                                if activeField == .end {
                                    DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                                        .datePickerStyle(.graphical)
                                        .labelsHidden()
                                        .onChange(of: endDate) { _, _ in
                                            withAnimation { activeField = nil }
                                        }
                                }
                            }
                            .padding(14)
                            .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))

                            Text("These should be based on your arrival and departure times at the expected location.")
                                .font(.caption)
                                .foregroundStyle(Color.appForeground.opacity(0.7))
                        }

                        TextField("Description (optional)", text: $description, axis: .vertical)
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
            .navigationTitle(isEditing ? "Edit Trip" : "New Trip")
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

    /// A tappable row showing a date; tapping toggles the inline picker below it.
    private func dateRow(title: String, date: Date, field: DateField) -> some View {
        Button {
            withAnimation { activeField = (activeField == field) ? nil : field }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Text(date, style: .date)
                    .foregroundStyle(activeField == field ? Color.appAccent : Color.appForeground)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        guard endDate >= startDate else {
            errorMessage = "End date can't be before the start date."
            return
        }
        errorMessage = nil
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = TripsAPI.CreateRequest(
                    title: name,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    startDate: Self.apiDateFormatter.string(from: startDate),
                    endDate: Self.apiDateFormatter.string(from: endDate)
                )
                let endpoint = trip.map { TripsAPI.update(id: $0.id, body) } ?? TripsAPI.create(body)
                let saved = try await api.send(endpoint, as: Trip.self)
                onSaved(saved)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Formats a picked date as the API's "yyyy-MM-dd" calendar date, in the user's timezone.
    private static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

#Preview {
    AddTripView()
}
