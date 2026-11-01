//
//  PurchasePopup.swift
//  outbound
//

import SwiftUI

/// A centered card for buying credits, shown over the credits page: a choice of set
/// amounts, a button to confirm the one picked, and how trips are priced.
struct PurchasePopup: View {
    let onClose: () -> Void

    /// How many people the "usable for" line prices a trip for.
    var members = TripPricing.includedMembers

    /// The amounts on offer, in cents.
    static let amountsCents = [500, 1_500, 2_500, 5_000]

    @State private var selectedCents = 1_500
    @State private var showingPricing = false

    /// One column per amount, so they all sit in a single row.
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: amountsCents.count)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Purchase Credits", systemImage: "creditcard.fill")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.appForeground.opacity(0.6))

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Self.amountsCents, id: \.self) { cents in
                    amountOption(cents)
                }
            }

            Button {
                // TODO: start the purchase once payments are integrated.
            } label: {
                Text("Purchase Credits")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appBackground, in: .rect(cornerRadius: appFieldCornerRadius))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)

            Text(Self.usableText(cents: selectedCents, members: members))
                .font(.footnote)
                .foregroundStyle(Color.appForeground.opacity(0.7))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.top, -6)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: selectedCents)

            Divider()
                .overlay(Color.appForeground.opacity(0.12))

            pricing
        }
        .popupCard(onClose: onClose)
    }

    /// How credits are spent, collapsed until asked for: each trip day at its bracket's
    /// rate, plus each member beyond the included ones at theirs, from `TripPricing`.
    private var pricing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(PopupCard.resizeAnimation) { showingPricing.toggle() }
            } label: {
                HStack {
                    Text("How trip pricing works")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                        .rotationEffect(.degrees(showingPricing ? 180 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityValue(showingPricing ? "Expanded" : "Collapsed")

            if showingPricing {
                VStack(alignment: .leading, spacing: 10) {
                    Text("You pay once per trip, based on how many days it is. Each day is priced at the rate for its range, so longer trips cost less per day.")
                        .font(.footnote)
                        .foregroundStyle(Color.appForeground.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                    ratesTable(TripPricing.brackets, rateHeader: "Per day")

                    Text("A standard trip includes unlimited collaboration between \(TripPricing.includedMembers) people. Each extra person costs less per day for longer trips.")
                        .font(.footnote)
                        .foregroundStyle(Color.appForeground.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    ratesTable(TripPricing.memberBrackets, rateHeader: "Per person, per day")
                }
                .transition(PopupCard.contentTransition)
            }
        }
    }

    /// Brackets as a bordered two-column table: the days, then the rate.
    private func ratesTable(_ brackets: [TripPricing.Bracket], rateHeader: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: appFieldCornerRadius)
        return VStack(spacing: 0) {
            tableRow(Text("Trip days"), Text(rateHeader), fill: Color.white.opacity(0.08))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appForeground.opacity(0.6))

            ForEach(Array(brackets.enumerated()), id: \.element.firstDay) { index, bracket in
                // Every other row shaded, so a rate is easy to follow across.
                tableRow(
                    Text(Self.daysText(bracket)),
                    Text(formatCredits(cents: bracket.centsPerDay)).monospacedDigit(),
                    fill: index.isMultiple(of: 2) ? Color.clear : Color.white.opacity(0.04)
                )
                .font(.footnote)
            }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1)))
    }

    private func tableRow(_ days: some View, _ rate: some View, fill: Color) -> some View {
        HStack {
            days
            Spacer(minLength: 12)
            rate
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(fill)
        .accessibilityElement(children: .combine)
    }

    /// How many equal trips the larger amounts are described as covering, since one
    /// very long trip says little about what they're good for. Others cover one.
    static let tripsPerAmount = [2_500: 3, 5_000: 6]

    /// What an amount pays for, e.g. "Usable for a 17-day trip with up to 5 members"
    /// or "Usable for 3 separate 7-day trips with up to 5 members".
    static func usableText(cents: Int, members: Int) -> String {
        let trips = tripsPerAmount[cents] ?? 1
        let days = TripPricing.maxDays(budgetCents: cents / trips, members: members)
        let who = "\(members) \(members == 1 ? "member" : "members")"
        guard days > 0 else { return "Not enough for a 1-day trip with \(who)" }
        guard trips > 1 else { return "Usable for a \(days)-day trip with up to \(who)" }
        return "Usable for \(trips) separate \(days)-day trips with up to \(who)"
    }

    /// A bracket's days, e.g. "Days 1–3" or "Day 31 and beyond".
    static func daysText(_ bracket: TripPricing.Bracket) -> String {
        guard let lastDay = bracket.lastDay else { return "Day \(bracket.firstDay) and beyond" }
        return "Days \(bracket.firstDay)–\(lastDay)"
    }

    private func amountOption(_ cents: Int) -> some View {
        let isSelected = cents == selectedCents
        return Button {
            selectedCents = cents
        } label: {
            Text(formatCredits(cents: cents).replacingOccurrences(of: ".00", with: ""))
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.appForeground.opacity(isSelected ? 0.16 : 0.06),
                            in: .rect(cornerRadius: appFieldCornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: appFieldCornerRadius)
                        .strokeBorder(isSelected ? Color.appBackground : .white.opacity(0.08),
                                      lineWidth: isSelected ? 2 : 1)
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    DimmedPopup(onClose: {}) {
        PurchasePopup(onClose: {})
    }
    .background(LinearGradient.tripsBackground)
}
