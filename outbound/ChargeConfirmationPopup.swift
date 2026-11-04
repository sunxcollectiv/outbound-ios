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

    @State private var showingBreakdown = false

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

            breakdown

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

    /// How the price adds up, collapsed until asked for.
    ///
    /// TODO: placeholder wording; the final explanation (and how it shows a change to an
    /// already-paid trip) is still to be written.
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(PopupCard.resizeAnimation) { showingBreakdown.toggle() }
            } label: {
                HStack {
                    Text("How we got this")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                        .rotationEffect(.degrees(showingBreakdown ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(showingBreakdown ? "Expanded" : "Collapsed")

            if showingBreakdown {
                VStack(alignment: .leading, spacing: 6) {
                    Text("\(quote.days) \(quote.days == 1 ? "day" : "days") for \(quote.members) \(quote.members == 1 ? "person" : "people")")
                        .font(.footnote.weight(.semibold))
                    ForEach(Array(quote.tripLines.enumerated()), id: \.offset) { _, line in
                        lineRow(line, label: Self.daysText(line))
                    }
                    if quote.extraMembers > 0 {
                        ForEach(Array(quote.memberLines.enumerated()), id: \.offset) { _, line in
                            lineRow(line, label: "\(quote.extraMembers) extra × \(Self.daysText(line).lowercased())", times: quote.extraMembers)
                        }
                    }
                    Text("Placeholder: a fuller explanation of this charge is coming.")
                        .font(.caption)
                        .italic()
                        .foregroundStyle(Color.appForeground.opacity(0.5))
                        .padding(.top, 4)
                }
                .foregroundStyle(Color.appForeground.opacity(0.8))
                .transition(PopupCard.contentTransition)
            }
        }
    }

    /// A bracket's days, e.g. "Day 1" or "Days 4–9".
    static func daysText(_ line: TripPricing.Line) -> String {
        line.firstDay == line.lastDay ? "Day \(line.firstDay)" : "Days \(line.firstDay)–\(line.lastDay)"
    }

    /// One bracket of the price, e.g. "Days 1–3   3 × $1.60   $4.80".
    private func lineRow(_ line: TripPricing.Line, label: String, times: Int = 1) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            Text("\(line.days) × \(formatCredits(cents: line.centsPerDay))")
                .foregroundStyle(Color.appForeground.opacity(0.6))
            Text(formatCredits(cents: line.cents * times))
                .frame(minWidth: 56, alignment: .trailing)
        }
        .font(.footnote)
        .monospacedDigit()
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
            quote: TripQuote(
                days: 3, members: 2, extraMembers: 0, priceCents: 480, refundCents: 0,
                balanceCents: 2_000, shortfallCents: 0,
                tripLines: TripPricing.breakdown(days: 3), memberLines: []
            ),
            onConfirm: {}, onClose: {}
        )
    }
    .background(LinearGradient.tripsBackground)
}
