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
                            ForEach(days) { day in
                                dayCell(day)
                                    .frame(width: cellWidth)
                                    .id(day.dayNumber)
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
                .onAppear { proxy.scrollTo(selection, anchor: .center) }
                .onChange(of: selection) { _, newValue in
                    withAnimation(.easeInOut(duration: 0.28)) {
                        proxy.scrollTo(newValue, anchor: .center)
                    }
                }
            }
        }
        .frame(height: 56)
        .padding(.top, 40)
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
