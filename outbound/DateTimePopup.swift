//
//  DateTimePopup.swift
//  outbound
//

import SwiftUI

/// A centered black card for picking an item's start or end, shown over the item
/// form when its date row is tapped. Shows the trip's days as a Sunday–Saturday
/// calendar; picking a day and time isn't wired up yet.
struct DateTimePopup: View {
    /// The row's label, e.g. "Starts" or "Check-out".
    let title: String
    /// The trip's first through last day; nil when the trip's dates aren't known.
    let tripDates: ClosedRange<Date>?
    let onClose: () -> Void

    /// Natural height of the calendar, so the card hugs it until it needs to scroll.
    @State private var calendarHeight: CGFloat = 0

    private static let cellSpacing: CGFloat = 6
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label(title, systemImage: "calendar")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(Color.appForeground.opacity(0.12), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if let tripDates {
                VStack(spacing: 8) {
                    weekdayHeader
                    ScrollView {
                        calendar(TripCalendarGrid(start: tripDates.lowerBound, end: tripDates.upperBound))
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { calendarHeight = $0 }
                    }
                    .frame(height: min(calendarHeight, 360))
                    .scrollBounceBehavior(.basedOnSize)
                }
            } else {
                Text("This trip has no dates yet.")
                    .font(.footnote)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                    .padding(.horizontal, 4)
            }
        }
        .foregroundStyle(Color.appForeground)
        .padding(20)
        .frame(maxWidth: 360)
        .background(Color.black, in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    /// Single-letter weekday labels, Sunday first.
    private var weekdayHeader: some View {
        LazyVGrid(columns: Self.columns, spacing: Self.cellSpacing) {
            ForEach(Array(Calendar.sundayFirst.veryShortWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.appForeground.opacity(0.5))
            }
        }
        .accessibilityHidden(true)
    }

    private func calendar(_ grid: TripCalendarGrid) -> some View {
        LazyVGrid(columns: Self.columns, spacing: Self.cellSpacing) {
            ForEach(grid.weeks.flatMap { $0 }) { day in
                dayCell(day)
            }
        }
    }

    private func dayCell(_ day: TripCalendarGrid.Day) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Text(day.date, format: .dateTime.day())
                    .font(.subheadline.weight(day.isInTrip ? .semibold : .regular))
                    .monospacedDigit()
                    .foregroundStyle(Color.appForeground.opacity(day.isInTrip ? 1 : 0.3))
            }
            .background(
                Color.appForeground.opacity(day.isInTrip ? 0.14 : 0.04),
                in: .rect(cornerRadius: 8)
            )
            .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).month(.wide).day()))
            .accessibilityHidden(!day.isInTrip)
    }
}

#Preview {
    ZStack {
        Color(white: 0.3).ignoresSafeArea()
        DateTimePopup(title: "Starts", tripDates: .now ... .now.addingTimeInterval(9 * 86_400), onClose: {})
    }
}
