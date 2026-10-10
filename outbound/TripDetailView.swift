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

    /// Live horizontal progress of an in-flight page swipe, in day-units
    /// (-1…1, negative dragging toward a later day). Lets the day picker track
    /// the drag and settle in sync with the page.
    @State private var pageDragProgress: CGFloat = 0

    private let api = APIClient.shared

    /// Coordinate space used to measure each card's position for the fade behind the picker.
    private static let detailSpace = "itineraryDetail"

    init(trip: Trip, days: [ItineraryDay]? = nil) {
        self.trip = trip
        _days = State(initialValue: days)
        _selection = State(initialValue: days?.first?.dayNumber ?? 1)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            background

            if let days {
                dayPager(days)
                    .ignoresSafeArea(edges: .bottom)
                    // Pin the day picker on top of the itinerary as an overlay, so its
                    // (wide, scrollable) content can never grow the pager or change the
                    // width of the page content behind it.
                    .overlay(alignment: .bottom) {
                        DaySelectorBar(days: days, selection: $selection, dragProgress: pageDragProgress)
                    }
            } else if let errorMessage {
                errorState(errorMessage)
            } else {
                loadingScaffold
            }
        }
        .coordinateSpace(.named(Self.detailSpace))
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

    // MARK: - Background

    /// Full-page trip backdrop: a destination photo laid over a very dark gray base,
    /// dialed back to ~30% so it reads as a subtle ambient wash rather than competing
    /// with the itinerary content. (Placeholder Melbourne shot until per-trip imagery
    /// is wired up.)
    private var background: some View {
        Color(white: 0.12)
            .ignoresSafeArea()
            .overlay {
                Image("MelbourneBackground")
                    .resizable()
                    .scaledToFill()
                    .opacity(0.2)
                    .clipped()
                    .ignoresSafeArea()
            }
    }

    // MARK: - Paged days

    private func dayPager(_ days: [ItineraryDay]) -> some View {
        DayPager(days: days, selection: $selection, dragProgress: $pageDragProgress) { day, scrollLocked in
            dayPage(day, scrollLocked: scrollLocked)
        }
    }

    private func dayPage(_ day: ItineraryDay, scrollLocked: Bool) -> some View {
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
        .scrollDisabled(scrollLocked)
    }

    // MARK: - Rows

    @ViewBuilder
    private func itemRow(_ item: TripItem) -> some View {
        Group {
            if item.kind == .transit {
                transitCard(item)
            } else {
                coverCard(item)
            }
        }
        .mask {
            GeometryReader { geo in
                let detailHeight = geo.bounds(of: .named(Self.detailSpace))?.height ?? geo.size.height
                cardFadeGradient(cardFrame: geo.frame(in: .named(Self.detailSpace)), detailHeight: detailHeight)
            }
        }
    }

    /// A per-card vertical gradient that fades the card as it scrolls down into the
    /// band where the day picker sits — top stays more opaque than the bottom, down
    /// to a 30% floor. Driven purely by the card's own position, so only the cards
    /// fade; the picker and its gradient are untouched.
    private func cardFadeGradient(cardFrame: CGRect, detailHeight: CGFloat) -> LinearGradient {
        // The band, measured up from the bottom of the detail view, roughly covering
        // the day picker. Content below `fadeTop` fades down to `minOpacity`.
        let fadeHeight: CGFloat = 120
        let minOpacity = 0.3
        let fadeTop = detailHeight - fadeHeight

        func opacity(atY y: CGFloat) -> Double {
            let t = (y - fadeTop) / fadeHeight
            return minOpacity + (1 - minOpacity) * Double(1 - min(max(t, 0), 1))
        }

        let height = max(cardFrame.height, 1)
        var stops: [Gradient.Stop] = [
            .init(color: .white.opacity(opacity(atY: cardFrame.minY)), location: 0)
        ]
        // Pin a fully-opaque stop where the fade begins, so the part of the card
        // sitting above the band never fades.
        let fadeTopLocation = (fadeTop - cardFrame.minY) / height
        if fadeTopLocation > 0 && fadeTopLocation < 1 {
            stops.append(.init(color: .white.opacity(1), location: fadeTopLocation))
        }
        stops.append(.init(color: .white.opacity(opacity(atY: cardFrame.maxY)), location: 1))

        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// A full-width card for a non-transit item: a cover (artwork when the item has
    /// one, otherwise a placeholder) with time + status overlaid, the title across
    /// its bottom, and an attached info strip carrying the notes and an assignee avatar.
    private func coverCard(_ item: TripItem) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                coverImage
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

            HStack {
                locationLabel
                Spacer()
                assigneeAvatar
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(Color.appCard)
        }
        .clipShape(.rect(cornerRadius: 16))
        .padding(.vertical, 6)
    }

    /// The cover image for every card. A single bundled dummy photo stands in until
    /// real per-item artwork is wired up.
    private var coverImage: some View {
        Image("DummyCover")
            .resizable()
            .scaledToFill()
    }

    /// A cover-less card for transit items: the same box as a cover card minus the
    /// image — time + status across the top, the title, then a location row with the
    /// assignee avatar.
    private func transitCard(_ item: TripItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(item.startsAt, format: .dateTime.hour().minute())
                    .monospacedDigit()
                Spacer()
                Text(statusLabel(item))
                    .tracking(1.5)
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.appForeground.opacity(0.7))

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title)
                        .font(.title3.weight(.bold))
                    locationLabel
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                assigneeAvatar
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard, in: .rect(cornerRadius: 16))
        .padding(.vertical, 6)
    }

    /// Placeholder for an item's location, which the backend doesn't send yet.
    private var locationLabel: some View {
        Text("[location]")
            .font(.caption)
            .tracking(1)
            .foregroundStyle(Color.appForeground.opacity(0.7))
    }

    /// The thin circular stand-in for an item's assignee avatar.
    private var assigneeAvatar: some View {
        Circle()
            .strokeBorder(Color.appForeground.opacity(0.35), lineWidth: 1)
            .frame(width: 30, height: 30)
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
    /// Live swipe progress published outward (-1…1) so the day picker can track the drag.
    @Binding var dragProgress: CGFloat
    @ViewBuilder let content: (ItineraryDay, Bool) -> Content

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
            // Lock vertical scrolling once a swipe commits to the horizontal axis
            // (and while a page transition animates), so day-paging never fights
            // the inner ScrollView.
            let scrollLocked = (dragDecided && dragHorizontal) || isAnimating

            HStack(spacing: 0) {
                slot(for: -1, width: w, scrollLocked: scrollLocked)
                    .opacity(slotOpacity(for: -1, width: w))
                slot(for: 0, width: w, scrollLocked: scrollLocked)
                    .opacity(slotOpacity(for: 0, width: w))
                slot(for: 1, width: w, scrollLocked: scrollLocked)
                    .opacity(slotOpacity(for: 1, width: w))
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
                        // Pull the day picker along, one day-width per page-width dragged.
                        dragProgress = max(-1, min(1, dragOffset / w))
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
                            withAnimation(.easeOut(duration: 0.2)) {
                                dragOffset = 0
                                dragProgress = 0
                            }
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

    /// Opacity for a slot given the live drag: the outgoing center fades out as pages
    /// slide, while the incoming neighbor stays fully opaque. Driven by `dragOffset`,
    /// so programmatic slides (taps, jumps) animate the same way.
    private func slotOpacity(for position: Int, width w: CGFloat) -> Double {
        guard dragOffset != 0, w > 0, position == 0 else { return 1 }
        let progress = min(abs(dragOffset) / w, 1)
        return Double(1 - progress)                             // outgoing center fades out
    }

    /// The day index shown in a slot, `position` being -1 (left), 0 (center), +1 (right).
    private func dayIndex(for position: Int) -> Int {
        if position == 0 { return index }
        if let incoming, incoming.side == position { return incoming.dayIndex }
        return index + position
    }

    @ViewBuilder
    private func slot(for position: Int, width: CGFloat, scrollLocked: Bool) -> some View {
        let i = dayIndex(for: position)
        if days.indices.contains(i) {
            content(days[i], scrollLocked).frame(width: width)
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
        // Commit the selection up front so the day picker re-centers on the new day
        // in parallel with the page, and retract any live drag-pull to zero — the two
        // motions share the same curve and duration, so the bar settles seamlessly.
        if selection != days[target].dayNumber {
            selection = days[target].dayNumber
        }
        withAnimation(.easeInOut(duration: 0.28), completionCriteria: .logicallyComplete) {
            dragOffset = side > 0 ? -w : w
            dragProgress = 0
        } completion: {
            index = target
            incoming = nil
            dragOffset = 0
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
