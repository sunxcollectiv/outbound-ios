//
//  BookingChangePopup.swift
//  outbound
//

import SwiftUI

/// Asks before changing a booked stay's dates or number of rooms, or deleting it:
/// the itinerary changes, but the real booking with the property doesn't, so the
/// user confirms they've already made the change there. Not asked for stays marked
/// Other, which have no booking behind them.
struct BookingChangePopup: View {
    enum Change: Equatable {
        /// The check-in or check-out date moved, the number of rooms changed, or both.
        case edit(dates: Bool, rooms: Bool)
        case delete

        /// What an edit to a stay asks about, or nil when it changes neither.
        static func edit(changingDates dates: Bool, rooms: Bool) -> Change? {
            dates || rooms ? .edit(dates: dates, rooms: rooms) : nil
        }
    }

    let change: Change
    let onConfirm: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Your Booking", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.appForeground.opacity(0.6))

            VStack(alignment: .leading, spacing: 6) {
                Text(question)
                    .font(.headline)
                Text(explanation)
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onConfirm) {
                Text(confirmTitle)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(change == .delete ? Color.appError : Color.appBackground, in: .rect(cornerRadius: appFieldCornerRadius))
            }
            .buttonStyle(.plain)
            .requiresConnection()
            .padding(.top, 4)
        }
        .popupCard(onClose: onClose)
    }

    var question: String {
        switch change {
        case .edit(dates: true, rooms: false): "Change this stay's dates?"
        case .edit(dates: false, rooms: true): "Change the number of rooms?"
        case .edit: "Change this stay's dates and rooms?"
        case .delete: "Delete this stay?"
        }
    }

    var explanation: String {
        switch change {
        case .edit(let dates, let rooms):
            let what = dates && rooms ? "new dates and rooms have" : dates ? "new dates have" : "new number of rooms has"
            return "This only updates your itinerary. It won't change your actual booking, so make sure the \(what) already been confirmed with the property."
        case .delete:
            return "This only removes it from your itinerary. It won't cancel your actual booking, so make sure it's already been cancelled with the property."
        }
    }

    var confirmTitle: String {
        switch change {
        case .edit: "Changed with Property"
        case .delete: "Cancelled with Property"
        }
    }
}

#Preview("Dates") {
    DimmedPopup(onClose: {}) {
        BookingChangePopup(change: .edit(dates: true, rooms: false), onConfirm: {}, onClose: {})
    }
}

#Preview("Delete") {
    DimmedPopup(onClose: {}) {
        BookingChangePopup(change: .delete, onConfirm: {}, onClose: {})
    }
}
