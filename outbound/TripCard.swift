//
//  TripCard.swift
//  outbound
//

import SwiftUI

/// A card summarizing a trip in the list.
struct TripCard: View {
    let trip: Trip

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(trip.title)
                .font(.title3.bold())
            Text(trip.dateRangeText)
                .font(.subheadline)
                .foregroundStyle(Color.appForeground.opacity(0.85))
            if let description = trip.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.appCard.opacity(0.6), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.appForeground.opacity(0.15))
        }
    }
}

#Preview {
    TripCard(trip: .sample)
        .padding()
        .appTheme()
}
