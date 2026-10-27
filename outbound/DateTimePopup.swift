//
//  DateTimePopup.swift
//  outbound
//

import SwiftUI

/// A centered black card for picking an item's start or end, shown over the item
/// form when its date row is tapped. Shows the trip's days as a Sunday–Saturday
/// calendar, then the hours, minutes and AM/PM. Tapping a time choice highlights it,
/// but nothing is written back to the form yet.
struct DateTimePopup: View {
    /// Leads the date line at the top, e.g. "Starts at" or "Check-out at".
    let title: String
    /// The trip's first through last day; nil when the trip's dates aren't known.
    let tripDates: ClosedRange<Date>?
    let onClose: () -> Void
    /// The row's current value, shown on the date line; nil when it isn't set.
    private let date: Date?

    /// Natural height of the calendar, so the card hugs it until it needs to scroll.
    @State private var calendarHeight: CGFloat = 0
    /// The highlighted hour on a 12-hour clock (1–12), if any.
    @State private var selectedHour: Int?
    /// The highlighted minute, one of `minutes`.
    @State private var selectedMinute: Int
    /// Whether the selected time is PM rather than AM.
    @State private var isPM: Bool

    private static let cellSpacing: CGFloat = 3
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: cellSpacing), count: 7)
    /// Corner radius of the day cells and the hour box.
    private static let gridCornerRadius: CGFloat = 4
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
        self.date = date
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
                valueLine(title, date?.formatted(.dateTime.month(.abbreviated).day().year()))
                    .accessibilityAddTraits(.isHeader)
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
                ScrollView {
                    calendar(TripCalendarGrid.months(start: tripDates.lowerBound, end: tripDates.upperBound))
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { calendarHeight = $0 }
                }
                .frame(height: min(calendarHeight, 360))
                .scrollBounceBehavior(.basedOnSize)
            } else {
                Text("This trip has no dates yet.")
                    .font(.footnote)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                    .padding(.horizontal, 4)
            }

            // Sets the date section apart from the time below it.
            Rectangle()
                .fill(Color.appForeground.opacity(0.12))
                .frame(height: 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                valueLine("Time", selectedTimeText)
                hourRow
                minuteRow
            }
        }
        .foregroundStyle(Color.appForeground)
        .padding(20)
        .frame(maxWidth: 360)
        .background(Color.black, in: .rect(cornerRadius: 20))
        // A light gray edge so the black card stands out against the dimmed form.
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.3)))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    /// A "Label: value" line with the label dimmed, e.g. "Time: 3:30 PM"; a nil value
    /// reads as a faint em dash, set a little further from the label.
    private func valueLine(_ label: String, _ value: String?) -> some View {
        (Text("\(label): ").foregroundStyle(Color.appForeground.opacity(0.6))
            + (value.map { Text($0) } ?? Text(" —").foregroundStyle(Color.appForeground.opacity(0.3))))
            .font(.subheadline.weight(.semibold))
            .monospacedDigit()
            .contentTransition(.numericText())
            .padding(.horizontal, 4)
    }

    /// A section per month the trip touches: the month's name over its days, inset to
    /// line up with the date and time labels.
    private func calendar(_ months: [TripCalendarGrid.Month]) -> some View {
        VStack(spacing: 16) {
            ForEach(months) { month in
                VStack(spacing: 8) {
                    Text(month.start, format: .dateTime.month(.wide))
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(2.5)
                        .foregroundStyle(Color.appForeground.opacity(0.25))
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: Self.columns, spacing: Self.cellSpacing) {
                        ForEach(month.grid.weeks.flatMap { $0 }) { day in
                            dayCell(day)
                        }
                    }
                }
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
                Color.appForeground.opacity(day.isInTrip ? 0.14 : 0.08),
                in: .rect(cornerRadius: Self.gridCornerRadius)
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
            .clipShape(.rect(cornerRadius: Self.gridCornerRadius))
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
        DateTimePopup(title: "Starts at", tripDates: .now ... .now.addingTimeInterval(9 * 86_400), onClose: {})
    }
}
