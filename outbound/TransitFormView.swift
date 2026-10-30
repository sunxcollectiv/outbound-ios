//
//  TransitFormView.swift
//  outbound
//

import SwiftUI

/// The form for adding or editing transit: an origin and a destination, each with its
/// own zone, so a leg can depart in one time zone and arrive in another. No title:
/// the server names it from its route.
struct TransitFormView: View {
    @Bindable var draft: TripItemDraft
    var onSaved: (TripItem) -> Void = { _ in }
    var onDeleted: () -> Void = {}

    /// Width of the origin/destination row, so each field's suggestions can span it.
    @State private var rowWidth: CGFloat?

    var body: some View {
        TripItemFormScaffold(
            draft: draft,
            timeLabels: TripItemTimeLabels(start: "Departs", end: "Arrives", missingStart: "Add a departure time."),
            onSaved: onSaved,
            onDeleted: onDeleted
        ) {
            VStack(alignment: .leading, spacing: 16) {
                modePicker

                // Side by side, with suggestions floating over the form across the whole
                // row (from the origin's left edge, or the destination's right).
                HStack(alignment: .top, spacing: 8) {
                    TripItemPlaceField(
                        label: "Origin",
                        placeholder: "Search",
                        text: $draft.startPlaceText,
                        place: $draft.startPlace,
                        timeZone: $draft.startPlaceZone,
                        floatingResults: .init(width: rowWidth, edge: .leading)
                    )
                    TripItemPlaceField(
                        label: "Destination",
                        placeholder: "Search",
                        text: $draft.endPlaceText,
                        place: $draft.endPlace,
                        timeZone: $draft.endPlaceZone,
                        floatingResults: .init(width: rowWidth, edge: .trailing)
                    )
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            }
        }
    }

    /// A row of icons, one per way to travel; the picked one is lit.
    private var modePicker: some View {
        HStack(spacing: 8) {
            ForEach(TransitMode.pickable) { mode in
                let isPicked = draft.transitMode == mode
                Button {
                    withAnimation(.snappy(duration: 0.15)) { draft.transitMode = mode }
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
