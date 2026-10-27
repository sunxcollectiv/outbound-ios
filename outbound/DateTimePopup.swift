//
//  DateTimePopup.swift
//  outbound
//

import SwiftUI

/// A centered black card for picking an item's start or end, shown over the item
/// form when its date row is tapped. Shows the trip's days as a Sunday–Saturday
/// calendar, then the hours, minutes and AM/PM, then a time zone search. Each choice
/// is written straight back to `date` once both a day and an hour are picked, and a
/// picked zone straight to `zone`, so closing keeps them.
struct DateTimePopup: View {
    /// Leads the date line at the top, e.g. "Starts at" or "Check-out at".
    let title: String
    /// The trip's first through last day; nil when the trip's dates aren't known.
    let tripDates: ClosedRange<Date>?
    /// The row's value, as a wall clock on the device-zone canvas the form uses.
    @Binding var date: Date?
    /// The zone this time is in; nil when none is set.
    @Binding var zone: TimeZone?
    let onClose: () -> Void

    /// What's typed in the zone field; starts as the current zone's label.
    @State private var zoneQuery: String
    @FocusState private var isZoneFieldFocused: Bool
    /// Bottom edge of the zone field in the popup's visible area, to decide which way
    /// the suggestions open.
    @State private var zoneFieldBottom: CGFloat = 0
    @Environment(\.popupVisibleHeight) private var popupVisibleHeight

    /// The highlighted day (midnight, as in the calendar grid), shown on the date
    /// line; nil until the row has a value or a day is tapped.
    @State private var selectedDay: Date?
    /// Natural height of the calendar, so the card hugs it until it needs to scroll.
    @State private var calendarHeight: CGFloat = 0
    /// Side of a day cell as laid out, so the hour cells can match it. Starts at a
    /// typical size until the calendar is measured (or when there's no calendar).
    @State private var dayCellSize: CGFloat = 44
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
    /// The hour row repeats 1–12 this many times and opens in the middle copy, so it
    /// scrolls on in either direction as if it looped.
    private static let hourCycles = 100
    private static let middleCycle = hourCycles / 2
    private static let minutes = [0, 15, 30, 45]
    /// How far the dark fade reaches in from each end of the hour row.
    private static let hourFadeWidth: CGFloat = 100
    /// How dark the fade gets at the very ends, so edge hours stay faintly visible.
    private static let hourFadeOpacity: Double = 0.6
    private static let zoneFieldHeight: CGFloat = 44
    private static let zoneResultRowHeight: CGFloat = 40
    /// Space between the zone field and its floating suggestions.
    private static let zoneResultsGap: CGFloat = 4
    /// Room the suggestions keep clear of the visible area's edge before flipping.
    private static let zoneResultsEdgeMargin: CGFloat = 16

    /// `date` seeds the highlighted day, hour, minute and AM/PM (the row's current
    /// value, if set).
    init(title: String, tripDates: ClosedRange<Date>?, date: Binding<Date?>, zone: Binding<TimeZone?>, onClose: @escaping () -> Void) {
        self.title = title
        self.tripDates = tripDates
        _date = date
        _zone = zone
        self.onClose = onClose
        let date = date.wrappedValue
        _zoneQuery = State(initialValue: zone.wrappedValue.map { TimeZoneSearch.label($0, at: date ?? tripDates?.lowerBound ?? .now) } ?? "")
        _selectedDay = State(initialValue: date.map { Calendar.sundayFirst.startOfDay(for: $0) })
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

    /// The selected day and time as one date, or nil until both a day and an hour
    /// are picked.
    private var selectedDate: Date? {
        guard let selectedDay, let selectedHour else { return nil }
        return Self.date(on: selectedDay, hour: selectedHour, minute: selectedMinute, isPM: isPM)
    }

    /// `day` at the given 12-hour clock time, e.g. 12 AM is midnight and 12 PM is noon.
    static func date(on day: Date, hour: Int, minute: Int, isPM: Bool, calendar: Calendar = .sundayFirst) -> Date? {
        let hour24 = hour % 12 + (isPM ? 12 : 0)
        return calendar.date(bySettingHour: hour24, minute: minute, second: 0, of: day)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                valueLine(title, selectedDay?.formatted(.dateTime.month(.abbreviated).day().year()))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
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

            zoneField
        }
        // Black with a light gray edge so the card stands out against the dimmed form.
        .popupCard(background: .black, border: .white.opacity(0.3), onClose: onClose)
        .onChange(of: selectedDate) { _, newDate in
            if let newDate { date = newDate }
        }
    }

    /// The moment zone abbreviations are read at (EST vs EDT): the chosen time, else the
    /// highlighted day, else the trip's first day — so an unset row in November still
    /// shows EST rather than whatever today's offset is.
    private var zoneReferenceDate: Date {
        date ?? selectedDay ?? tripDates?.lowerBound ?? .now
    }

    /// Zones matching what's typed, hidden once the text is the chosen zone's label.
    private var zoneResults: [TimeZone] {
        guard isZoneFieldFocused, zoneQuery != zone.map(zoneLabel) else { return [] }
        return TimeZoneSearch.matches(zoneQuery, at: zoneReferenceDate)
    }

    private func zoneLabel(_ zone: TimeZone) -> String {
        TimeZoneSearch.label(zone, at: zoneReferenceDate)
    }

    /// A search field for the time zone, kept dark with a light outline. Matches float
    /// in a list over the card rather than growing it: below the field, or above it
    /// when there isn't room below (say, with the keyboard up). Clearing it removes the zone.
    private var zoneField: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(Color.appForeground.opacity(0.5))
            TextField(
                "",
                text: $zoneQuery,
                prompt: Text("Timezone (optional)").foregroundStyle(Color.appForeground.opacity(0.4))
            )
            .textFieldStyle(.plain)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($isZoneFieldFocused)
            if !zoneQuery.isEmpty {
                Button {
                    zoneQuery = ""
                    zone = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Color.appForeground.opacity(0.5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear time zone")
            }
        }
        .font(.subheadline)
        .padding(.horizontal, 12)
        .frame(height: Self.zoneFieldHeight)
        .overlay(
            RoundedRectangle(cornerRadius: Self.gridCornerRadius)
                .strokeBorder(Color.appForeground.opacity(0.25))
        )
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: DimmedPopup<EmptyView>.space).maxY } action: {
            zoneFieldBottom = $0
        }
        .overlay(alignment: showsZoneResultsAbove ? .bottom : .top) {
            if !zoneResults.isEmpty {
                // Start level with the field, then slide a field's height (plus a small
                // gap) up or down so the list sits just clear of it.
                zoneResultsList
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(y: (Self.zoneFieldHeight + Self.zoneResultsGap) * (showsZoneResultsAbove ? -1 : 1))
            }
        }
    }

    /// The floating list of matching zones.
    private var zoneResultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(zoneResults.enumerated()), id: \.element.identifier) { index, match in
                if index > 0 {
                    Rectangle()
                        .fill(Color.appForeground.opacity(0.12))
                        .frame(height: 1)
                }
                Button {
                    zone = match
                    zoneQuery = zoneLabel(match)
                    isZoneFieldFocused = false
                } label: {
                    HStack {
                        Text(TimeZoneSearch.city(match))
                            .lineLimit(1)
                            .layoutPriority(1)
                        Spacer(minLength: 12)
                        // Long ids (America/North_Dakota/New_Salem) shorten in the middle,
                        // keeping the abbreviation at the end readable.
                        Text("\(match.identifier) · \(WallClock.zoneAbbreviation(match, at: zoneReferenceDate))")
                            .font(.caption)
                            .foregroundStyle(Color.appForeground.opacity(0.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .frame(height: Self.zoneResultRowHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: 0.08), in: .rect(cornerRadius: Self.gridCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Self.gridCornerRadius)
                .strokeBorder(Color.appForeground.opacity(0.25))
        )
        .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
    }

    /// Whether the suggestion list opens above the field: when the room left below it
    /// in the visible area (above the keyboard, when it's up) can't fit the list.
    private var showsZoneResultsAbove: Bool {
        let roomBelow = popupVisibleHeight - zoneFieldBottom - Self.zoneResultsEdgeMargin
        return popupVisibleHeight > 0 && roomBelow < zoneResultsHeight + Self.zoneResultsGap
    }

    /// Height of the suggestion list: its fixed-height rows plus the dividers between.
    private var zoneResultsHeight: CGFloat {
        CGFloat(zoneResults.count) * Self.zoneResultRowHeight + CGFloat(max(zoneResults.count - 1, 0))
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
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        (proxy.size.width - 6 * Self.cellSpacing) / 7
                    } action: { dayCellSize = $0 }
                }
            }
        }
    }

    /// A square day; trip days can be tapped to select them, filling the cell like
    /// the selected hour. Days outside the trip only pad the week.
    private func dayCell(_ day: TripCalendarGrid.Day) -> some View {
        let isSelected = day.isInTrip && selectedDay == day.date
        // Weekends stand out so the week's shape reads at a glance: trip weekends get a
        // white line along the bottom, padding weekends a slightly lighter fill.
        let isWeekend = Calendar.sundayFirst.isDateInWeekend(day.date)
        let fill = day.isInTrip ? 0.14 : (isWeekend ? 0.09 : 0.06)
        let showsWeekendLine = isWeekend && day.isInTrip && !isSelected
        return Button {
            withAnimation(.snappy(duration: 0.15)) { selectedDay = day.date }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    Text(day.date, format: .dateTime.day())
                        .font(.subheadline.weight(day.isInTrip ? .semibold : .regular))
                        .monospacedDigit()
                        .foregroundStyle(isSelected ? Color.black : Color.appForeground.opacity(day.isInTrip ? 1 : 0.3))
                }
                .background(isSelected ? Color.appForeground : Color.appForeground.opacity(fill))
                .overlay(alignment: .bottom) {
                    if showsWeekendLine {
                        Color.white.opacity(0.5).frame(height: 2)
                    }
                }
                .clipShape(.rect(cornerRadius: Self.gridCornerRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `.disabled`, which would also fade the padding days past their own styling.
        .allowsHitTesting(day.isInTrip)
        .accessibilityLabel(Text(day.date, format: .dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHidden(!day.isInTrip)
    }

    /// Hours 1–12 as one rounded box of cells the size of a day cell, split by thin
    /// dividers. The hours repeat in a lazy row that opens on the selection in the
    /// middle copy, so the box scrolls endlessly either way.
    private var hourRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(0..<(Self.hourCycles * Self.hours.count), id: \.self) { index in
                        HStack(spacing: 0) {
                            if index > 0 {
                                Rectangle()
                                    .fill(Color.appForeground.opacity(0.15))
                                    .frame(width: 1)
                                    .padding(.vertical, 10)
                            }
                            hourCell(Self.hours[index % Self.hours.count]) {
                                // Bring the tapped copy to the middle, clear of the edge fades.
                                withAnimation(.snappy(duration: 0.3)) { proxy.scrollTo(index, anchor: .center) }
                            }
                        }
                        // VoiceOver gets one set of hours rather than every copy.
                        .accessibilityHidden(index / Self.hours.count != Self.middleCycle)
                    }
                }
                .frame(height: dayCellSize)
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            // Tame the fling: a swipe moves only a few hours, then settles on a cell edge.
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByFew))
            .background(Color.appForeground.opacity(0.14))
            .overlay { hourRowEdgeFades }
            .clipShape(.rect(cornerRadius: Self.gridCornerRadius))
            .onAppear { scrollToSelectedHour(proxy) }
            // The cells resize once the calendar is measured; keep the selection centered.
            .onChange(of: dayCellSize) { scrollToSelectedHour(proxy) }
        }
    }

    /// Scrolls the hour row to the selected hour in the middle copy, or to the start of
    /// that copy when no hour is selected.
    private func scrollToSelectedHour(_ proxy: ScrollViewProxy) {
        let middle = Self.middleCycle * Self.hours.count
        if let selectedHour {
            proxy.scrollTo(middle + selectedHour - 1, anchor: .center)
        } else {
            proxy.scrollTo(middle, anchor: .leading)
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
                .fill(Color.appForeground.opacity(0.3))
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

    /// Dark gradients over both ends of the hour row, so hours fade in and out as they
    /// scroll; they let taps through to the hours beneath.
    private var hourRowEdgeFades: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.black.opacity(Self.hourFadeOpacity), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.hourFadeWidth)
            Spacer(minLength: 0)
            LinearGradient(colors: [.clear, .black.opacity(Self.hourFadeOpacity)], startPoint: .leading, endPoint: .trailing)
                .frame(width: Self.hourFadeWidth)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A tappable hour, filled edge to edge when selected; `onSelect` runs after the tap.
    private func hourCell(_ hour: Int, onSelect: @escaping () -> Void) -> some View {
        let isSelected = selectedHour == hour
        return Button {
            withAnimation(.snappy(duration: 0.15)) { selectedHour = hour }
            onSelect()
        } label: {
            Text(String(hour))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.black : Color.appForeground)
                .frame(width: dayCellSize)
                .frame(maxHeight: .infinity)
                .background(isSelected ? Color.appForeground : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(hour) o'clock")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    ZStack {
        Color(white: 0.3).ignoresSafeArea()
        DateTimePopup(title: "Starts at", tripDates: .now ... .now.addingTimeInterval(9 * 86_400), date: .constant(nil), zone: .constant(nil), onClose: {})
    }
}
