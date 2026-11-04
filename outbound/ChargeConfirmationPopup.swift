//
//  ChargeConfirmationPopup.swift
//  outbound
//

import SwiftUI

/// Asks before a trip save that costs credits the user has: how much it takes, what
/// they have and will have left, and how the price was worked out. Shown from the trip
/// form over a dimmed screen (see `DimmedPopup`).
struct ChargeConfirmationPopup: View {
    let tripTitle: String
    let quote: TripQuote
    /// The trip owner's name when someone else is paying (an organizer editing the
    /// trip): refunds only ever go to the owner, so the payer is told up front.
    var refundsGoTo: String? = nil
    let onConfirm: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Confirm Credits", systemImage: "creditcard.fill")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.appForeground.opacity(0.6))

            Text("Saving \(tripTitle) uses \(formatCredits(cents: quote.priceCents)) of your credits.")
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                amountRow("Your credits", cents: quote.balanceCents)
                amountRow("This trip", cents: -quote.priceCents, signed: true)
                Divider()
                    .overlay(Color.appForeground.opacity(0.12))
                amountRow("Left after", cents: quote.balanceAfterCents)
                    .fontWeight(.semibold)
            }
            .padding(14)
            .background(Color.appForeground.opacity(0.06), in: .rect(cornerRadius: appFieldCornerRadius))

            if let refundsGoTo {
                OwnerRefundNote(owner: refundsGoTo)
            }

            PriceBreakdown(quote: quote)

            Button(action: onConfirm) {
                Text("Use \(formatCredits(cents: quote.priceCents))")
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

    private func amountRow(_ title: String, cents: Int, signed: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 12)
            Text(formatCredits(cents: cents, signed: signed))
                .monospacedDigit()
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// Warns a payer who isn't the trip's owner that credits spent on it don't come back
/// to them: refunds for a shortened or cancelled trip always go to the owner.
struct OwnerRefundNote: View {
    /// The owner's name.
    let owner: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.footnote.weight(.semibold))
            Text("You're not this trip's owner. If the trip is later shortened or cancelled, any refunded credits go to \(owner), not back to you.")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color.appForeground.opacity(0.8))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    DimmedPopup(onClose: {}) {
        ChargeConfirmationPopup(
            tripTitle: "Before",
            // 3 extra people × 5 days = 15 member-days, on the "2026-11" rates.
            quote: TripQuote(
                days: 5, members: 8, extraMembers: 3, priceCents: 915, refundCents: 0,
                balanceCents: 2_000, shortfallCents: 0,
                tripLines: [
                    TripPricing.Line(firstDay: 1, lastDay: 3, centsPerDay: 160),
                    TripPricing.Line(firstDay: 4, lastDay: 5, centsPerDay: 80),
                ],
                memberLines: [
                    TripPricing.Line(firstDay: 1, lastDay: 10, centsPerDay: 20),
                    TripPricing.Line(firstDay: 11, lastDay: 15, centsPerDay: 15),
                ]
            ),
            onConfirm: {}, onClose: {}
        )
    }
    .background(LinearGradient.tripsBackground)
}
