//
//  ItineraryEntryCard.swift
//  outbound
//

import SwiftUI

/// One card in a day's itinerary, styled for the spot its entry stands for:
///
/// - a derived moment of an item (arrival, check-out) is a light compact card headed
///   "Arrival at <place>" / "Check-out from <place>", naming the item for reference;
/// - a layover is a light compact card with no title, just its details and the stop;
/// - other transit entries (departures) are a dark compact card under the booking's
///   title;
/// - everything else is a plain card — or, when its place has a photo, a cover card
///   topped by that photo.
///
/// `places` is the itinerary's single copy of each place, looked up by id, so a place
/// patched there updates every card showing it. `placeDetails` is its cache of Google
/// Place Details by google place id, preferred over the backend's place fields (which
/// are often still being enriched).
///
/// `membersSummary` (e.g. "You and 2 others") shows in a box under the kind label on
/// the item's own card, in place of the assignee avatar. Derived moments and layovers
/// don't show it. Nil keeps the avatar.
struct ItineraryEntryCard: View {
    let entry: ItineraryEntry
    let places: ItineraryPlaces
    let placeDetails: [String: PlaceDetails]
    var membersSummary: String? = nil
    /// How many are going, which picks the box's icon.
    var membersCount: Int = 0

    private var item: TripItem { entry.item }
    /// The place this entry is at, from the itinerary's shared copy.
    private var place: Place? { places.current(entry.place) }
    private var time: String { entry.timeText(.dateTime.hour().minute()) }

    var body: some View {
        switch entry.phase {
        case .arrival, .checkOut:
            derivedCard
        case .layover:
            compactCard(badge: badge, title: nil, detail: transitDetail, place: place, style: .light)
        default:
            if item.kind == .transit {
                compactCard(badge: badge, title: item.title, detail: transitDetail, place: place, showsMembers: true)
            } else if let photo = place?.coverPhoto {
                coverCard(photo)
            } else {
                plainCard
            }
        }
    }

    /// The label top-right of a card: the spot the entry stands for (e.g. "CHECK-IN"),
    /// else the item's first tag (e.g. "RESERVED"), else its kind.
    private var badge: String {
        (entry.phase?.label ?? item.tags.first ?? item.kind.label).uppercased()
    }

    // MARK: - Full-width cards

    /// The default full-width card: time + badge (with the members box under it) over
    /// the title in a short top section, then a faint rule and the info strip with the
    /// location — left off when there's nothing for the strip to show.
    private var plainCard: some View {
        VStack(spacing: 0) {
            // Sized to its content: a fixed gap above the title, then however many
            // lines the title takes. The gap shrinks when the members box already
            // spaces the title down.
            VStack(alignment: .leading, spacing: membersSummary == nil ? 30 : 12) {
                timeAndBadge()
                Text(item.title)
                    .font(.title3.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Color.appForeground)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsInfoStrip {
                // Inset to line up with the text above and below it.
                Rectangle()
                    .fill(Color.appForeground.opacity(0.3))
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                infoStrip
            }
        }
        .background(Color.appCard)
        .clipShape(.rect(cornerRadius: 16))
        .padding(.vertical, 6)
    }

    /// A full-width card for a place with a photo: the photo as a cover with time +
    /// badge overlaid and the title across its bottom, over the info strip.
    private func coverCard(_ photo: CoverPhoto) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                // The gradient shows while the photo loads, or if it fails to.
                PlacePhotoView(photo: photo) {
                    LinearGradient(colors: [.appCard, .appAccent], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                }
                .overlay(alignment: .top) {
                    timeAndBadge(tint: .white)
                        .foregroundStyle(.white)
                        .padding(14)
                }

                Text(item.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(14)
                    // Clear the photo credit along the cover's bottom edge.
                    .padding(.bottom, 8)
            }

            if showsInfoStrip {
                infoStrip
            }
        }
        .clipShape(.rect(cornerRadius: 16))
        .padding(.vertical, 6)
    }

    /// The row across the top of a full-width card: the time, and the badge opposite
    /// with the members box (if any) right under it.
    private func timeAndBadge(tint: Color = .appForeground) -> some View {
        HStack(alignment: .top) {
            Text(time)
                .monospacedDigit()
            Spacer()
            badgeAndMembers(badge, tint: tint)
        }
        .font(.caption.weight(.bold))
    }

    /// A card's badge, with the members box under it when there's a summary to show.
    private func badgeAndMembers(_ badge: String, tint: Color, lineLimit: Int? = nil) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            Text(badge)
                .tracking(1.5)
                .lineLimit(lineLimit)
            if let membersSummary {
                membersBox(membersSummary, tint: tint)
            }
        }
    }

    /// Whether a full-width card has an info strip: always while it holds the avatar,
    /// else only when there's a location to show.
    private var showsInfoStrip: Bool {
        membersSummary == nil || hasLocation(place, hidingName: item.title)
    }

    /// The bottom of a full-width card: the location, and an assignee avatar when the
    /// members box isn't standing in for it.
    private var infoStrip: some View {
        HStack {
            locationLabel(place, hidingName: item.title)
            Spacer()
            if membersSummary == nil {
                assigneeAvatar()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color.appCard)
    }

    // MARK: - Compact cards

    /// A derived moment of an item rather than the item itself: a light card headed by
    /// where it happens, with the item named top-right for reference — or its kind,
    /// when the name just repeats the place. A stay without a place falls back to its
    /// own name (that's where you're leaving).
    private var derivedCard: some View {
        let name = placeName(place) ?? (item.kind == .lodging ? item.title : nil)
        let phase = entry.phase?.label ?? item.kind.label
        // You arrive at a place but check out from one.
        let preposition = entry.phase == .checkOut ? "from" : "at"
        let reference = item.title == name ? item.kind.label : item.title
        return compactCard(
            badge: reference.uppercased(),
            title: name.map { "\(phase) \(preposition) \($0)" } ?? phase,
            detail: transitDetail,
            place: place,
            placeNameShown: name,
            style: .light
        )
    }

    /// The line under a transit card's title: at a layover the time on the ground and
    /// onward departure, then the leg's carrier and flight number. Nil when empty.
    private var transitDetail: String? {
        var details: [String] = []
        if entry.phase == .layover {
            if let minutes = entry.layoverMinutes {
                let duration = Duration.seconds(minutes * 60)
                details.append("\(duration.formatted(.units(allowed: [.hours, .minutes], width: .narrow))) layover")
            }
            if let departs = entry.layoverDepartureText(.dateTime.hour().minute()) {
                details.append("departs \(departs)")
            }
        }
        if let label = entry.segment?.label { details.append(label) }
        return details.isEmpty ? nil : details.joined(separator: " · ")
    }

    /// Colors for a compact card: the regular dark card, or a light one (90% white with
    /// near-black text) for derived moments and layovers.
    private struct CompactCardStyle {
        let background: Color
        let foreground: Color

        static let regular = CompactCardStyle(background: .appCard, foreground: .appForeground)
        static let light = CompactCardStyle(background: Color(white: 0.9), foreground: Color(white: 0.1))
    }

    /// A cover-less card: time + badge across the top, the title (if any) and an
    /// optional detail line, then a location row with the assignee avatar — or, when
    /// `showsMembers` and there's a summary, the members box under the badge instead.
    /// `placeNameShown` is a place name already in the title, so the location row
    /// doesn't repeat it (defaults to the title itself).
    private func compactCard(
        badge: String, title: String?, detail: String?, place: Place?,
        placeNameShown: String? = nil, style: CompactCardStyle = .regular, showsMembers: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(time)
                    .monospacedDigit()
                Spacer()
                if showsMembers {
                    badgeAndMembers(badge, tint: style.foreground, lineLimit: 1)
                } else {
                    Text(badge)
                        .tracking(1.5)
                        .lineLimit(1)
                }
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(style.foreground.opacity(0.7))

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(title)
                            .font(.title3.weight(.bold))
                    }
                    if let detail {
                        Text(detail)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(style.foreground.opacity(0.75))
                    }
                    locationLabel(place, hidingName: placeNameShown ?? title ?? "", foreground: style.foreground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // The members box up top stands in for the avatar.
                if !showsMembers || membersSummary == nil {
                    assigneeAvatar(tint: style.foreground)
                }
            }
        }
        .foregroundStyle(style.foreground)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.background, in: .rect(cornerRadius: 16))
        .padding(.vertical, 6)
    }

    // MARK: - Shared pieces

    /// A place's display name: the cached Google name, else the backend's.
    private func placeName(_ place: Place?) -> String? {
        place?.googlePlaceId.flatMap { placeDetails[$0] }?.name ?? place?.name
    }

    /// The name and address a card's location row shows: the name is dropped when it
    /// matches `hiddenName` (already shown elsewhere on the card).
    private func locationParts(_ place: Place?, hidingName hiddenName: String) -> (name: String?, address: String?) {
        let name = placeName(place).flatMap { $0 == hiddenName ? nil : $0 }
        let address = place?.googlePlaceId.flatMap { placeDetails[$0] }?.address ?? place?.address
        return (name, address)
    }

    private func hasLocation(_ place: Place?, hidingName hiddenName: String) -> Bool {
        let parts = locationParts(place, hidingName: hiddenName)
        return parts.name != nil || parts.address != nil
    }

    /// A card's location: the place name over its address, hidden when there's neither
    /// a name nor an address to show.
    @ViewBuilder
    private func locationLabel(_ place: Place?, hidingName hiddenName: String, foreground: Color = .appForeground) -> some View {
        let (name, address) = locationParts(place, hidingName: hiddenName)
        if name != nil || address != nil {
            VStack(alignment: .leading, spacing: 2) {
                if let name {
                    Text(name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(foreground)
                        .lineLimit(1)
                }
                if let address {
                    Text(address)
                        .font(.caption2)
                        .foregroundStyle(foreground.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Who the item is for, in very dark gray on a small box tinted to the card. Three or
    /// more add a plain plus snug against the two-person icon.
    private func membersBox(_ summary: String, tint: Color = .appForeground) -> some View {
        Label {
            Text(summary)
        } icon: {
            // Negative spacing tucks the plus into the symbol's trailing padding.
            HStack(spacing: -2) {
                Image(systemName: ItemMemberSelection.symbol(forCount: membersCount))
                if membersCount >= 3 {
                    Image(systemName: "plus")
                        .imageScale(.small)
                        .fontWeight(.heavy)
                }
            }
        }
        .font(.caption2.weight(.semibold))
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
        .foregroundStyle(Color(white: 0.15))
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        // Near-solid so the dark text reads over photos too.
        .background(tint.opacity(0.85), in: .rect(cornerRadius: 7))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Members: \(summary)")
    }

    /// The thin circular stand-in for an item's assignee avatar, stroked in `tint` so it
    /// reads on both dark and light cards.
    private func assigneeAvatar(tint: Color = .appForeground) -> some View {
        Circle()
            .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            .frame(width: 30, height: 30)
    }
}
