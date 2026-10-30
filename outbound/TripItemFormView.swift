//
//  TripItemFormView.swift
//  outbound
//

import SwiftUI

/// Modal for manually adding or editing a trip item: opens the form for the item's
/// kind (`ActivityFormView`, `LodgingFormView` or `TransitFormView`), which share
/// their state through a `TripItemDraft` and their layout through `TripItemFormScaffold`.
///
/// Pass an existing `item` to edit it (its own kind wins); omit it to create a new
/// item of `kind`. A kind is fixed once the form is open.
struct TripItemFormView: View {
    @State private var draft: TripItemDraft

    /// Called with the created or updated item after a successful save.
    var onSaved: (TripItem) -> Void

    /// Called after the item being edited is deleted.
    var onDeleted: () -> Void

    /// - Parameters:
    ///   - defaultDate: The calendar day a new item's start defaults to (the day being
    ///     viewed when add was tapped); the time-of-day defaults to noon. `nil` falls back to now.
    ///   - viewedDay: The itinerary day the form was opened from, marked in the date
    ///     popup's calendar. For a new item it defaults to `defaultDate`.
    init(tripId: String, kind: TripItemKind = .activity, members: [TripMember] = [], tripDates: ClosedRange<Date>? = nil, item: TripItem? = nil, defaultDate: Date? = nil, viewedDay: Date? = nil, onSaved: @escaping (TripItem) -> Void = { _ in }, onDeleted: @escaping () -> Void = {}) {
        _draft = State(initialValue: TripItemDraft(tripId: tripId, kind: kind, members: members, tripDates: tripDates, item: item, defaultDate: defaultDate, viewedDay: viewedDay))
        self.onSaved = onSaved
        self.onDeleted = onDeleted
    }

    var body: some View {
        switch draft.kind {
        case .activity: ActivityFormView(draft: draft, onSaved: onSaved, onDeleted: onDeleted)
        case .lodging: LodgingFormView(draft: draft, onSaved: onSaved, onDeleted: onDeleted)
        case .transit: TransitFormView(draft: draft, onSaved: onSaved, onDeleted: onDeleted)
        }
    }
}

#Preview {
    TripItemFormView(tripId: "sample", kind: .transit, tripDates: .now ... .now.addingTimeInterval(3 * 86_400))
        .environment(AuthStore())
}
