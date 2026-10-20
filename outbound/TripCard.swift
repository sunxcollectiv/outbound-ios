//
//  TripCard.swift
//  outbound
//

import SwiftUI

/// A tall, "story"-style tile summarizing a trip in the grid.
struct TripCard: View {
    let trip: Trip

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            TripCover(trip: trip)
            scrim
            info
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    /// A bottom-up gradient so the text stays legible over any image. It starts 20%
    /// down the card and darkens steadily to nearly opaque at the bottom.
    private var scrim: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.45), location: 0.55),
                .init(color: .black.opacity(0.85), location: 1),
            ],
            startPoint: UnitPoint(x: 0.5, y: 0.2),
            endPoint: .bottom
        )
        // Purely visual: let taps through to the photo credit chip underneath.
        .allowsHitTesting(false)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(trip.title)
                .font(.headline)
                .lineLimit(2)
            areaTags
            Text(trip.dateRangeText)
                .font(.caption)
                .foregroundStyle(Color.appForeground.opacity(0.85))
                .lineLimit(1)
        }
        .foregroundStyle(Color.appForeground)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    /// The trip's areas as small tags. Shows every tag when they fit on one line,
    /// otherwise the first one plus a "+N" count.
    @ViewBuilder
    private var areaTags: some View {
        let areas = trip.areas ?? []
        if let first = areas.first {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) {
                    ForEach(areas) { areaTag($0.name) }
                }
                HStack(spacing: 4) {
                    areaTag(first.name)
                    if areas.count > 1 { areaTag("+\(areas.count - 1)") }
                }
            }
        }
    }

    private func areaTag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.white, in: .rect(cornerRadius: 4))
    }
}

#Preview {
    TripCard(trip: .sample)
        .frame(width: 180)
        .padding()
        .appTheme()
}
