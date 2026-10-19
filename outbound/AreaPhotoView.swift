//
//  AreaPhotoView.swift
//  outbound
//

import SwiftUI

/// An area's Unsplash photo filling its frame, with the "Photo by … on Unsplash"
/// credit Unsplash requires as a chip in the top-leading corner. Tapping the chip asks
/// before opening the photographer's profile in the browser, when the server gives one
/// (the chip sits on a tappable card, so a stray tap shouldn't leave the app).
///
/// Shows `placeholder` while the image loads, fades the photo in over it once it
/// arrives, and keeps showing the placeholder if loading fails.
///
/// Images come through `PlaceImageCache`, so one already loaded this session shows
/// straight away with no placeholder or fade.
struct AreaPhotoView<Placeholder: View>: View {
    let photo: AreaPhoto
    @ViewBuilder var placeholder: Placeholder

    @State private var image: UIImage?
    @State private var confirmingProfile = false
    @Environment(\.openURL) private var openURL

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
            if let profile = photo.attributionUrl {
                chip(name: name)
                    // A high-priority tap, so it wins over the card's navigation link
                    // underneath (a nested Button doesn't).
                    .highPriorityGesture(TapGesture().onEnded { confirmingProfile = true })
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { confirmingProfile = true }
                    .accessibilityHint("Opens the photographer's profile in your browser")
                    .alert("Open in browser?", isPresented: $confirmingProfile) {
                        Button("Cancel", role: .cancel) {}
                        Button("Open") { openURL(profile) }
                    } message: {
                        Text("View \(name)'s profile on Unsplash.")
                    }
            } else {
                chip(name: name)
            }
        }
    }

    /// A capsule chip reading "Photo by Jane Doe on Unsplash" that grows with the text
    /// up to the frame's width, then cuts the text off at the end.
    private func chip(name: String) -> some View {
        Text("Photo by \(name) on Unsplash")
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.3), in: .capsule)
            .contentShape(.capsule)
            .padding(8)
    }
}
