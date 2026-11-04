//
//  PriceBreakdown.swift
//  outbound
//

import SwiftUI

/// How a quoted trip price adds up, collapsed until asked for: each trip-day bracket,
/// then the extra people's member-day brackets, the total, and for an edit, what's
/// already been paid and what's due now. Shown in `ChargeConfirmationPopup` and in
/// `PurchasePopup` when a save is short of credits.
struct PriceBreakdown: View {
    let quote: TripQuote

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(PopupCard.resizeAnimation) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text("How we got this")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

            if isExpanded {
                lines
                    .transition(PopupCard.contentTransition)
            }
        }
    }

    private var lines: some View {
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
                // Each line already covers everyone extra: the brackets run over all
                // their member-days together.
                ForEach(Array(quote.memberLines.enumerated()), id: \.offset) { _, line in
                    lineRow(line, label: Self.memberDaysRangeText(line))
                }
            }

            Divider()
                .overlay(Color.appForeground.opacity(0.12))
                .padding(.vertical, 2)
            totalRow("Trip price", cents: tripPriceCents)
            if paidCents > 0 {
                totalRow("Already paid", cents: -paidCents)
                totalRow("Due now", cents: quote.priceCents)
                    .fontWeight(.semibold)
            }
        }
        .foregroundStyle(Color.appForeground.opacity(0.8))
    }

    /// The trip's whole price as it would stand: what the lines add up to.
    private var tripPriceCents: Int {
        (quote.tripLines + quote.memberLines).reduce(0) { $0 + $1.cents }
    }

    /// What's been paid for the trip already, e.g. before an edit that adds days.
    private var paidCents: Int { quote.paidCents ?? 0 }

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

    private func totalRow(_ title: String, cents: Int) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            Text(formatCredits(cents: cents, signed: cents < 0))
                .frame(minWidth: 56, alignment: .trailing)
        }
        .font(.footnote)
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}
