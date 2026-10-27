//
//  LodgingPopup.swift
//  outbound
//

import SwiftUI

/// A centered card with what you need to get to a stay: its name and address, room
/// for the address in the local language, and links to it and directions in Google
/// Maps. Shown over the itinerary when its lodging bar is tapped.
struct LodgingPopup: View {
    let name: String
    let address: String?
    let googlePlaceId: String?
    let onEdit: () -> Void
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 4) {
                Label("Lodging", systemImage: "bed.double.fill")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                        .frame(width: 28, height: 28)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit Lodging")
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(name)
                    .font(.title3.bold())
                if let address {
                    Text(address)
                        .font(.subheadline)
                        .foregroundStyle(Color.appForeground.opacity(0.75))
                        .textSelection(.enabled)
                }
            }

            localAddressPlaceholder

            HStack(spacing: 10) {
                if let url = Self.viewURL(name: name, address: address, googlePlaceId: googlePlaceId) {
                    Button {
                        openURL(url)
                    } label: {
                        mapsButtonLabel("View in Google Maps", systemImage: "map.fill")
                            .foregroundStyle(Color.appForeground)
                            .background(Color.appForeground.opacity(0.12), in: .rect(cornerRadius: 10))
                    }
                }
                if let url = Self.directionsURL(name: name, address: address, googlePlaceId: googlePlaceId) {
                    Button {
                        openURL(url)
                    } label: {
                        mapsButtonLabel("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .foregroundStyle(Color(white: 0.15))
                            .background(Color.appForeground, in: .rect(cornerRadius: 10))
                    }
                }
            }
            // Both buttons as tall as the taller one.
            .fixedSize(horizontal: false, vertical: true)
            .buttonStyle(.plain)
        }
        .popupCard(onClose: onClose)
    }

    /// Icon over title, so a long title fits a half-width button.
    private func mapsButtonLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.body)
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }

    /// Where the address in the local language will go, for showing a driver.
    private var localAddressPlaceholder: some View {
        Text("Address in local language")
            .font(.caption)
            .foregroundStyle(Color.appForeground.opacity(0.5))
            .frame(maxWidth: .infinity, minHeight: 56)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.appForeground.opacity(0.3))
            }
    }
}

/// Google Maps links to a place, by its Google place id when there is one (so the exact
/// listing opens) with the name and address as the search text. They open the Google
/// Maps app when it's installed, the website otherwise.
extension LodgingPopup {
    /// The place's listing.
    static func viewURL(name: String, address: String?, googlePlaceId: String?) -> URL? {
        mapsURL(path: "search/", place: "query", placeId: "query_place_id", name: name, address: address, googlePlaceId: googlePlaceId)
    }

    /// Directions to the place. With no origin given, Maps starts from your current
    /// location.
    static func directionsURL(name: String, address: String?, googlePlaceId: String?) -> URL? {
        mapsURL(path: "dir/", place: "destination", placeId: "destination_place_id", name: name, address: address, googlePlaceId: googlePlaceId)
    }

    private static func mapsURL(path: String, place: String, placeId: String, name: String, address: String?, googlePlaceId: String?) -> URL? {
        var components = URLComponents(string: "https://www.google.com/maps/\(path)")
        var items = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: place, value: [name, address].compactMap { $0 }.joined(separator: ", ")),
        ]
        if let googlePlaceId {
            items.append(URLQueryItem(name: placeId, value: googlePlaceId))
        }
        components?.queryItems = items
        return components?.url
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        LodgingPopup(
            name: "W Melbourne",
            address: "408 Flinders Ln, Melbourne VIC 3000, Australia",
            googlePlaceId: nil,
            onEdit: {},
            onClose: {}
        )
    }
}
