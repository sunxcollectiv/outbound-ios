//
//  TransitFormView.swift
//  outbound
//

import SwiftUI

/// The form for adding or editing transit: an origin and a destination, each with its
/// own zone, so a leg can depart in one time zone and arrive in another.
struct TransitFormView: View {
    @Bindable var draft: TripItemDraft
    var onSaved: (TripItem) -> Void = { _ in }
    var onDeleted: () -> Void = {}

    var body: some View {
        TripItemFormScaffold(
            draft: draft,
            timeLabels: TripItemTimeLabels(start: "Departs", end: "Arrives", missingStart: "Add a departure time."),
            onSaved: onSaved,
            onDeleted: onDeleted
        ) {
            TripItemPlaceField(
                label: "Origin",
                placeholder: "Search origin",
                text: $draft.startPlaceText,
                place: $draft.startPlace,
                timeZone: $draft.startPlaceZone
            )
            TripItemPlaceField(
                label: "Destination",
                placeholder: "Search destination",
                text: $draft.endPlaceText,
                place: $draft.endPlace,
                timeZone: $draft.endPlaceZone
            )
        }
    }
}

#Preview {
    TransitFormView(draft: TripItemDraft(tripId: "sample", kind: .transit, tripDates: .now ... .now.addingTimeInterval(3 * 86_400)))
        .environment(AuthStore())
}
