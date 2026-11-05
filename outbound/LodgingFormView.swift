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
