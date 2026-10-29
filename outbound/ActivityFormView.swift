//
//  ActivityFormView.swift
//  outbound
//

import SwiftUI

/// The form for adding or editing an activity: one place, a start, and an optional end.
struct ActivityFormView: View {
    @Bindable var draft: TripItemDraft
    var onSaved: (TripItem) -> Void = { _ in }
    var onDeleted: () -> Void = {}

    var body: some View {
        TripItemFormScaffold(
            draft: draft,
            timeLabels: TripItemTimeLabels(start: "Starts", end: "Ends", missingStart: "Add a start time.", endIsOptional: true),
            onSaved: onSaved,
            onDeleted: onDeleted
        ) {
            TripItemPlaceField(
                placeholder: "Search a place",
                text: $draft.startPlaceText,
                place: $draft.startPlace,
                timeZone: $draft.startPlaceZone
            )
        }
    }
}

#Preview {
    ActivityFormView(draft: TripItemDraft(tripId: "sample", kind: .activity, tripDates: .now ... .now.addingTimeInterval(3 * 86_400)))
        .environment(AuthStore())
}
