//
//  DateTimePopup.swift
//  outbound
//

import SwiftUI

/// A centered black card for picking an item's start or end, shown over the item
/// form when its date row is tapped. Shows the trip's days as a Sunday–Saturday
/// calendar, then a row of hours. Tapping an hour highlights it, but nothing is
/// written back to the form yet.
struct DateTimePopup: View {
    /// The row's label, e.g. "Starts" or "Check-out".
    let title: String
    /// The trip's first through last day; nil when the trip's dates aren't known.
    let tripDates: ClosedRange<Date>?
    let onClose: () -> Void

    /// Natural height of the calendar, so the card hugs it until it needs to scroll.
    @State private var calendarHeight: CGFloat = 0
    /// The highlighted hour on a 12-hour clock (1–12), if any.
    @State private var selectedHour: Int?
    /// The highlighted minute, one of `minutes`.
    @State private var selectedMinute: Int
    /// Whether the selected time is PM rather than AM.
    @State private var isPM: Bool

    private static let cellSpacing: CGFloat = 6
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7)
    private static let hours = Array(1...12)
    private static let minutes = [0, 15, 30, 45]
    /// Hour cells share one fixed width so the box scrolls rather than squeezing 12 in.
    private static let hourCellWidth: CGFloat = 48
    private static let hourRowHeight: CGFloat = 44

    /// `date` seeds the highlighted hour, minute and AM/PM (the row's current value, if set).
    init(title: String, tripDates: ClosedRange<Date>?, date: Date? = nil, onClose: @escaping () -> Void) {
        self.title = title
        self.tripDates = tripDates
        self.onClose = onClose
        let parts = date.map { Calendar.current.dateComponents([.hour, .minute], from: $0) }
        // Snap to the nearest quarter so an off-grid time still highlights a choice.
        let minute = parts?.minute ?? 0
        _selectedMinute = State(initialValue: Self.minutes.min { abs($0 - minute) < abs($1 - minute) } ?? 0)
        _isPM = State(initialValue: (parts?.hour ?? 0) >= 12)
        if let hour = parts?.hour {
            _selectedHour = State(initialValue: hour % 12 == 0 ? 12 : hour % 12)
        }
    }

    /// The selected time, e.g. "3:30 PM", or nil when no hour is selected.
    private var selectedTimeText: String? {
        guard let selectedHour else { return nil }
        return String(format: "%d:%02d %@", selectedHour, selectedMinute, isPM ? "PM" : "AM")
    }

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

            VStack(alignment: .leading, spacing: 8) {
                (Text("Time: ").foregroundStyle(Color.appForeground.opacity(0.6))
                    + Text(selectedTimeText ?? "Not set"))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .padding(.horizontal, 4)
                hourRow
                minuteRow
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

    /// Hours 1–12 as one rounded box of equal-width, full-height cells split by thin
    /// dividers. The box scrolls horizontally, starting scrolled to the selection.
    private var hourRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Self.hours, id: \.self) { hour in
                        if hour != Self.hours.first {
                            Rectangle()
                                .fill(Color.appForeground.opacity(0.15))
                                .frame(width: 1)
                                .padding(.vertical, 10)
                        }
                        hourCell(hour)
                    }
                }
                .frame(height: Self.hourRowHeight)
            }
            .scrollIndicators(.hidden)
            .background(Color.appForeground.opacity(0.14))
            .clipShape(.rect(cornerRadius: 8))
            .onAppear {
                if let selectedHour { proxy.scrollTo(selectedHour, anchor: .center) }
            }
        }
    }

    /// The quarter-hour minutes, then AM/PM after a thin divider, as plain text spread
    /// across the row: the selected choices in full white, the rest at half opacity.
    private var minuteRow: some View {
        HStack(spacing: 0) {
            ForEach(Self.minutes, id: \.self) { minute in
                textChoice(String(format: "%02d", minute), isSelected: selectedMinute == minute) {
                    selectedMinute = minute
                }
                .accessibilityLabel("\(minute) minutes")
            }
            Rectangle()
                .fill(Color.appForeground.opacity(0.15))
                .frame(width: 1, height: 20)
                // On top of the columns' own centering gap, to set AM/PM further apart.
                .padding(.horizontal, 16)
            textChoice("AM", isSelected: !isPM) { isPM = false }
            textChoice("PM", isSelected: isPM) { isPM = true }
        }
    }

    /// A tappable plain-text choice, full white when selected and half opacity otherwise.
    private func textChoice(_ label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.15), action)
        } label: {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Color.white.opacity(isSelected ? 1 : 0.5))
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A tappable hour, filled edge to edge when selected.
    private func hourCell(_ hour: Int) -> some View {
        let isSelected = selectedHour == hour
        return Button {
            withAnimation(.snappy(duration: 0.15)) { selectedHour = hour }
        } label: {
            Text(String(hour))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.black : Color.appForeground)
                .frame(width: Self.hourCellWidth)
                .frame(maxHeight: .infinity)
                .background(isSelected ? Color.appForeground : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(hour)
        .accessibilityLabel("\(hour) o'clock")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    ZStack {
        Color(white: 0.3).ignoresSafeArea()
        DateTimePopup(title: "Starts", tripDates: .now ... .now.addingTimeInterval(9 * 86_400), onClose: {})
    }
}
