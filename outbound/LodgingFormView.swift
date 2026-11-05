//
//  LodgingFormView.swift
//  outbound
//

import SwiftUI

/// The form for adding or editing a lodging: what kind of place it is (hotel,
/// vacation rental, …), where you're staying, as a picked place or a name taken as
/// typed (which becomes its title), then check-in and check-out.
struct LodgingFormView: View {
    @Bindable var draft: TripItemDraft
    var onSaved: (TripItem) -> Void = { _ in }
    var onDeleted: () -> Void = {}

    @State private var showingRoomDetails = false

    /// "+ add room": a point under subheadline (15pt), scaled with Dynamic Type.
    @ScaledMetric(relativeTo: .subheadline) private var addRoomSize: CGFloat = 14

    var body: some View {
        TripItemFormScaffold(
            draft: draft,
            timeLabels: TripItemTimeLabels(start: "Check-in", end: "Check-out", missingStart: "Add a check-in time."),
            onSaved: onSaved,
            onDeleted: onDeleted
        ) {
            propertyTypePicker
            TripItemPlaceField(
                placeholder: "Search a place",
                text: $draft.startPlaceText,
                place: $draft.startPlace,
                timeZone: $draft.startPlaceZone,
                typedEntry: $draft.typedName
            )
        } afterTimes: {
            roomsSection
        }
        .overlay { roomDetailsPopup }
    }

    // MARK: - Room details

    /// "Room details" with "+ add room" opposite, over a full-width row per room, or
    /// a dashed placeholder while the stay has none. Adding a room or tapping one
    /// opens the room details popup.
    private var roomsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Room details")
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground.opacity(0.8))
                Spacer(minLength: 8)
                Button(action: openRoomDetails) {
                    // The plus snug against the words, rather than a label's wide gap.
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                        Text("add room")
                    }
                    .font(.system(size: addRoomSize, weight: .semibold))
                    .foregroundStyle(Color.appForeground)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add room")
            }
            if draft.rooms.isEmpty {
                roomsPlaceholder
            } else {
                ForEach(Array(draft.rooms.enumerated()), id: \.element.id) { index, room in
                    roomButton(room, number: index + 1)
                }
            }
        }
    }

    /// One room, styled like the members row up top: its name, and its type and
    /// guests opposite.
    private func roomButton(_ room: LodgingRoom, number: Int) -> some View {
        Button(action: openRoomDetails) {
            HStack(spacing: 12) {
                Text(room.title(number: number))
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if let summary = room.summary {
                    Text(summary)
                        .foregroundStyle(Color.appForeground.opacity(0.75))
                        .lineLimit(1)
                }
            }
            .padding(14)
            .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Stands in for the rooms until the stay has one: a dashed outline the height of
    /// a room row. Not a button; rooms are added from "+ add room" above it.
    private var roomsPlaceholder: some View {
        Text("No room details yet")
            .foregroundStyle(Color.appForeground.opacity(0.5))
            .frame(maxWidth: .infinity)
            .padding(14)
            .overlay {
                RoundedRectangle(cornerRadius: appFieldCornerRadius)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.appForeground.opacity(0.3))
            }
    }

    private func openRoomDetails() {
        withAnimation(.snappy(duration: 0.25)) { showingRoomDetails = true }
    }

    private func closeRoomDetails() {
        withAnimation(.snappy(duration: 0.2)) { showingRoomDetails = false }
    }

    /// The room details popup over a dimmed form; tapping outside closes it. Blank
    /// for now, until it holds a room's details.
    @ViewBuilder
    private var roomDetailsPopup: some View {
        if showingRoomDetails {
            DimmedPopup(onClose: closeRoomDetails) {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .popupCard(background: .black, onClose: closeRoomDetails)
                    .accessibilityLabel("Room details")
            }
        }
    }

    /// One tile per property type, icon over name; the picked one is lit. Tapping it
    /// again clears it, since a stay needn't say.
    private var propertyTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(LodgingType.allCases) { type in
                let isPicked = draft.propertyType == type
                Button {
                    withAnimation(.snappy(duration: 0.15)) {
                        draft.propertyType = isPicked ? nil : type
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: type.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            // One height for every icon, so the names line up.
                            .frame(height: 20)
                        Text(type.shortLabel)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(isPicked ? Color.black : Color.appForeground.opacity(0.8))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(
                        isPicked ? Color.appForeground : Color.appForeground.opacity(0.08),
                        in: .rect(cornerRadius: appFieldCornerRadius)
                    )
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(type.label)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
        }
    }
}

#Preview {
    LodgingFormView(draft: TripItemDraft(tripId: "sample", kind: .lodging, tripDates: .now ... .now.addingTimeInterval(3 * 86_400)))
        .environment(AuthStore())
}
