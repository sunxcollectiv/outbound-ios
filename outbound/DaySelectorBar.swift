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

    var body: some View {
        GeometryReader { geo in
            // Five cells span the width; end insets let the first and last day
            // still settle in the center.
            let cellWidth = geo.size.width / 5
            let sideInset = (geo.size.width - cellWidth) / 2

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    GlassEffectContainer(spacing: 20) {
                        HStack(spacing: 0) {
                            ForEach(days) { day in
                                dayCell(day)
                                    .frame(width: cellWidth)
                                    .id(day.dayNumber)
                            }
                        }
                        .padding(.horizontal, sideInset)
                        // Track the itinerary swipe: one day-width of travel per full page drag.
                        .offset(x: dragProgress * cellWidth)
                    }
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
            .glassEffect(
                isSelected
                    ? .regular.tint(Color(white: 0.9)).interactive()
                    : .clear.interactive(),
                in: .circle
            )
            .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
            .animation(.easeInOut(duration: 0.25), value: isSelected)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}
