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
    @State private var trip: Trip

    @State private var days: [ItineraryDay]?
    /// The trip's days keyed by date, for the zones to default the add-item picker to.
    /// Loaded alongside the itinerary (which doesn't carry zones yet) and joined on date.
    @State private var dayTimeZones: [String: [TimeZone]] = [:]
    /// Google Place Details for every place in the itinerary, keyed by google place id.
    /// The backend enriches its own place records (name/address) asynchronously, so
    /// those are often still null here; we fetch Google's copy once and cache it so
    /// cards can show a location immediately. See `loadPlaceDetails(for:)`.
    @State private var placeDetails: [String: PlaceDetails] = [:]
    /// One copy of each place in the itinerary, by id, which every card and the item
    /// sheet read from. Patched in place when stale places come back refreshed, so all
    /// cards for a place update together. See `refreshStalePlaces(_:)`.
    @State private var places = ItineraryPlaces()
    @State private var selection: Int
    @State private var errorMessage: String?
    /// A pending add-item sheet, carrying the day that was shown when add was tapped.
    /// Presented via `.sheet(item:)` so the form receives the value directly; with
    /// `.sheet(isPresented:)` the content closure could capture a stale date.
    @State private var addItemRequest: AddItemRequest?
    @State private var showingEditTrip = false
    @State private var selectedItem: TripItem?

    /// Live horizontal progress of an in-flight page swipe, in day-units
    /// (-1…1, negative dragging toward a later day). Lets the day picker track
    /// the drag and settle in sync with the page.
    @State private var pageDragProgress: CGFloat = 0

    /// Flips once when the itinerary first shows, playing the entrance animation: the
    /// lodging chips and day picker fade in, then each card slides in after the one before, then
    /// the Add Activity line. Never reset, so reloads and later pages don't replay it.
    @State private var hasRevealed = false

    @Environment(\.dismiss) private var dismiss

    private let api = APIClient.shared

    /// Coordinate space used to measure each card's position for the fade behind the picker.
    private static let detailSpace = "itineraryDetail"

    init(trip: Trip, days: [ItineraryDay]? = nil) {
        _trip = State(initialValue: trip)
        _days = State(initialValue: days)
        // Back on the day last viewed when the trip was opened within the hour; a day
        // that no longer exists falls back to the first once the itinerary loads.
        _selection = State(initialValue: days?.first?.dayNumber ?? LastVisitedDay.dayNumber(for: trip.id) ?? 1)
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
                            .revealIn(hasRevealed)
                    }
                    // A task rather than onAppear: the pager settles on the selected day in
                    // its own onAppear, and revealing in that same update would animate the
                    // page swap (ghosting the old page) and skip the incoming cards' entrance.
                    .task { hasRevealed = true }
            } else if let errorMessage {
                errorState(errorMessage)
            }
        }
        .coordinateSpace(.named(Self.detailSpace))
        // The navigation container's own backdrop, which the zoom transition shows
        // around the screen while it scales; left alone it's the system's white.
        .containerBackground(Color(white: 0.12), for: .navigation)
        .foregroundStyle(Color.appForeground)
        .navigationTitle(trip.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(Color.appBackground, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            // The trip's title with the day being viewed beside it, in place of a header
            // on each page. The title truncates first so the day always shows.
            ToolbarItem(placement: .principal) {
                HStack(spacing: 6) {
                    Text(trip.title)
                        .foregroundStyle(.white)
                    if let selectedDay {
                        Text("Day \(selectedDay.dayNumber)")
                            .foregroundStyle(.white.opacity(0.55))
                            .contentTransition(.numericText(value: Double(selectedDay.dayNumber)))
                            .animation(.snappy, value: selectedDay.dayNumber)
                            .fixedSize()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            AppToolbarButton(placement: .topBarLeading) {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .accessibilityLabel("Back")
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 4) {
                    Button {
                        addItemRequest = AddItemRequest(date: selectedDay?.calendarDate)
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add Item")
                    }
                    Menu {
                        Button("Edit Trip", systemImage: "pencil") {
                            showingEditTrip = true
                        }
                        Button("Share", systemImage: "square.and.arrow.up") {}
                        Button("Delete Trip", systemImage: "trash", role: .destructive) {}
                    } label: {
                        Image(systemName: "ellipsis")
                            .accessibilityLabel("More")
                    }
                }
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .sheet(item: $addItemRequest) { request in
            TripItemFormView(tripId: trip.id, defaultZone: defaultNewItemZone, defaultDate: request.date, onSaved: { saved in
                Task { await load(focusItemId: saved.id) }
            })
        }
        .sheet(isPresented: $showingEditTrip) {
            TripFormView(trip: trip) { updated in
                trip = updated
                // Dates may have shifted, so rebuild the day-by-day itinerary.
                Task { await load() }
            }
        }
        .sheet(item: $selectedItem) { item in
            TripItemDetailView(item: places.resolving(item)) { saved in
                Task { await load(focusItemId: saved.id) }
            }
        }
        .task { if days == nil { await load() } }
        .onDisappear {
            if days != nil { LastVisitedDay.record(selection, for: trip.id) }
        }
    }

    // MARK: - Background

    /// The trip's cover art (the same image as its tile in the grid), dimmed to a dark
    /// wash so the cards stay legible. Matching the tile lets the zoom transition read
    /// as the tile growing into this screen.
    private var background: some View {
        Color(white: 0.12)
            .ignoresSafeArea()
            .overlay {
                TripCover(trip: trip, showsAttribution: false)
                    .overlay { Color(white: 0.12).opacity(0.8) }
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
                ForEach(day.lodging, id: \.item.id) { stay in
                    lodgingRow(stay)
                        .revealIn(hasRevealed)
                }

                if day.entries.isEmpty && day.lodging.isEmpty {
                    Text("Nothing planned")
                        .font(.subheadline)
                        .foregroundStyle(Color.appForeground.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .revealIn(hasRevealed, delay: Self.cardRevealDelay(0))
                } else {
                    ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                        itemRow(entry)
                            .revealIn(hasRevealed, delay: Self.cardRevealDelay(index), slide: 16)
                    }
                }

                // Centered between faint rules that run out to the content's edges.
                HStack(spacing: 12) {
                    addActivityRule
                    Button {
                        addItemRequest = AddItemRequest(date: day.calendarDate)
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
                    // Keep the label on one line; the rules take whatever width is left.
                    .fixedSize()
                    addActivityRule
                }
                .padding(.top, 14)
                .padding(.bottom, 10)
                .revealIn(hasRevealed, delay: Self.cardRevealDelay(day.entries.count) + 0.05)

                // Clear the bottom day-picker bar.
                Color.clear.frame(height: 120)
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollDisabled(scrollLocked)
    }

    /// When the card at `index` starts its entrance: just after the lodging chips and day picker, then each
    /// card a beat after the one before. Capped so a long day doesn't keep the cards
    /// further down waiting.
    private static func cardRevealDelay(_ index: Int) -> Double {
        0.12 + Double(min(index, 6)) * 0.07
    }

    // MARK: - Rows

    private func itemRow(_ entry: ItineraryEntry) -> some View {
        ItineraryEntryCard(entry: entry, places: places, placeDetails: placeDetails)
            .contentShape(.rect)
            // Every entry of an item (each end, each layover) opens the same record.
            .onTapGesture { selectedItem = entry.item }
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
        .contentShape(.rect)
        .onTapGesture { selectedItem = stay.item }
    }

    /// A faint hairline flanking the Add Activity button.
    private var addActivityRule: some View {
        Rectangle()
            .fill(Color.appForeground.opacity(0.2))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Error

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

    /// The day currently shown in the pager.
    private var selectedDay: ItineraryDay? {
        days?.first(where: { $0.dayNumber == selection })
    }

    /// The zones of the currently shown day, used as a fallback for the add-item picker.
    private var selectedDayTimeZones: [TimeZone] {
        guard let date = selectedDay?.date else { return [] }
        return dayTimeZones[date] ?? []
    }

    /// The zone a newly added item should default to: the zone the traveler is in at the
    /// end of the chronologically last item (its end zone, else its start zone). Falls
    /// back to the selected day's zone when the trip has no items yet or the last one
    /// is zoneless.
    private var defaultNewItemZone: TimeZone? {
        // Zoneless items are ordered by their wall clock read in their day's zone.
        let timed = (days ?? []).flatMap { day in
            let fallback = dayTimeZones[day.date]?.first ?? .current
            return day.uniqueItems.map { item in
                (item, item.endInstant(fallbackZone: fallback) ?? item.startInstant(fallbackZone: fallback))
            }
        }
        if let last = timed.max(by: { $0.1 < $1.1 })?.0,
           let zone = last.endTimezone ?? last.startTimezone {
            return zone
        }
        return selectedDayTimeZones.first
    }

    /// The day to show after a reload: the day holding the just-saved item when given,
    /// otherwise the current day if it still exists, falling back to the first day.
    private func resolveSelection(in days: [ItineraryDay], focusItemId: String?) -> Int {
        if let focusItemId,
           let day = days.first(where: { day in
               day.uniqueItems.contains { $0.id == focusItemId }
           }) {
            return day.dayNumber
        }
        if days.contains(where: { $0.dayNumber == selection }) {
            return selection
        }
        return days.first?.dayNumber ?? 1
    }

    /// Reloads the itinerary. Pass `focusItemId` after a save to land on the day that
    /// item sits on; otherwise the current day is kept (falling back to the first).
    private func load(focusItemId: String? = nil) async {
        do {
            let itinerary = try await api.send(TripsAPI.itinerary(tripId: trip.id), as: Itinerary.self)
            days = itinerary.days
            places = ItineraryPlaces(days: itinerary.days)
            selection = resolveSelection(in: itinerary.days, focusItemId: focusItemId)
            errorMessage = nil
            // The itinerary is already on screen; stale places refresh alongside the
            // Google details and patch their cards when they land.
            async let refresh: Void = refreshStalePlaces(itinerary.stalePlaceIds)
            await loadPlaceDetails(for: itinerary.days)
            await refresh
        } catch {
            errorMessage = error.localizedDescription
        }
        // The day zones are a best-effort join for the add-item picker; a failure here
        // shouldn't block the itinerary, so it's loaded separately and ignored on error.
        if let tripDays = try? await api.send(TripDaysAPI.list(tripId: trip.id), as: [TripDay].self) {
            dayTimeZones = Dictionary(tripDays.map { ($0.date, $0.timeZones) }, uniquingKeysWith: { first, _ in first })
        }
    }

    /// Fetches Google Place Details for every place referenced by the itinerary and
    /// caches them by google place id, so cards can render a name/address even before
    /// the backend has enriched its own place records. Best-effort: places already
    /// cached are skipped, and individual lookups that fail are simply left out.
    private func loadPlaceDetails(for days: [ItineraryDay]) async {
        let ids = Set(days.flatMap(\.places).compactMap(\.googlePlaceId))
        let missing = ids.subtracting(placeDetails.keys)
        guard !missing.isEmpty else { return }

        let fetched = await withTaskGroup(of: (String, PlaceDetails?).self) { group in
            for id in missing {
                group.addTask { (id, try? await GooglePlacesClient.shared.placeDetails(placeId: id)) }
            }
            var results: [String: PlaceDetails] = [:]
            for await (id, details) in group {
                if let details { results[id] = details }
            }
            return results
        }
        placeDetails.merge(fetched) { _, new in new }
    }
}

extension TripDetailView {
    /// Asks the server to refresh the places the itinerary flagged as stale (in batches
    /// of `PlacesAPI.refreshBatchLimit`), then patches the shared copies so every card
    /// for those places picks up the new data, cover photo included. Best-effort: a
    /// failed batch leaves its places as the itinerary delivered them.
    fileprivate func refreshStalePlaces(_ ids: [String]) async {
        guard !ids.isEmpty else { return }
        let batches = stride(from: 0, to: ids.count, by: PlacesAPI.refreshBatchLimit).map {
            Array(ids[$0..<min($0 + PlacesAPI.refreshBatchLimit, ids.count)])
        }
        for batch in batches {
            guard let response = try? await api.send(PlacesAPI.refresh(placeIds: batch), as: PlacesAPI.RefreshResponse.self) else { continue }
            places.update(with: response.places)
        }
    }
}

/// A request to present the add-item form, defaulting to `date`'s calendar day.
private struct AddItemRequest: Identifiable {
    let id = UUID()
    let date: Date?
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

    /// Starts on the selected day rather than the first, so the pager never swaps
    /// pages right after it appears (which would show through the entrance animation).
    @State private var index: Int

    init(
        days: [ItineraryDay],
        selection: Binding<Int>,
        dragProgress: Binding<CGFloat>,
        @ViewBuilder content: @escaping (ItineraryDay, Bool) -> Content
    ) {
        self.days = days
        _selection = selection
        _dragProgress = dragProgress
        self.content = content
        _index = State(initialValue: days.firstIndex { $0.dayNumber == selection.wrappedValue } ?? 0)
    }
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

/// Fades content in, optionally sliding it up, once `isRevealed` turns true.
private struct RevealIn: ViewModifier {
    let isRevealed: Bool
    let delay: Double
    let slide: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(isRevealed ? 1 : 0)
            .offset(y: isRevealed || reduceMotion ? 0 : slide)
            .animation(.easeOut(duration: 0.35).delay(delay), value: isRevealed)
    }
}

private extension View {
    func revealIn(_ isRevealed: Bool, delay: Double = 0, slide: CGFloat = 0) -> some View {
        modifier(RevealIn(isRevealed: isRevealed, delay: delay, slide: slide))
    }
}
