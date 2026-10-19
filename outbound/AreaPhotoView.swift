//
//  AreaPhotoView.swift
//  outbound
//

import SwiftUI

/// An area's Unsplash photo filling its frame, with the "Photo by … on Unsplash"
/// credit Unsplash requires as a chip in the top-leading corner (the name linked to
/// the photographer's profile when the server gives one). Shows `placeholder` while the
/// image loads, fades the photo in over it once it arrives, and keeps showing the
/// placeholder if loading fails.
///
/// Images come through `PlaceImageCache`, so one already loaded this session shows
/// straight away with no placeholder or fade.
struct AreaPhotoView<Placeholder: View>: View {
    let photo: AreaPhoto
    @ViewBuilder var placeholder: Placeholder

    @State private var image: UIImage?

    init(photo: AreaPhoto, @ViewBuilder placeholder: () -> Placeholder) {
        self.photo = photo
        self.placeholder = placeholder()
        _image = State(initialValue: PlaceImageCache.shared.cachedImage(for: photo.url))
    }

    var body: some View {
        ZStack {
            placeholder
            if let image {
                // Fill whatever frame the caller gives, so the credit sits in the
                // visible corner rather than off the edge of the scaled-to-fill image.
                Color.clear
                    .overlay { Image(uiImage: image).resizable().scaledToFill() }
                    .clipped()
                    .overlay(alignment: .topLeading) { attribution }
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
        if let name = photo.attribution {
            // A capsule chip that grows with the text up to the frame's width, then
            // cuts the text off at the end.
            Text(credit(name: name))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .tint(.white.opacity(0.9))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.black.opacity(0.45), in: .capsule)
                .padding(8)
        }
    }

    /// "Photo by Jane Doe on Unsplash", with the name linked to `attributionUrl`.
    private func credit(name: String) -> AttributedString {
        var text = AttributedString("Photo by ")
        var linkedName = AttributedString(name)
        linkedName.link = photo.attributionUrl
        text += linkedName
        text += AttributedString(" on Unsplash")
        return text
    }
}
