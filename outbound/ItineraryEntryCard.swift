//
//  ItineraryEntryCard.swift
//  outbound
//

import SwiftUI

/// One card in a day's itinerary, styled for the spot its entry stands for:
///
/// - a derived moment of an item (arrival, check-out) is a light compact card headed
///   "Arrival at <place>" / "Check-out from <place>", naming the item for reference;
/// - other transit entries (departure, layover) are a dark compact card under the
///   booking's title;
/// - everything else is a cover card with artwork.
///
/// `placeDetails` is the itinerary's cache of Google Place Details by google place id,
/// preferred over the backend's place fields (which are often still being enriched).
struct ItineraryEntryCard: View {
    let entry: ItineraryEntry
    let placeDetails: [String: PlaceDetails]

    private var item: TripItem { entry.item }
    private var time: String { entry.timeText(.dateTime.hour().minute()) }

    var body: some View {
        switch entry.phase {
        case .arrival, .checkOut:
            derivedCard
        default:
            if item.kind == .transit {
                compactCard(badge: badge, title: item.title, detail: transitDetail, place: entry.place)
            } else {
                coverCard
            }
        }
    }

    /// The label top-right of a card: the spot the entry stands for (e.g. "CHECK-IN"),
    /// else the item's first tag (e.g. "RESERVED"), else its kind.
    private var badge: String {
        (entry.phase?.label ?? item.tags.first ?? item.kind.label).uppercased()
    }

    // MARK: - Cover card

    /// A full-width card: a cover (a placeholder until per-item artwork is wired up)
    /// with time + badge overlaid and the title across its bottom, over an info strip
    /// with the location and an assignee avatar.
    private var coverCard: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                Image("DummyCover")
                    .resizable()
                    .scaledToFill()
                    .frame(height: 170)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .overlay {
                        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                    }
                    .overlay(alignment: .top) {
                        HStack {
                            Text(time)
                                .monospacedDigit()
                            Spacer()
                            Text(badge)
                                .tracking(1.5)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(14)
                    }

                Text(item.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(14)
            }

            HStack {
                locationLabel(entry.place, hidingName: item.title)
                Spacer()
                assigneeAvatar()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.appCard)
        }
        .clipShape(.rect(cornerRadius: 16))
        .padding(.vertical, 6)
    }

    // MARK: - Compact cards

    /// A derived moment of an item rather than the item itself: a light card headed by
    /// where it happens, with the item named top-right for reference — or its kind,
    /// when the name just repeats the place. A stay without a place falls back to its
    /// own name (that's where you're leaving).
    private var derivedCard: some View {
        let place = placeName(entry.place) ?? (item.kind == .lodging ? item.title : nil)
        let phase = entry.phase?.label ?? item.kind.label
        // You arrive at a place but check out from one.
        let preposition = entry.phase == .checkOut ? "from" : "at"
        let reference = item.title == place ? item.kind.label : item.title
        return compactCard(
            badge: reference.uppercased(),
            title: place.map { "\(phase) \(preposition) \($0)" } ?? phase,
            detail: transitDetail,
            place: entry.place,
            placeNameShown: place,
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
    /// near-black text) for derived moments.
    private struct CompactCardStyle {
        let background: Color
        let foreground: Color

        static let regular = CompactCardStyle(background: .appCard, foreground: .appForeground)
        static let light = CompactCardStyle(background: Color(white: 0.9), foreground: Color(white: 0.1))
    }

    /// A cover-less card: time + badge across the top, the title and an optional detail
    /// line, then a location row with the assignee avatar. `placeNameShown` is a place
    /// name already in the title, so the location row doesn't repeat it (defaults to
    /// the title itself).
    private func compactCard(
        badge: String, title: String, detail: String?, place: Place?,
        placeNameShown: String? = nil, style: CompactCardStyle = .regular
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(time)
                    .monospacedDigit()
                Spacer()
                Text(badge)
                    .tracking(1.5)
                    .lineLimit(1)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(style.foreground.opacity(0.7))

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(.title3.weight(.bold))
                    if let detail {
                        Text(detail)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(style.foreground.opacity(0.75))
                    }
                    locationLabel(place, hidingName: placeNameShown ?? title, foreground: style.foreground)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                assigneeAvatar(tint: style.foreground)
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

    /// A card's location: the place name over its address. The name is dropped when it
    /// matches `hiddenName` (already shown elsewhere on the card), and the whole row is
    /// hidden when there's neither a name nor an address to show.
    @ViewBuilder
    private func locationLabel(_ place: Place?, hidingName hiddenName: String, foreground: Color = .appForeground) -> some View {
        let name = placeName(place).flatMap { $0 == hiddenName ? nil : $0 }
        let address = place?.googlePlaceId.flatMap { placeDetails[$0] }?.address ?? place?.address
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

    /// The thin circular stand-in for an item's assignee avatar, stroked in `tint` so it
    /// reads on both dark and light cards.
    private func assigneeAvatar(tint: Color = .appForeground) -> some View {
        Circle()
            .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            .frame(width: 30, height: 30)
    }
}
