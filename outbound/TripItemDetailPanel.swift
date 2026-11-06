//
//  TripItemDetailPanel.swift
//  outbound
//

import SwiftUI
import MapKit

/// An item's details, folded open beneath its card in the itinerary: a soft
/// off-white panel that grows down out of the card's bottom edge, with the item's
/// details and an Edit button. Tapping the card again folds it away.
///
/// Square along the top and rounded along the bottom, so with the card's bottom
/// corners squared off too (`ItineraryEntryCard.isExpanded`) the two read as one
/// card. Its top sits up behind the card, so there's white behind the card's
/// corners while they animate square.
struct TripItemDetailPanel: View {
    let item: TripItem
    /// How far the panel's top sits up behind the card (see the static `anchor`);
    /// zero under a see-through card, where it would show through.
    var anchor: CGFloat = TripItemDetailPanel.anchor
    var onEdit: () -> Void

    private static let shape = UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)

    /// How far above its card's bottom edge the panel's top is pinned, hidden
    /// behind the card. The panel only grows downward from there, so as it opens
    /// (and the card's corners square off) there's always white under the seam.
    static let anchor: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            TripItemDetailContent(item: item)
            Button("Edit", action: onEdit)
                .buttonStyle(DarkPillButtonStyle())
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        // Clear the part hidden behind the card.
        .padding(.top, 20 + anchor)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(TripItemDetailContent.foreground)
        .tint(Color.appAccent)
        .background(TripItemDetailContent.background, in: Self.shape)
    }
}

/// Unfolds a view downward from its top edge: the top stays put and only the
/// visible height grows (or shrinks back), like a drawer opening, with nothing
/// sliding.
struct UnfoldTransition: Transition {
    func body(content: Content, phase: TransitionPhase) -> some View {
        content
            .mask(alignment: .top) {
                Rectangle()
                    .scaleEffect(x: 1, y: phase.isIdentity ? 1 : 0, anchor: .top)
            }
    }
}

/// The body of an item's details — badges, place(s), times, stay details, notes,
/// tags and source — shown in the inline panel under its itinerary card. Loads Google
/// Place Details for its place(s) itself.
struct TripItemDetailContent: View {
    let item: TripItem

    /// A soft off-white — 90% white so it reads as light without the glare of pure
    /// white — with near-black text for contrast.
    static let background = Color(white: 0.9)
    static let foreground = Color(white: 0.1)
    private let textColor = TripItemDetailContent.foreground

    /// Google Place Details for the item's place and (for transit) its destination,
    /// loaded on appear when a google place id is present.
    @State private var startDetails: PlaceDetails?
    @State private var endDetails: PlaceDetails?

    var body: some View {
        content
            .task(id: placeTaskKey) { await loadPlaceDetails() }
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

            if item.kind == .lodging {
                staySections(item.lodging ?? LodgingDetails(), rooms: item.rooms)
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

            sourceSection
        }
    }

    /// Where an imported item came from, and whether anyone has changed the booking
    /// since. Left out for one entered by hand.
    @ViewBuilder
    private var sourceSection: some View {
        if let label = item.source?.importLabel, let source = item.source {
            detailSection(title: "Source") {
                VStack(alignment: .leading, spacing: 2) {
                    Label(label, systemImage: source.systemImage)
                    if let edited = editedText {
                        Text(edited)
                            .font(.subheadline)
                            .foregroundStyle(textColor.opacity(0.7))
                    }
                }
            }
        }
    }

    /// "Edited since by Sam on Nov 5" (or without the name when nobody's known), or
    /// nil when the booking hasn't been changed since it was imported.
    private var editedText: String? {
        guard let editedAt = item.editedAt else { return nil }
        let day = editedAt.formatted(.dateTime.month(.abbreviated).day())
        if let name = item.editedBy?.displayName ?? item.editedBy?.email {
            return "Edited since by \(name) on \(day)"
        }
        return "Edited since on \(day)"
    }

    /// Kind and visibility badges across the top.
    private var header: some View {
        HStack(spacing: 8) {
            badge(item.kind.label.uppercased())
            if item.kind == .lodging, let type = item.lodging?.propertyType {
                badge(type.label.uppercased(), systemImage: type.systemImage)
            }
            badge(item.visibility.label.uppercased())
            Spacer()
        }
    }

    private func badge(_ text: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.bold))
        .tracking(1.5)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(textColor.opacity(0.1), in: .capsule)
    }

    private var tagChips: some View {
        HStack(spacing: 8) {
            ForEach(item.tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(textColor.opacity(0.1), in: .capsule)
            }
        }
    }

    /// A titled block: a small caption label above its content.
    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(textColor.opacity(0.6))
            content()
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Stay details

    /// What the booking says about a stay beyond its dates and place: its rooms, the
    /// free-cancellation deadline, and the property's own phone. Each block is left
    /// out when the booking doesn't state it.
    @ViewBuilder
    private func staySections(_ lodging: LodgingDetails, rooms: [LodgingRoom]) -> some View {
        if !rooms.isEmpty {
            detailSection(title: rooms.count == 1 ? "Room" : "Rooms") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(rooms.enumerated()), id: \.element.id) { index, room in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.title(number: index + 1))
                                .font(.body.weight(.semibold))
                            if let summary = room.summary {
                                Text(summary)
                                    .font(.subheadline)
                                    .foregroundStyle(textColor.opacity(0.7))
                            }
                        }
                    }
                }
            }
        }

        if let deadline = lodging.cancellationText(zone: item.startTimezone) {
            let passed = lodging.cancellationHasPassed(zone: item.startTimezone)
            detailSection(title: "Free cancellation") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(passed ? "Ended \(deadline)" : "Until \(deadline)")
                    if passed {
                        Text("Cancelling now may cost you.")
                            .font(.subheadline)
                            .foregroundStyle(textColor.opacity(0.7))
                    }
                }
            }
        }

        if let phone = lodging.phone, !phone.trimmingCharacters(in: .whitespaces).isEmpty {
            detailSection(title: "Property phone") {
                if let url = URL(string: "tel://\(phone.filter { !$0.isWhitespace })") {
                    Link(destination: url) { Label(phone, systemImage: "phone.fill") }
                } else {
                    Text(phone)
                }
            }
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
                if let name, name != item.displayTitle {
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
                                    Text("(\(count.formatted()))").foregroundStyle(textColor.opacity(0.6))
                                }
                            }
                        }
                    }
                    .font(.subheadline)
                }

                if let address {
                    Text(address).foregroundStyle(textColor.opacity(0.85))
                }

                if let details, !details.weekdayHours.isEmpty {
                    hoursDisclosure(details)
                }

                contactLinks(details)

                if let coordinate = coordinate(place: place, details: details) {
                    placeMap(coordinate: coordinate, name: name ?? place.name ?? item.displayTitle)
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
        .tint(textColor)
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

/// A compact button: light text on a dark pill, so it reads clearly against the
/// light panel background.
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
    ScrollView {
        TripItemDetailPanel(item: .sample, anchor: 0) {}
            .padding()
    }
    .background(Color.appBackground)
    .environment(AuthStore())
}
