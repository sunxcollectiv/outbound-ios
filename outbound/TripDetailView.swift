//
//  TripDetailView.swift
//  outbound
//

import SwiftUI

/// The itinerary for a single trip. Content is placeholder for now — the layout
/// mirrors the eventual timeline (a time marker alongside each itinerary item)
/// so real data from `GET /trips/{id}/itinerary` can drop straight in.
struct TripDetailView: View {
    let trip: Trip

    @State private var showingAddItem = false

    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
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

                    ForEach(0..<5, id: \.self) { _ in
                        HStack(alignment: .top, spacing: 12) {
                            DashedPlaceholder(height: 44)
                                .frame(width: 64)
                            DashedPlaceholder("Itinerary item", height: 88)
                        }
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
            AddTripItemView(tripId: trip.id)
        }
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: .sample)
    }
    .appTheme()
}
