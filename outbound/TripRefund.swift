//
//  TripRefund.swift
//  outbound
//

import SwiftUI

/// Credits a change to a trip gives back: what's refunded, or that nothing is because
/// the refund window has closed (a day after the trip starts).
struct TripRefund: Equatable {
    let cents: Int
    /// Credits were paid for the trip, but it's too late to get them back.
    var windowClosed = false

    /// Whether there's anything to tell the user.
    var isWorthShowing: Bool { cents > 0 || windowClosed }
}

extension TripQuote {
    /// What deleting the trip as it stands gives back: everything paid for it, while
    /// the refund window is open.
    var deleteRefund: TripRefund {
        let paid = paidCents ?? 0
        return refundWindowOpen == false
            ? TripRefund(cents: 0, windowClosed: paid > 0)
            : TripRefund(cents: paid)
    }

    /// What saving this edit gives back.
    var editRefund: TripRefund { TripRefund(cents: refundCents) }
}

extension TripsAPI {
    /// What deleting the trip would refund, from a quote for the trip as it stands
    /// (its own dates, not its group's span). Nothing is saved.
    static func deleteRefund(tripId: String, api: APIClient = .shared) async throws -> TripRefund {
        let trip = try await api.send(read(id: tripId), as: Trip.self)
        let body = CreateRequest(title: trip.title, description: trip.description, startDate: trip.startDate, endDate: trip.endDate)
        return try await api.send(quote(id: tripId, body), as: TripQuote.self).deleteRefund
    }
}

/// The part of a popup that says what credits come back from deleting or shortening a
/// trip, and where they go. Shown in `DeleteTripPopup` and `RefundConfirmationPopup`.
struct TripRefundSection: View {
    enum Reason {
        case delete, edit
    }

    let refund: TripRefund
    let reason: Reason
    /// The trip owner's name when they aren't the one making the change: refunds always
    /// go to the owner.
    var refundsGoTo: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: refund.cents > 0 ? "arrow.uturn.backward.circle.fill" : "clock.badge.xmark")
                .font(.headline)
            Text(explanation)
                .font(.footnote)
                .foregroundStyle(Color.appForeground.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appForeground.opacity(0.06), in: .rect(cornerRadius: appFieldCornerRadius))
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        refund.cents > 0 ? "\(formatCredits(cents: refund.cents)) credit refund" : "No credit refund"
    }

    /// Whose balance the refund goes to, e.g. "your" or "Sam's".
    private var whose: String {
        refundsGoTo.map { "\($0)'s" } ?? "your"
    }

    private var explanation: String {
        guard refund.cents > 0 else {
            return "Refunds end a day after a trip starts, so the credits paid for this trip aren't given back."
        }
        switch reason {
        case .delete:
            return "Everything paid for this trip goes back to \(whose) credit balance when it's deleted."
        case .edit:
            return "The credits for the days and people this trip no longer needs go back to \(whose) credit balance."
        }
    }
}

/// Asks before deleting a trip, saying what's lost and what credits come back. The
/// refund is looked up as the popup opens; deleting doesn't wait for it.
struct DeleteTripPopup: View {
    let tripId: String
    let onDelete: () -> Void
    let onClose: () -> Void
    var api: APIClient = .shared

    @State private var refund: TripRefund?
    @State private var isLoadingRefund = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Delete Trip", systemImage: "trash.fill")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.appForeground.opacity(0.6))

            VStack(alignment: .leading, spacing: 6) {
                Text("Delete this trip?")
                    .font(.headline)
                Text("Everything on it is deleted for everyone on the trip. This can't be undone.")
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isLoadingRefund {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(Color.appForeground)
                    Text("Checking for a credit refund…")
                        .font(.footnote)
                        .foregroundStyle(Color.appForeground.opacity(0.7))
                }
                .transition(PopupCard.contentTransition)
            } else if let refund, refund.isWorthShowing {
                TripRefundSection(refund: refund, reason: .delete)
                    .transition(PopupCard.contentTransition)
            }

            Button(action: onDelete) {
                Text("Delete Trip")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appError, in: .rect(cornerRadius: appFieldCornerRadius))
            }
            .buttonStyle(.plain)
            .requiresConnection()
            .padding(.top, 4)
        }
        .popupCard(onClose: onClose)
        .task {
            // No refund line if it can't be looked up; deleting still works.
            let loaded = try? await TripsAPI.deleteRefund(tripId: tripId, api: api)
            withAnimation(PopupCard.resizeAnimation) {
                refund = loaded
                isLoadingRefund = false
            }
        }
    }
}

/// Asks before saving an edit that gives credits back, e.g. shorter dates.
struct RefundConfirmationPopup: View {
    let tripTitle: String
    let quote: TripQuote
    /// The trip owner's name when someone else is editing (see `TripRefundSection`).
    var refundsGoTo: String?
    let onConfirm: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Confirm Changes", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.appForeground.opacity(0.6))

            Text("Save the changes to \(tripTitle)?")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            TripRefundSection(refund: quote.editRefund, reason: .edit, refundsGoTo: refundsGoTo)

            Button(action: onConfirm) {
                Text("Save Changes")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appBackground, in: .rect(cornerRadius: appFieldCornerRadius))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .popupCard(onClose: onClose)
    }
}

#Preview("Refund on edit") {
    DimmedPopup(onClose: {}) {
        RefundConfirmationPopup(
            tripTitle: "Lisbon",
            quote: TripQuote(
                days: 4, members: 2, extraMembers: 0, priceCents: 0, refundCents: 480,
                balanceCents: 2_000, shortfallCents: 0, tripLines: [], memberLines: []
            ),
            onConfirm: {}, onClose: {}
        )
    }
    .background(LinearGradient.tripsBackground)
}
