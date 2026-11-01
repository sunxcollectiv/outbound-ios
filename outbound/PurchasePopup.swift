//
//  PurchasePopup.swift
//  outbound
//

import SwiftUI

/// A centered card for buying credits, shown over the credits page: a choice of set
/// amounts, a button to confirm the one picked, and how trips are priced.
struct PurchasePopup: View {
    let onClose: () -> Void

    /// The amounts on offer, in cents.
    static let amountsCents = [500, 1_500, 2_500, 5_000]

    @State private var selectedCents = 1_500

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

            Divider()
                .overlay(Color.appForeground.opacity(0.12))

            pricing
        }
        .popupCard(onClose: onClose)
    }

    /// How credits are spent: each trip day at its bracket's rate, from `TripPricing`.
    private var pricing: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How trip pricing works")
                .font(.subheadline.weight(.semibold))
            Text("You pay once per trip, based on how many days it is. Each day is priced at the rate for its range, so longer trips cost less per day.")
                .font(.footnote)
                .foregroundStyle(Color.appForeground.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 6) {
                ForEach(TripPricing.brackets, id: \.firstDay) { bracket in
                    HStack {
                        Text(Self.daysText(bracket))
                        Spacer()
                        Text("\(formatCredits(cents: bracket.centsPerDay)) per day")
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }
            }
            .padding(.top, 2)
        }
        .accessibilityElement(children: .combine)
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
