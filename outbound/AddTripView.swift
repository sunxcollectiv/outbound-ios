//
//  AddTripView.swift
//  outbound
//

import SwiftUI

/// Modal for manually creating a trip. Collects a name, start/end dates, and an
/// optional description. Timezone and locations come later, derived from trip items.
struct AddTripView: View {
    @Environment(\.dismiss) private var dismiss

    /// Called with the newly created trip after a successful save.
    var onCreated: (Trip) -> Void = { _ in }

    @State private var title = ""
    @State private var startDate = Date()
    @State private var endDate = Date()
    @State private var description = ""
    @State private var activeField: DateField?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private enum DateField { case start, end }

    private let api = APIClient.shared

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
            .navigationTitle("New Trip")
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
                        Button("Add", action: save)
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
                let trip = try await api.send(TripsAPI.create(body), as: Trip.self)
                onCreated(trip)
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
