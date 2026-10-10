//
//  TripDetailView.swift
//  outbound
//

import SwiftUI

/// The itinerary for a single trip. Content is placeholder for now — the layout
/// mirrors the eventual timeline (a time marker alongside each itinerary item)
/// so real data from `GET /trips/{id}/itinerary` can drop straight in.
struct TripDetailView: View {
    var body: some View {
        ZStack {
            Color.appBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DashedPlaceholder("Trip summary", height: 100)

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
        .navigationTitle("Itinerary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }
}

#Preview {
    NavigationStack {
        TripDetailView()
    }
    .appTheme()
}
