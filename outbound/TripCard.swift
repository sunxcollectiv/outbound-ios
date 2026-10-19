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
            cover
            scrim
            info
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.appForeground.opacity(0.15))
        }
    }

    /// The cover image, or a styled placeholder when none is set / still loading.
    @ViewBuilder
    private var cover: some View {
        if let urlString = trip.coverImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholder
            }
        } else {
            placeholder
        }
    }

    /// A warm gradient with a translucent travel glyph, shown when there's no cover art.
    private var placeholder: some View {
        LinearGradient(
            colors: [Color.appCard, Color.appAccent],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.appForeground.opacity(0.35))
                .offset(y: -32)
        }
    }

    /// A bottom-up gradient so the text stays legible over any image.
    private var scrim: some View {
        LinearGradient(
            colors: [.clear, .black.opacity(0.65)],
            startPoint: .center,
            endPoint: .bottom
        )
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
