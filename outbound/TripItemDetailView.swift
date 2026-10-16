//
//  TripItemDetailView.swift
//  outbound
//

import SwiftUI
import MapKit

/// A sheet showing the details of a single trip item — an activity, a piece of
/// lodging, or a transit leg.
///
/// For now the layout is generic across all three kinds. The `content` switch is
/// the seam for later: each `TripItemKind` will grow its own tailored layout
/// (e.g. check-in/check-out emphasis for lodging, route/leg details for transit).
struct TripItemDetailView: View {
    @State private var item: TripItem

    /// Called with the updated item after an edit is saved, so the presenter can
    /// refresh its itinerary.
    var onSaved: (TripItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var showingEdit = false

    /// Google Place Details for the item's place and (for transit) its destination,
    /// loaded on appear when a google place id is present.
    @State private var startDetails: PlaceDetails?
    @State private var endDetails: PlaceDetails?

    /// A soft off-white sheet — 90% white so it reads as light without the glare
    /// of pure white — with near-black text for contrast.
    private let sheetBackground = Color(white: 0.9)
    private let sheetForeground = Color(white: 0.1)

    init(item: TripItem, onSaved: @escaping (TripItem) -> Void = { _ in }) {
        _item = State(initialValue: item)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            ZStack {
                sheetBackground.ignoresSafeArea()
                ScrollView {
                    content
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(sheetForeground)
            .tint(Color.appAccent)
            .task(id: placeTaskKey) { await loadPlaceDetails() }
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(sheetBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Edit") { showingEdit = true }
                        .buttonStyle(DarkPillButtonStyle())
                }
                .sharedBackgroundVisibility(.hidden)
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .buttonStyle(DarkPillButtonStyle())
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        .presentationBackground(sheetBackground)
        .sheet(isPresented: $showingEdit) {
            TripItemFormView(tripId: item.tripId, item: item) { updated in
                item = updated
                onSaved(updated)
            }
        }
    }

    /// The per-kind body. Every kind currently funnels to the same generic layout;
    /// this switch is where activity / lodging / transit layouts will diverge.
    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .activity, .lodging, .transit:
            genericDetail
        }
    }

    // MARK: - Generic layout

    private var genericDetail: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            if item.kind == .transit {
                if let place = item.place {
                    placeSection(title: "From", place: place, details: startDetails)
                }
                if let endPlace = item.endPlace {
                    placeSection(title: "To", place: endPlace, details: endDetails)
                }
            } else if let place = item.place {
                placeSection(title: "Location", place: place, details: startDetails)
            }

            detailSection(title: startLabel) {
                Text([item.startText(.dateTime.weekday().month().day().hour().minute()), item.startZoneAbbreviation].compactMap { $0 }.joined(separator: " "))
            }

            if let endText = item.endText(.dateTime.weekday().month().day().hour().minute()) {
                detailSection(title: endLabel) {
                    Text([endText, item.endZoneAbbreviation].compactMap { $0 }.joined(separator: " "))
                }
            }

            if let notes = item.notes, !notes.isEmpty {
                detailSection(title: "Notes") {
                    Text(notes)
                }
            }

            if !item.tags.isEmpty {
                detailSection(title: "Tags") {
                    tagChips
                }
            }
        }
    }

    /// Kind and scope badges across the top.
    private var header: some View {
        HStack(spacing: 8) {
            badge(item.kind.label.uppercased())
            badge(item.scope.label.uppercased())
            Spacer()
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(1.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(sheetForeground.opacity(0.1), in: .capsule)
    }

    private var tagChips: some View {
        HStack(spacing: 8) {
            ForEach(item.tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(sheetForeground.opacity(0.1), in: .capsule)
            }
        }
    }

    /// A titled block: a small caption label above its content.
    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(sheetForeground.opacity(0.6))
            content()
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var startLabel: String { item.kind == .lodging ? "Check-in" : "Starts" }
    private var endLabel: String { item.kind == .lodging ? "Check-out" : "Ends" }

    // MARK: - Place details

    /// Changes whenever the item's place(s) change, so the loader re-runs after an edit.
    private var placeTaskKey: String {
        "\(item.place?.id ?? "")|\(item.endPlace?.id ?? "")"
    }

    /// Loads Google Place Details for whichever places have a google place id. Failures
    /// are ignored — the section falls back to the stored place fields.
    private func loadPlaceDetails() async {
        startDetails = nil
        endDetails = nil
        if let gid = item.place?.googlePlaceId {
            startDetails = try? await GooglePlacesClient.shared.placeDetails(placeId: gid)
        }
        if item.kind == .transit, let gid = item.endPlace?.googlePlaceId {
            endDetails = try? await GooglePlacesClient.shared.placeDetails(placeId: gid)
        }
    }

    /// A place block: name, type, rating, address, hours, and contact links. Uses live
    /// Google details when available, otherwise the place's stored fields.
    @ViewBuilder
    private func placeSection(title: String, place: Place, details: PlaceDetails?) -> some View {
        let name = details?.name ?? place.name
        let address = details?.address ?? place.address

        detailSection(title: title) {
            VStack(alignment: .leading, spacing: 10) {
                if let name, name != item.title {
                    Text(name).font(.body.weight(.semibold))
                }

                if details?.typeLabel != nil || details?.rating != nil {
                    HStack(spacing: 10) {
                        if let type = details?.typeLabel {
                            Text(type)
                        }
                        if let rating = details?.rating {
                            HStack(spacing: 3) {
                                Image(systemName: "star.fill").foregroundStyle(.yellow)
                                Text(String(format: "%.1f", rating))
                                if let count = details?.userRatingCount {
                                    Text("(\(count.formatted()))").foregroundStyle(sheetForeground.opacity(0.6))
                                }
                            }
                        }
                    }
                    .font(.subheadline)
                }

                if let address {
                    Text(address).foregroundStyle(sheetForeground.opacity(0.85))
                }

                if let details, !details.weekdayHours.isEmpty {
                    hoursDisclosure(details)
                }

                contactLinks(details)

                if let coordinate = coordinate(place: place, details: details) {
                    placeMap(coordinate: coordinate, name: name ?? place.name ?? item.title)
                }
            }
        }
    }

    /// Prefers Google's coordinates (reliably present) and falls back to the
    /// backend-enriched place coordinates when details haven't loaded.
    private func coordinate(place: Place, details: PlaceDetails?) -> CLLocationCoordinate2D? {
        if let lat = details?.latitude, let lon = details?.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        if let lat = place.latitude, let lon = place.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }

    /// A compact, non-interactive map pinning the place.
    private func placeMap(coordinate: CLLocationCoordinate2D, name: String) -> some View {
        Map(initialPosition: .region(MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))) {
            Marker(name, coordinate: coordinate)
                .tint(Color.appAccent)
        }
        .frame(height: 180)
        .clipShape(.rect(cornerRadius: 12))
        .allowsHitTesting(false)
    }

    private func hoursDisclosure(_ details: PlaceDetails) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(details.weekdayHours, id: \.self) { line in
                    Text(line).font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            HStack(spacing: 8) {
                Text("Hours").font(.subheadline.weight(.medium))
                if let openNow = details.openNow {
                    Text(openNow ? "Open now" : "Closed")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background((openNow ? Color.green : Color.red).opacity(0.18), in: .capsule)
                        .foregroundStyle(openNow ? Color.green : Color.red)
                }
            }
        }
        .tint(sheetForeground)
    }

    @ViewBuilder
    private func contactLinks(_ details: PlaceDetails?) -> some View {
        if let phone = details?.phone,
           let url = URL(string: "tel://\(phone.filter { !$0.isWhitespace })") {
            Link(destination: url) { Label(phone, systemImage: "phone.fill") }
                .font(.subheadline)
        }
        if let website = details?.website, let url = URL(string: website) {
            Link(destination: url) { Label("Website", systemImage: "globe") }
                .font(.subheadline)
        }
        if let maps = details?.mapsURL, let url = URL(string: maps) {
            Link(destination: url) { Label("Open in Google Maps", systemImage: "map.fill") }
                .font(.subheadline)
        }
    }
}

/// A compact toolbar button: light text on a dark pill, so the top actions read
/// clearly against the light sheet background.
private struct DarkPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .fixedSize()
            .foregroundStyle(Color(white: 0.95))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Color(white: 0.15), in: .capsule)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

#Preview {
    TripItemDetailView(item: .sample)
}
