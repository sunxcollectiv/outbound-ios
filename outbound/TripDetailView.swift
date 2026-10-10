//
//  TripDetailView.swift
//  outbound
//

import SwiftUI

/// The itinerary for a single trip. The header renders instantly from the `Trip`
/// passed in from the list; the day-by-day itinerary loads asynchronously and
/// fills in, showing placeholder scaffolding while in flight.
struct TripDetailView: View {
    let trip: Trip

    @State private var days: [ItineraryDay]?
    @State private var errorMessage: String?
    @State private var showingAddItem = false

    private let api = APIClient.shared

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    if let days {
                        ForEach(days) { day in
                            daySection(day)
                        }
                    } else if let errorMessage {
                        errorState(errorMessage)
                    } else {
                        loadingScaffold
                    }
                }
                .padding()
            }
        }
        .foregroundStyle(Color.appForeground)
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Item")
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddTripItemView(tripId: trip.id, onCreated: { _ in
                Task { await load() }
            })
        }
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trip.title)
                .font(.largeTitle.bold())
            Text(trip.dateRangeText)
                .font(.subheadline)
                .foregroundStyle(Color.appForeground.opacity(0.85))
            if let description = trip.description, !description.isEmpty {
                Text(description)
                    .font(.callout)
                    .foregroundStyle(Color.appForeground.opacity(0.75))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func daySection(_ day: ItineraryDay) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Day \(day.dayNumber)")
                    .font(.headline)
                Text(day.displayDate)
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
            }

            ForEach(day.lodging, id: \.item.id) { stay in
                lodgingRow(stay)
            }

            if day.items.isEmpty && day.lodging.isEmpty {
                Text("Nothing planned")
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground.opacity(0.5))
            } else {
                ForEach(day.items) { item in
                    itemRow(item)
                }
            }
        }
    }

    private func itemRow(_ item: TripItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(item.startsAt, format: .dateTime.hour().minute())
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Color.appForeground.opacity(0.75))
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.kind.label.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(Color.appForeground.opacity(0.55))
                Text(item.title)
                    .font(.body.weight(.semibold))
                if let notes = item.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.footnote)
                        .foregroundStyle(Color.appForeground.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.appCard.opacity(0.6), in: .rect(cornerRadius: 10))
        }
    }

    private func lodgingRow(_ stay: LodgingStay) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bed.double.fill")
                .font(.caption)
            Text(stay.item.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(stay.phase.label)
                .font(.caption)
                .foregroundStyle(Color.appForeground.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.appForeground.opacity(0.1), in: .rect(cornerRadius: 10))
    }

    private var loadingScaffold: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    DashedPlaceholder(height: 20)
                        .frame(width: 140)
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(alignment: .top, spacing: 12) {
                            DashedPlaceholder(height: 44)
                                .frame(width: 52)
                            DashedPlaceholder("Itinerary item", height: 72)
                        }
                    }
                }
            }
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appForeground.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private func load() async {
        do {
            let itinerary = try await api.send(TripsAPI.itinerary(tripId: trip.id), as: Itinerary.self)
            days = itinerary.days
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: .sample)
    }
    .appTheme()
}
