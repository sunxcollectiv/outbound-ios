//
//  CreditsView.swift
//  outbound
//

import SwiftUI

/// One line in the user's credit ledger: money added, or spent on a trip.
struct CreditLedgerEntry: Identifiable, Equatable {
    let id: String
    /// What the line is for, e.g. "Added credits" or "Unlocked Tokyo 2026".
    let title: String
    /// Whole cents, positive for credits added and negative for credits spent, so
    /// amounts add up exactly.
    let amountCents: Int
    let date: Date
}

extension CreditLedgerEntry {
    /// The balance the lines add up to, in cents.
    static func balanceCents(of entries: [CreditLedgerEntry]) -> Int {
        entries.reduce(0) { $0 + $1.amountCents }
    }

    /// Placeholder lines until the backend has a ledger, newest first.
    static let samples: [CreditLedgerEntry] = {
        let now = Date()
        func daysAgo(_ days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }
        return [
            CreditLedgerEntry(id: "5", title: "Unlocked Lisbon Weekend", amountCents: -499, date: daysAgo(2)),
            CreditLedgerEntry(id: "4", title: "Added credits", amountCents: 1_000, date: daysAgo(3)),
            CreditLedgerEntry(id: "3", title: "Unlocked Tokyo 2026", amountCents: -999, date: daysAgo(21)),
            CreditLedgerEntry(id: "2", title: "Unlocked Big Sur Road Trip", amountCents: -499, date: daysAgo(45)),
            CreditLedgerEntry(id: "1", title: "Added credits", amountCents: 2_000, date: daysAgo(46)),
        ]
    }()
}

/// Formats cents as dollars, e.g. 1050 → "$10.50"; with `signed`, "+$10.50" or "−$4.99".
func formatCredits(cents: Int, signed: Bool = false) -> String {
    let dollars = (Decimal(abs(cents)) / 100).formatted(.currency(code: "USD"))
    guard signed else { return cents < 0 ? "-" + dollars : dollars }
    return (cents < 0 ? "−" : "+") + dollars
}

/// The user's credits, pushed from the drawer: the balance, a button to buy more, and
/// the activity behind the balance, newest first.
struct CreditsView: View {
    var entries: [CreditLedgerEntry] = CreditLedgerEntry.samples

    @State private var showingPurchase = false

    var body: some View {
        List {
            Section {
                balanceHeader
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                if entries.isEmpty {
                    Text("No activity yet")
                        .font(.subheadline)
                        .foregroundStyle(Color.appForeground.opacity(0.7))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(entries) { entry in
                        CreditLedgerRow(entry: entry)
                            .listRowBackground(Color.clear)
                            .listRowSeparatorTint(Color.appForeground.opacity(0.12))
                    }
                }
            } header: {
                Text("Activity")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appForeground.opacity(0.7))
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(LinearGradient.tripsBackground, for: .navigation)
        .offlinePillAtBottom()
        .foregroundStyle(Color.appForeground)
        .navigationTitle("Credits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // Drawn here rather than by the system, so it can dim with the page under
            // the popup (the bar sits above the popup's backdrop).
            ToolbarItem(placement: .principal) {
                Text("Credits")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .opacity(showingPurchase ? 0.2 : 1)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        // Hiding the whole bar would shift the page up under the popup.
        .navigationBarBackButtonHidden(showingPurchase)
        .overlay { purchasePopup }
        .offlinePillNearBottom(isActive: showingPurchase)
    }

    private func closePurchase() {
        withAnimation(.snappy(duration: 0.2)) { showingPurchase = false }
    }

    /// The open buy popup over a dimmed page; tapping outside closes it.
    @ViewBuilder
    private var purchasePopup: some View {
        if showingPurchase {
            DimmedPopup(onClose: closePurchase) {
                PurchasePopup(onClose: closePurchase)
            }
        }
    }

    private var balanceHeader: some View {
        VStack(spacing: 6) {
            Text("Balance")
                .font(.subheadline)
                .foregroundStyle(Color.appForeground.opacity(0.7))
            Text(formatCredits(cents: CreditLedgerEntry.balanceCents(of: entries)))
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
            Button {
                withAnimation(.snappy(duration: 0.2)) { showingPurchase = true }
            } label: {
                Label("Add Credits", systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.appBackground, in: .rect(cornerRadius: appFieldCornerRadius))
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

/// One ledger line: what it was for, when, and the amount in or out.
struct CreditLedgerRow: View {
    let entry: CreditLedgerEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.amountCents >= 0 ? "plus" : "lock.open")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.1), in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(entry.date, format: .dateTime.month(.abbreviated).day().year())
                    .font(.caption)
                    .foregroundStyle(Color.appForeground.opacity(0.5))
            }
            Spacer(minLength: 8)
            Text(formatCredits(cents: entry.amountCents, signed: true))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(entry.amountCents >= 0 ? Color.green : Color.appForeground)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack {
        CreditsView()
    }
}
