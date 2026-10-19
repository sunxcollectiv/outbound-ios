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
        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
    }

    /// The trip's own cover image, else the first area photo, else a styled
    /// placeholder. An area photo fetched after the list loads fades in over the
    /// placeholder.
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
        } else if let photo = areaCoverPhoto {
            AreaPhotoView(photo: photo) { placeholder }
        } else {
            placeholder
        }
    }

    /// The photo of the first of the trip's areas that has one.
    private var areaCoverPhoto: AreaPhoto? {
        trip.areas?.lazy.compactMap(\.coverPhoto).first
    }

    /// A solid color shown when there's no cover art, picked from the trip's id so it
    /// looks random across trips but stays the same for each one.
    private var placeholder: some View {
        Self.placeholderColors[Self.stableIndex(for: trip.id, count: Self.placeholderColors.count)]
    }

    /// Deep, muted tones that keep white text legible and sit well on the terracotta
    /// background.
    private static let placeholderColors: [Color] = [
        Color(red: 0.18, green: 0.36, blue: 0.31), // forest
        Color(red: 0.17, green: 0.25, blue: 0.38), // navy
        Color(red: 0.36, green: 0.23, blue: 0.37), // plum
        Color(red: 0.12, green: 0.44, blue: 0.47), // teal
        Color(red: 0.48, green: 0.18, blue: 0.23), // burgundy
        Color(red: 0.36, green: 0.42, blue: 0.18), // olive
        Color(red: 0.24, green: 0.23, blue: 0.48), // indigo
        Color(red: 0.29, green: 0.33, blue: 0.38), // slate
        Color(red: 0.54, green: 0.35, blue: 0.12), // ochre
    ]

    /// A deterministic index for `id`. `hashValue` is reseeded every launch, so this
    /// uses FNV-1a to keep each trip's color the same between launches.
    private static func stableIndex(for id: String, count: Int) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in id.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return Int(hash % UInt64(count))
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
