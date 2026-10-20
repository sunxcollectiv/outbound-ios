//
//  TripCover.swift
//  outbound
//

import SwiftUI

/// A trip's cover art filling its frame: shown on the trip's tile in the grid and,
/// dimmed, behind its itinerary, so opening a trip reads as the tile growing to fill
/// the screen.
struct TripCover: View {
    let trip: Trip
    /// Whether an area photo shows its Unsplash credit chip.
    var showsAttribution = true

    /// The trip's own cover image, else the first area's photo, else a styled
    /// placeholder. An area photo fetched after the list loads fades in over the
    /// placeholder.
    @ViewBuilder
    var body: some View {
        if let urlString = trip.coverImageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                placeholder
            }
        } else if let photo = areaCoverPhoto {
            AreaPhotoView(photo: photo, showsAttribution: showsAttribution) { placeholder }
        } else {
            placeholder
        }
    }

    /// The first area's default photo. Only the first area's is used, even when a
    /// later one has a photo, so the cover always matches the leading area.
    private var areaCoverPhoto: AreaPhoto? {
        trip.areas?.first?.coverPhoto
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
}
