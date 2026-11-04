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
                        Text(Self.memberDaysText(extraMembers: quote.extraMembers, days: quote.days))
                            .font(.footnote.weight(.semibold))
                            .padding(.top, 4)
                        // Each line already covers everyone extra: the brackets run over
                        // all their member-days together.
                        ForEach(Array(quote.memberLines.enumerated()), id: \.offset) { _, line in
                            lineRow(line, label: Self.memberDaysRangeText(line))
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

    /// How the extra member-days add up, e.g. "3 extra people × 5 days = 15 member-days".
    static func memberDaysText(extraMembers: Int, days: Int) -> String {
        let people = extraMembers == 1 ? "1 extra person" : "\(extraMembers) extra people"
        let total = extraMembers * days
        return "\(people) × \(days) \(days == 1 ? "day" : "days") = \(total) \(total == 1 ? "member-day" : "member-days")"
    }

    /// A member bracket's member-days, e.g. "Member-day 1" or "Member-days 1–10".
    static func memberDaysRangeText(_ line: TripPricing.Line) -> String {
        line.firstDay == line.lastDay ? "Member-day \(line.firstDay)" : "Member-days \(line.firstDay)–\(line.lastDay)"
    }

    /// One bracket of the price, e.g. "Days 1–3   3 × $1.60   $4.80".
    private func lineRow(_ line: TripPricing.Line, label: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            Text("\(line.days) × \(formatCredits(cents: line.centsPerDay))")
                .foregroundStyle(Color.appForeground.opacity(0.6))
            Text(formatCredits(cents: line.cents))
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
