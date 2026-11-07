//
//  DaySelectorBar.swift
//  outbound
//

import SwiftUI

/// The day picker pinned to the bottom of the itinerary: a dark glassy bar with a
/// circular button per day (weekday label above, day-of-month inside the circle).
/// The selected day is a filled cream disc; tapping a day scrubs the pager and the
/// bar stays in sync with the current `selection`.
///
/// Days scroll horizontally — about five fit across the width at once — and the row
/// can be slid freely to any day. Whenever `selection` changes (a tap here, or a
/// swipe of the itinerary itself), the selected day animates back to center.
struct DaySelectorBar: View {
    /// The fade above the row of day circles. The itinerary reads it to know where
    /// the circles start, the bottom of the band it centers an opened card in.
    static let fadeHeight: CGFloat = 40

    let days: [ItineraryDay]
    @Binding var selection: Int
    /// Live itinerary-swipe progress in day-units (-1…1); pulls the row along as the
    /// pages are dragged, before `selection` settles on the final day.
    var dragProgress: CGFloat = 0
    /// Tapped from the plus button at either end of the row, to add a segment:
    /// `.leading` for days before the trip, `.trailing` for days after.
    var onAddSegment: (HorizontalEdge) -> Void = { _ in }
    /// The ends that show the plus button; an end left out keeps its empty cell, so the
    /// row's layout doesn't change.
    var segmentEdges: Set<HorizontalEdge> = [.leading, .trailing]
    /// The trip the screen is for: its days' line is solid, its extensions' hatched.
    var primaryTripId: String?

    /// How far the row is scrolled, for drawing the trip lines (outside the scroll view,
    /// so the edge fade doesn't reach them) in step with the days.
    @State private var scrollOffset: CGFloat = 0
    /// The room below the row down to the screen's bottom edge, where the trip lines sit.
    @State private var bottomInset: CGFloat = 0
    /// The trip line's thickness, and the break between trips.
    private static let tripLineHeight: CGFloat = 5
    private static let tripLineBreak: CGFloat = 8
    /// The screen's corner radius on current iPhones (not public API, so a constant).
    /// The trip lines fade out across the bottom corners: from where the curve begins,
    /// to where it has swallowed the line's height.
    private static let screenCornerRadius: CGFloat = 62

    var body: some View {
        GeometryReader { geo in
            // A fade band at each edge doubles as the side margin: five cells fill the
            // space between the two bands and stay fully opaque, while days scrolling
            // past fade out through the band (see edgeFadeMask).
            let fadeZone: CGFloat = 36
            let circleSize: CGFloat = 56   // matches the dayCell circle
            // Five circles fit between the fade bands; widen the gap between them by 20%.
            let baseGap = (geo.size.width - fadeZone * 2) / 5 - circleSize
            let cellWidth = max(circleSize + baseGap * 1.2, 1)
            let sideInset = (geo.size.width - cellWidth) / 2

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 2) {
                        HStack(spacing: 0) {
                            // The add-segment buttons sit in the side insets, so the first
                            // and last days still scroll to center.
                            segmentEnd(.leading)
                                .frame(width: cellWidth)
                            ForEach(cells) { cell in
                                switch cell {
                                case .day(let day):
                                    dayCell(day)
                                        .frame(width: cellWidth)
                                        .id(day.dayNumber)
                                case .gap(let gapDays):
                                    gapCell(gapDays)
                                        .frame(width: cellWidth)
                                }
                            }
                            segmentEnd(.trailing)
                                .frame(width: cellWidth)
                        }
                        .padding(.horizontal, max(sideInset - cellWidth, 0))
                        // Track the itinerary swipe: one day-width of travel per full page drag.
                        .offset(x: dragProgress * cellWidth)
                    }
                }
                // A static edge gradient fades the content (glass included) near both
                // sides, so days ease in/out instead of being hard-cut at the edge.
                .mask(edgeFadeMask(fadeZone: fadeZone, width: geo.size.width))
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.x } action: { _, x in
                    scrollOffset = x
                }
                .overlay(alignment: .bottomLeading) {
                    tripLines(
                        cellWidth: cellWidth,
                        // Where the first cell starts on screen.
                        origin: max(sideInset - cellWidth, 0) - scrollOffset + dragProgress * cellWidth,
                        width: geo.size.width
                    )
                    // Down past the safe area, so the line sits on the screen's bottom edge.
                    .offset(y: bottomInset)
                }
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
                .onChange(of: selection) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 56)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        .padding(.top, Self.fadeHeight)
        .frame(maxWidth: .infinity)
        .background {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        }
    }

    /// A full-height horizontal gradient: transparent at both edges, opaque across the
    /// middle. Used as a mask so day cells fade as they scroll into the edge bands.
    /// The ramp is compressed to the inner part of each band, so days drop to
    /// transparent sharply once they leave the primary five.
    private func edgeFadeMask(fadeZone: CGFloat, width: CGFloat) -> some View {
        let f = max(0, min(0.5, fadeZone / width))
        let ramp = f * 0.7   // only the inner ~70% of the band ramps; the rest is clear
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: f - ramp),
                .init(color: .white, location: f),
                .init(color: .white, location: 1 - f),
                .init(color: .clear, location: 1 - (f - ramp)),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// A white line under each run of days on one trip, reaching the screen edges at the
    /// ends of the journey, with a short break where one trip meets the next and none
    /// under gap days. `origin` is where the leading plus cell starts on screen.
    private func tripLines(cellWidth: CGFloat, origin: CGFloat, width: CGFloat) -> some View {
        // Each run of cells sharing a trip, by cell index (the plus cell is 0). A day
        // no trip covers (a flight before the trip, say) joins the run it sits beside.
        var runs: [(trip: String?, first: Int, last: Int)] = []
        for (offset, cell) in cells.enumerated() {
            let index = offset + 1
            guard case .day(let day) = cell else { continue }
            if let last = runs.last, last.last == index - 1, day.tripId == nil || last.trip == nil || last.trip == day.tripId {
                runs[runs.count - 1] = (last.trip ?? day.tripId, last.first, index)
            } else {
                runs.append((day.tripId, index, index))
            }
        }
        return ZStack(alignment: .leading) {
            ForEach(Array(runs.enumerated()), id: \.offset) { position, run in
                let touchesPrevious = position > 0 && runs[position - 1].last == run.first - 1
                let touchesNext = position < runs.count - 1 && runs[position + 1].first == run.last + 1
                // Out to the screen edge at either end of the journey.
                let start = position == 0 ? min(origin, 0) - 1 : origin + CGFloat(run.first) * cellWidth + (touchesPrevious ? Self.tripLineBreak / 2 : 0)
                let end = position == runs.count - 1 ? max(origin + CGFloat(cells.count + 2) * cellWidth, width) + 1 : origin + CGFloat(run.last + 1) * cellWidth - (touchesNext ? Self.tripLineBreak / 2 : 0)
                tripLine(isPrimary: run.trip == nil || run.trip == primaryTripId)
                    .frame(width: max(end - start, 0), height: Self.tripLineHeight)
                    .offset(x: start)
            }
        }
        .frame(width: width, alignment: .leading)
        .clipped()
        .mask(cornerFadeMask(width: width))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Clear at each end where the screen's corner curve has cut off the line, opaque from
    /// where the curve starts.
    private func cornerFadeMask(width: CGFloat) -> some View {
        let r = Self.screenCornerRadius
        // How far in from the edge the curve is at the line's top.
        let lost = r - (r * r - (r - Self.tripLineHeight) * (r - Self.tripLineHeight)).squareRoot()
        // The fade starts a little inside the curve, so it's well underway by the corner.
        let clear = min(lost / width, 0.5), opaque = min((r + 15) / width, 0.5)
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: clear),
                .init(color: .white, location: opaque),
                .init(color: .white, location: 1 - opaque),
                .init(color: .clear, location: 1 - clear),
                .init(color: .clear, location: 1),
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    /// One trip's stretch of line: solid for the primary trip, hatched for an extension.
    @ViewBuilder
    private func tripLine(isPrimary: Bool) -> some View {
        if isPrimary {
            Rectangle().fill(.white.opacity(0.6))
        } else {
            Canvas { context, size in
                var path = Path()
                let stripe: CGFloat = 2, spacing: CGFloat = 5
                var x = -size.height
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: size.height))
                    path.addLine(to: CGPoint(x: x + size.height, y: 0))
                    x += spacing
                }
                context.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: stripe)
            }
            .clipped()
        }
    }

    /// The row's cells: each day, with every run of gap days between the user's trips
    /// folded into one.
    private var cells: [Cell] {
        var cells: [Cell] = []
        for day in days {
            if day.isGap, case .gap(let run) = cells.last {
                cells[cells.count - 1] = .gap(run + [day])
            } else {
                cells.append(day.isGap ? .gap([day]) : .day(day))
            }
        }
        return cells
    }

    private enum Cell: Identifiable {
        case day(ItineraryDay)
        /// A run of gap days, shown as plain dates rather than a circle.
        case gap([ItineraryDay])

        var id: String {
            switch self {
            case .day(let day): "day-\(day.dayNumber)"
            case .gap(let days): "gap-\(days.first?.dayNumber ?? 0)"
            }
        }
    }

    /// The dates of a gap between the user's trips as plain text, e.g. "Dec 5", or the
    /// first and last with a short rule between them. Sized like a day circle, so the
    /// row keeps its rhythm across the gap.
    private func gapCell(_ gapDays: [ItineraryDay]) -> some View {
        let dates = gapDays.compactMap(\.calendarDate).map { $0.formatted(.dateTime.month(.abbreviated).day()) }
        let first = dates.first ?? "", last = dates.last ?? ""
        let isRange = dates.count > 1
        return VStack(spacing: 4) {
            Text(first)
            if isRange {
                Capsule()
                    .frame(width: 10, height: 1.5)
                Text(last)
            }
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Color.appForeground.opacity(0.6))
        .shadow(color: .black.opacity(0.4), radius: 3, y: 1)
        .frame(width: 56, height: 56)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isRange ? "No trip \(first) to \(last)" : "No trip \(first)")
    }

    /// A small dark plus disc past the first or last day, for adding days on that side.
    /// Smaller than the day circles so it reads as an action, not another day.
    @ViewBuilder
    private func segmentEnd(_ edge: HorizontalEdge) -> some View {
        if segmentEdges.contains(edge) {
            addSegmentButton(edge)
        } else {
            Color.clear
        }
    }

    private func addSegmentButton(_ edge: HorizontalEdge) -> some View {
        Button {
            onAddSegment(edge)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.appForeground.opacity(0.9))
                .frame(width: 36, height: 36)
                .background(Color(white: 0.1).opacity(0.9), in: .circle)
                .overlay(Circle().strokeBorder(Color(white: 0.28), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(edge == .leading ? "Add a segment before the trip" : "Add a segment after the trip")
    }

    private func dayCell(_ day: ItineraryDay) -> some View {
        let isSelected = day.dayNumber == selection
        return Button {
            selection = day.dayNumber
        } label: {
            VStack(spacing: 0.5) {
                Text(day.weekdayShort)
                    .font(.system(size: 7, weight: .semibold))
                    .tracking(1)
                    .opacity(0.75)
                Text("\(day.dayOfMonth)")
                    .font(.system(size: 18, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color(white: 0.15) : Color.appForeground.opacity(0.9))
            .frame(width: 56, height: 56)
            // Not `.interactive()` glass: that swells the circle while it's held.
            .glassEffect(
                isSelected ? .regular.tint(Color(white: 0.9)) : .clear,
                in: .circle
            )
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .animation(.easeInOut(duration: 0.25), value: isSelected)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}
