//
//  TransitFormView.swift
//  outbound
//

import SwiftUI

/// The form for adding or editing transit: one or more legs, each with how it
/// travels, an origin and a destination, and when it departs and arrives (each end
/// in its own zone, so a leg can cross zones). No title: the server names it from
/// its route.
struct TransitFormView: View {
    @Bindable var draft: TripItemDraft
    var onSaved: (TripItem) -> Void = { _ in }
    var onDeleted: () -> Void = {}

    /// The leg and end whose date popup is open, if any.
    @State private var editingTime: EditingTime?

    private struct EditingTime {
        let legID: TransitLeg.ID
        let field: DateTimePopup.Field
    }

    var body: some View {
        TripItemFormScaffold(
            draft: draft,
            timeLabels: TripItemTimeLabels(start: "Departs", end: "Arrives", missingStart: "Add a departure time."),
            onSaved: onSaved,
            onDeleted: onDeleted
        ) {
            VStack(alignment: .leading, spacing: 28) {
                ForEach(Array(draft.legs.enumerated()), id: \.element.id) { index, leg in
                    // A faint rule between legs.
                    if index > 0 {
                        Rectangle()
                            .fill(Color.appForeground.opacity(0.12))
                            .frame(height: 1)
                            .accessibilityHidden(true)
                    }
                    TransitLegSection(
                        leg: leg,
                        // Numbered only once there's more than one.
                        number: draft.legs.count > 1 ? index + 1 : nil,
                        onDelete: { withAnimation(.snappy(duration: 0.25)) { draft.removeLeg(leg) } },
                        onEditTime: { field in
                            withAnimation(.snappy(duration: 0.25)) { editingTime = EditingTime(legID: leg.id, field: field) }
                        }
                    )
                    // Earlier legs over later ones, so their floating suggestions show.
                    .zIndex(Double(draft.legs.count - index))
                }

                addLegButton
                    // Twice the form's usual gap before the notes below.
                    .padding(.bottom, 20)
            }
        }
        .overlay { timePickerPopup }
        .offlinePillNearBottom(isActive: editingTime != nil)
    }

    private var addLegButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { draft.addLeg() }
        } label: {
            Label("Add transit leg", systemImage: "plus")
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .overlay {
                    RoundedRectangle(cornerRadius: appFieldCornerRadius)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        .foregroundStyle(Color.appForeground.opacity(0.5))
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.appForeground.opacity(0.8))
    }

    private func closeTimePicker() {
        withAnimation(.snappy(duration: 0.2)) { editingTime = nil }
    }

    /// The date popup for the tapped leg's departure or arrival, over a dimmed form.
    @ViewBuilder
    private var timePickerPopup: some View {
        if let editingTime, let leg = draft.legs.first(where: { $0.id == editingTime.legID }) {
            @Bindable var leg = leg
            DimmedPopup(onClose: closeTimePicker) {
                DateTimePopup(
                    field: editingTime.field,
                    startPlaceholder: "Departs",
                    endPlaceholder: "Arrives",
                    tripDates: draft.tripDates,
                    start: $leg.startsAt,
                    end: $leg.endsAt,
                    startZone: $leg.startZone,
                    endZone: $leg.endZone,
                    viewedDay: draft.viewedDay,
                    onClose: closeTimePicker
                )
            }
        }
    }
}

/// One leg of a transit: a "Segment N" tag with a delete button when there are
/// several, then the ways to travel, the origin and destination side by side, and
/// when it departs and arrives.
private struct TransitLegSection: View {
    @Bindable var leg: TransitLeg
    /// The leg's number, shown with a delete button; nil for a lone leg.
    let number: Int?
    let onDelete: () -> Void
    let onEditTime: (DateTimePopup.Field) -> Void

    /// Width of the origin/destination row, so each field's suggestions can span it.
    @State private var rowWidth: CGFloat?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let number {
                header(number)
            }

            modePicker

            // Side by side, with suggestions floating over the form across the whole
            // row (from the origin's left edge, or the destination's right).
            HStack(alignment: .top, spacing: 8) {
                TripItemPlaceField(
                    label: "Origin",
                    placeholder: "Search",
                    text: $leg.startPlaceText,
                    place: $leg.startPlace,
                    timeZone: $leg.startPlaceZone,
                    floatingResults: .init(width: rowWidth, edge: .leading)
                )
                TripItemPlaceField(
                    label: "Destination",
                    placeholder: "Search",
                    text: $leg.endPlaceText,
                    place: $leg.endPlace,
                    timeZone: $leg.endPlaceZone,
                    floatingResults: .init(width: rowWidth, edge: .trailing)
                )
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            // Over the times below, so the suggestions cover them.
            .zIndex(1)

            HStack(spacing: 8) {
                TripItemTimeBlock(title: "Departs", placeholder: "Add start", date: $leg.startsAt, zone: $leg.startZone) {
                    onEditTime(.start)
                }
                TripItemTimeBlock(title: "Arrives", placeholder: "Add end", date: $leg.endsAt, zone: $leg.endZone) {
                    onEditTime(.end)
                }
            }
        }
    }

    /// The leg's number as a tag, with an inline delete on the right.
    private func header(_ number: Int) -> some View {
        HStack {
            Text("Segment \(number)")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.appForeground.opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.appForeground.opacity(0.12), in: .capsule)
            Spacer()
            Button("Delete", action: onDelete)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color.appError)
                .buttonStyle(.plain)
                .accessibilityLabel("Delete segment \(number)")
        }
    }

    /// A row of icons, one per way to travel; the picked one is lit.
    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(TransitMode.pickable) { mode in
                let isPicked = leg.transitMode == mode
                Button {
                    withAnimation(.snappy(duration: 0.15)) { leg.transitMode = mode }
                } label: {
                    Image(systemName: mode.systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isPicked ? Color.black : Color.appForeground.opacity(0.8))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            isPicked ? Color.appForeground : Color.appForeground.opacity(0.08),
                            in: .rect(cornerRadius: appFieldCornerRadius)
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(mode.label)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
        }
    }
}

#Preview {
    TransitFormView(draft: TripItemDraft(tripId: "sample", kind: .transit, tripDates: .now ... .now.addingTimeInterval(3 * 86_400)))
        .environment(AuthStore())
}
