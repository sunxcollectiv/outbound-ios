//
//  TripDetailView.swift
//  outbound
//

import SwiftUI

/// The itinerary for a single trip, presented one day per page. You swipe
/// horizontally between days, and a day picker pinned to the bottom stays in
/// sync (tap a day to jump, swipe to scrub). The day-by-day itinerary loads
/// asynchronously, showing placeholder scaffolding while in flight.
struct TripDetailView: View {
    let trip: Trip

    @State private var days: [ItineraryDay]?
    @State private var selection: Int
    @State private var errorMessage: String?
    @State private var showingAddItem = false

    private let api = APIClient.shared

    init(trip: Trip, days: [ItineraryDay]? = nil) {
        self.trip = trip
        _days = State(initialValue: days)
        _selection = State(initialValue: days?.first?.dayNumber ?? 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.appBackground.ignoresSafeArea()

            if let days {
                dayPager(days)
                    .ignoresSafeArea(edges: .bottom)
                DaySelectorBar(days: days, selection: $selection)
            } else if let errorMessage {
                errorState(errorMessage)
            } else {
                loadingScaffold
            }
        }
        .foregroundStyle(Color.appForeground)
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddItem = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Item")
            }
        }
        .sheet(isPresented: $showingAddItem) {
            AddTripItemView(tripId: trip.id, onCreated: { _ in
                Task { await load() }
            })
        }
        .task { if days == nil { await load() } }
    }

    // MARK: - Paged days

    private func dayPager(_ days: [ItineraryDay]) -> some View {
        DayPager(days: days, selection: $selection) { day in
            dayPage(day)
        }
    }

    private func dayPage(_ day: ItineraryDay) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Day \(day.dayNumber)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                    Text(day.displayDate)
                        .font(.title2.bold())
                }
                .padding(.bottom, 4)

                ForEach(day.lodging, id: \.item.id) { stay in
                    lodgingRow(stay)
                }

                if day.items.isEmpty && day.lodging.isEmpty {
                    Text("Nothing planned")
                        .font(.subheadline)
                        .foregroundStyle(Color.appForeground.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                } else {
                    ForEach(day.items) { item in
                        itemRow(item)
                    }
                }

                Button {
                    showingAddItem = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                        Text("ADD ACTIVITY")
                            .tracking(1.5)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                // Clear the bottom day-picker bar.
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Rows

    @ViewBuilder
    private func itemRow(_ item: TripItem) -> some View {
        if let imageUrl = item.imageUrl, !imageUrl.isEmpty {
            featuredCard(item, imageUrl: imageUrl)
        } else {
            HStack(alignment: .top, spacing: 14) {
                Text(item.startsAt, format: .dateTime.hour().minute())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Color.appForeground.opacity(0.85))
                    .frame(width: 52, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes.uppercased())
                            .font(.caption2)
                            .tracking(0.5)
                            .foregroundStyle(Color.appForeground.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
        }
    }

    /// A full-width cover-image card for items with artwork (e.g. a dinner spot):
    /// time + status overlaid on the image, title across its bottom, and an attached
    /// info strip below carrying the location and an assignee avatar.
    private func featuredCard(_ item: TripItem, imageUrl: String) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: imageUrl)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        Color.appCard
                    }
                }
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay {
                    LinearGradient(
                        colors: [.clear, .black.opacity(0.7)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                }
                .overlay(alignment: .top) {
                    HStack {
                        Text(item.startsAt, format: .dateTime.hour().minute())
                            .monospacedDigit()
                        Spacer()
                        Text(statusLabel(item))
                            .tracking(1.5)
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(14)
                }

                Text(item.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(14)
            }

            if let notes = item.notes, !notes.isEmpty {
                HStack {
                    Text(notes.uppercased())
                        .font(.caption)
                        .tracking(1)
                        .foregroundStyle(Color.appForeground.opacity(0.7))
                    Spacer()
                    Circle()
                        .strokeBorder(Color.appForeground.opacity(0.35), lineWidth: 1)
                        .frame(width: 30, height: 30)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Color.appCard.opacity(0.6))
            }
        }
        .clipShape(.rect(cornerRadius: 16))
        .padding(.vertical, 6)
    }

    /// The badge shown top-right of a featured card: the item's first tag if it has
    /// one (e.g. "RESERVED"), otherwise its kind.
    private func statusLabel(_ item: TripItem) -> String {
        (item.tags.first ?? item.kind.label).uppercased()
    }

    private func lodgingRow(_ stay: LodgingStay) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bed.double.fill")
                .font(.caption)
            Text(stay.item.title)
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text(stay.phase.label)
                .font(.caption)
                .foregroundStyle(Color.appForeground.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Color.appForeground.opacity(0.1), in: .rect(cornerRadius: 10))
    }

    // MARK: - Loading / error

    private var loadingScaffold: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                DashedPlaceholder(height: 28)
                    .frame(width: 160)
                ForEach(0..<3, id: \.self) { _ in
                    HStack(alignment: .top, spacing: 12) {
                        DashedPlaceholder(height: 44)
                            .frame(width: 52)
                        DashedPlaceholder("Itinerary item", height: 72)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appForeground.opacity(0.8))
                .multilineTextAlignment(.center)
            Button("Try Again") {
                Task { await load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func load() async {
        do {
            let itinerary = try await api.send(TripsAPI.itinerary(tripId: trip.id), as: Itinerary.self)
            days = itinerary.days
            selection = itinerary.days.first?.dayNumber ?? 1
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The day picker pinned to the bottom of the itinerary: a dark glassy bar with a
/// circular button per day (weekday label above, day-of-month inside the circle).
/// The selected day is a filled cream disc; tapping a day scrubs the pager and the
/// bar stays in sync with the current `selection`.
private struct DaySelectorBar: View {
    let days: [ItineraryDay]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                dayCell(day)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 40)
        .padding(.horizontal, 12)
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
            ZStack {
                Circle()
                    .fill(isSelected ? Color.appForeground : Color.clear)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.appForeground.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
                    }

                VStack(spacing: 1.4) {
                    Text(day.weekdayShort)
                        .font(.system(size: 7, weight: .semibold))
                        .tracking(1)
                        .opacity(0.75)
                    Text("\(day.dayOfMonth)")
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(isSelected ? Color.appBackground : Color.appForeground.opacity(0.9))
            }
            .frame(width: 56, height: 56)
            .animation(.easeInOut(duration: 0.25), value: isSelected)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
    }
}

/// A horizontally paged container that renders only the current day and its
/// immediate neighbors, so swiping never scrolls through intermediate pages.
///
/// A swipe commits to the adjacent day (±1). Changing `selection` from elsewhere
/// (the day picker) slides a single transition toward the target — entering from
/// the right if it's a later day, from the left if earlier — with the far target
/// placed directly in the neighbor slot so nothing in between is ever built.
private struct DayPager<Content: View>: View {
    let days: [ItineraryDay]
    @Binding var selection: Int
    @ViewBuilder let content: (ItineraryDay) -> Content

    @State private var index = 0
    @State private var dragOffset: CGFloat = 0
    @State private var pageWidth: CGFloat = 0
    @State private var isAnimating = false

    /// A far jump places its target in one neighbor slot: `(side, dayIndex)`,
    /// where `side` is -1 for the left slot or +1 for the right.
    @State private var incoming: (side: Int, dayIndex: Int)?

    // Per-gesture axis lock so vertical scrolling isn't hijacked by the pager.
    @State private var dragDecided = false
    @State private var dragHorizontal = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let hasLeft = index > 0
            let hasRight = index < days.count - 1

            HStack(spacing: 0) {
                slot(for: -1, width: w)
                slot(for: 0, width: w)
                slot(for: 1, width: w)
            }
            .frame(width: w * 3, alignment: .leading)
            .offset(x: -w + dragOffset)
            .frame(width: w, height: geo.size.height, alignment: .leading)
            .clipped()
            .contentShape(.rect)
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { value in
                        guard !isAnimating else { return }
                        let t = value.translation
                        if !dragDecided {
                            dragDecided = true
                            dragHorizontal = abs(t.width) > abs(t.height)
                        }
                        guard dragHorizontal else { return }
                        if (t.width > 0 && !hasLeft) || (t.width < 0 && !hasRight) {
                            dragOffset = t.width * 0.25 // resist past the ends
                        } else {
                            dragOffset = t.width
                        }
                    }
                    .onEnded { value in
                        defer { dragDecided = false; dragHorizontal = false }
                        guard !isAnimating, dragHorizontal else { return }
                        let t = value.translation.width
                        let threshold = w * 0.25
                        if t < -threshold && hasRight {
                            slide(to: index + 1, width: w)
                        } else if t > threshold && hasLeft {
                            slide(to: index - 1, width: w)
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) { dragOffset = 0 }
                        }
                    }
            )
            .onAppear {
                pageWidth = w
                index = days.firstIndex { $0.dayNumber == selection } ?? 0
            }
            .onChange(of: w) { _, newWidth in pageWidth = newWidth }
        }
        .onChange(of: selection) { _, newValue in
            guard let target = days.firstIndex(where: { $0.dayNumber == newValue }),
                  target != index, !isAnimating, pageWidth > 0 else { return }
            slide(to: target, width: pageWidth)
        }
    }

    /// The day index shown in a slot, `position` being -1 (left), 0 (center), +1 (right).
    private func dayIndex(for position: Int) -> Int {
        if position == 0 { return index }
        if let incoming, incoming.side == position { return incoming.dayIndex }
        return index + position
    }

    @ViewBuilder
    private func slot(for position: Int, width: CGFloat) -> some View {
        let i = dayIndex(for: position)
        if days.indices.contains(i) {
            content(days[i]).frame(width: width)
        } else {
            Color.clear.frame(width: width)
        }
    }

    /// Slides a single page toward `target` and settles on it. For a non-adjacent
    /// target the day is dropped into the neighbor slot so no intermediate page renders.
    private func slide(to target: Int, width w: CGFloat) {
        guard target != index, w > 0 else { return }
        isAnimating = true
        let side = target > index ? 1 : -1
        if abs(target - index) > 1 {
            incoming = (side: side, dayIndex: target)
        }
        withAnimation(.easeInOut(duration: 0.28), completionCriteria: .logicallyComplete) {
            dragOffset = side > 0 ? -w : w
        } completion: {
            index = target
            incoming = nil
            dragOffset = 0
            if selection != days[target].dayNumber {
                selection = days[target].dayNumber
            }
            isAnimating = false
        }
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: .sample, days: ItineraryDay.sampleDays)
    }
    .appTheme()
}
