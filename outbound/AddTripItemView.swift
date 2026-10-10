//
//  AddTripItemView.swift
//  outbound
//

import SwiftUI

/// Modal for manually adding an item to a trip. Collects a kind, title, start/end
/// times, and optional notes. Locations come later, derived separately.
struct AddTripItemView: View {
    let tripId: String

    @Environment(\.dismiss) private var dismiss

    /// Called with the newly created item after a successful save.
    var onCreated: (TripItem) -> Void = { _ in }

    @State private var kind: TripItemKind = .activity
    @State private var scope: TripItemScope = .group
    @State private var title = ""
    @State private var startsAt = Date()
    @State private var hasEndTime = false
    @State private var endsAt = Date()
    @State private var notes = ""
    @State private var activeField: TimeField?
    @State private var isSaving = false
    @State private var errorMessage: String?

    private enum TimeField { case start, end }

    private let api = APIClient.shared

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

                        TextField("Title", text: $title)
                            .textInputAutocapitalization(.words)
                            .appField()

                        VStack(spacing: 8) {
                            timeRow(title: "Starts", date: startsAt, field: .start)
                            if activeField == .start {
                                DatePicker("", selection: $startsAt, displayedComponents: [.date, .hourAndMinute])
                                    .datePickerStyle(.graphical)
                                    .labelsHidden()
                                    .onChange(of: startsAt) { _, newValue in
                                        if endsAt < newValue { endsAt = newValue }
                                    }
                            }

                            Divider().overlay(Color.appForeground.opacity(0.2))

                            Toggle("Set end time", isOn: $hasEndTime.animation())
                            if hasEndTime {
                                timeRow(title: "Ends", date: endsAt, field: .end)
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
            .navigationTitle("New Item")
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
                let body = TripItemsAPI.CreateRequest(
                    kind: kind,
                    scope: scope,
                    title: trimmedTitle,
                    notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
                    startsAt: startsAt,
                    endsAt: hasEndTime ? endsAt : nil
                )
                let item = try await api.send(TripItemsAPI.create(tripId: tripId, body), as: TripItem.self)
                onCreated(item)
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
