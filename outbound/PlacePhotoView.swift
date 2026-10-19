//
//  PlacePhotoView.swift
//  outbound
//

import SwiftUI

/// A place's cover photo filling its frame, with the photographer credit Google
/// requires in the bottom-trailing corner (each name linked to its profile when the
/// server gives one). Shows `placeholder` while the image loads, fades the photo in
/// over it once it arrives, and keeps showing the placeholder if loading fails — a
/// cover `url` can 403 once its reference expires.
///
/// Images come through `PlaceImageCache`, so one already loaded this session shows
/// straight away with no placeholder or fade.
struct PlacePhotoView<Placeholder: View>: View {
    let photo: CoverPhoto
    @ViewBuilder var placeholder: Placeholder

    @State private var image: UIImage?

    init(photo: CoverPhoto, @ViewBuilder placeholder: () -> Placeholder) {
        self.photo = photo
        self.placeholder = placeholder()
        _image = State(initialValue: PlaceImageCache.shared.cachedImage(for: photo.url))
    }

    var body: some View {
        // The placeholder stays underneath and the photo fades in over it, rather
        // than cutting from one to the other the moment it arrives.
        ZStack {
            placeholder
            if let image {
                // Fill whatever frame the caller gives, so the credit sits in the
                // visible corner rather than off the edge of the scaled-to-fill image.
                Color.clear
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipped()
                    .overlay(alignment: .bottomTrailing) { attribution }
                    .transition(.opacity)
            }
        }
        .task(id: photo.url) {
            if let cached = PlaceImageCache.shared.cachedImage(for: photo.url) {
                image = cached
                return
            }
            image = nil
            let loaded = await PlaceImageCache.shared.image(for: photo.url)
            withAnimation(.easeOut(duration: 0.25)) { image = loaded }
        }
    }

    @ViewBuilder
    private var attribution: some View {
        if !credits.isEmpty {
            Text(credit)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .tint(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.6), radius: 2)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
        }
    }

    /// The credits that have a name to show.
    private var credits: [(name: String, uri: URL?)] {
        photo.attributions.compactMap { author in
            author.displayName.map { ($0, author.uri) }
        }
    }

    /// "Photo: Jane D, Sam K", with each name linked to its `uri` when present.
    private var credit: AttributedString {
        var text = AttributedString("Photo: ")
        for (index, author) in credits.enumerated() {
            if index > 0 { text += AttributedString(", ") }
            var name = AttributedString(author.name)
            name.link = author.uri
            text += name
        }
        return text
    }
}
