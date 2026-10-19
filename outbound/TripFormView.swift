//
//  TripFormView.swift
//  outbound
//

import SwiftUI

/// Modal for manually creating or editing a trip. Collects a name, start/end dates,
/// and an optional description. Timezone and locations come later, derived from trip
/// items. Pass an existing `trip` to edit it; omit it to create a new one.
struct TripFormView: View {
    @Environment(\.dismiss) private var dismiss

    /// The trip being edited, or `nil` when creating a new one.
    private let trip: Trip?

    /// Called with the created or updated trip after a successful save.
    var onSaved: (Trip) -> Void

    @State private var title: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var description: String
    /// The areas the trip covers, shown as chips.
    @State private var areas: [Area]
    /// Ids of areas marked for removal. They stay as chips, faded, until the trip is
    /// saved without them, so a mistaken tap can be undone.
    @State private var areaIdsToRemove: Set<String> = []
    @State private var showingAreaPicker = false
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
        _areas = State(initialValue: trip?.areas ?? [])
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

                        areaChips

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

    /// The `area_ids` to send. Sending a list replaces all of the trip's areas, so an
    /// edit that leaves them as they were sends nothing.
    private var areaIdsToSave: [String]? {
        let ids = areas.map(\.id).filter { !areaIdsToRemove.contains($0) }
        if let trip, ids == (trip.areas ?? []).map(\.id) { return nil }
        return ids
    }

    /// An area's chip, with a button that toggles marking it for removal.
    private func areaChip(_ area: Area) -> some View {
        let isMarked = areaIdsToRemove.contains(area.id)
        return HStack(spacing: 6) {
            Text(area.name)
                .font(.subheadline.weight(.medium))
            Button {
                if isMarked {
                    areaIdsToRemove.remove(area.id)
                } else {
                    areaIdsToRemove.insert(area.id)
                }
            } label: {
                Image(systemName: isMarked ? "minus.circle.fill" : "xmark")
                    .font(.footnote.weight(.semibold))
                    // Same footprint for both icons so the chip doesn't change width.
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isMarked ? "Keep \(area.name)" : "Remove \(area.name)")
        }
        .foregroundStyle(Color.black.opacity(0.85))
        .padding(.leading, 12)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.9), in: .rect(cornerRadius: 8))
        .opacity(isMarked ? 0.8 : 1)
    }

    /// A chip per area, then a dashed chip for adding another.
    private var areaChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Areas")
                .font(.subheadline.weight(.semibold))
            FlowLayout(spacing: 8) {
                ForEach(areas) { area in
                    areaChip(area)
                }
                Button { showingAreaPicker = true } label: {
                    Label("Add area", systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .foregroundStyle(Color.appForeground.opacity(0.7))
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $showingAreaPicker) {
            AreaPickerSheet(excludedIds: Set(areas.map(\.id))) { areas.append($0) }
        }
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
                    endDate: Self.apiDateFormatter.string(from: endDate),
                    // Seed the trip's days with the device's zone on create; PATCH doesn't take it.
                    timezone: isEditing ? nil : TimeZone.current.identifier,
                    areaIds: areaIdsToSave
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
    TripFormView()
}
