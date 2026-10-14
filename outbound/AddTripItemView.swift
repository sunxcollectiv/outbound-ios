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

    private enum TimeField { case start, end }

    private let api = APIClient.shared

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

                        TextField("Title", text: $title)
                            .textInputAutocapitalization(.words)
                            .appField()

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
                let endpoint = item.map { TripItemsAPI.update(tripId: tripId, itemId: $0.id, body) }
                    ?? TripItemsAPI.create(tripId: tripId, body)
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
