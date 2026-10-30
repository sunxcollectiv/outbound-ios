//
//  LodgingFormView.swift
//  outbound
//

import SwiftUI

/// The form for adding or editing a lodging: where you're staying, as a picked place
/// or a name taken as typed (which becomes its title), then check-in and check-out.
struct LodgingFormView: View {
    @Bindable var draft: TripItemDraft
    var onSaved: (TripItem) -> Void = { _ in }
    var onDeleted: () -> Void = {}

    var body: some View {
        TripItemFormScaffold(
            draft: draft,
            timeLabels: TripItemTimeLabels(start: "Check-in", end: "Check-out", missingStart: "Add a check-in time."),
            onSaved: onSaved,
            onDeleted: onDeleted
        ) {
            TripItemPlaceField(
                placeholder: "Search a place",
                text: $draft.startPlaceText,
                place: $draft.startPlace,
                timeZone: $draft.startPlaceZone,
                typedEntry: $draft.typedName
            )
        }
    }
}

#Preview {
    LodgingFormView(draft: TripItemDraft(tripId: "sample", kind: .lodging, tripDates: .now ... .now.addingTimeInterval(3 * 86_400)))
        .environment(AuthStore())
}
