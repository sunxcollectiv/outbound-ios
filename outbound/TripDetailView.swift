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
    /// The stay whose lodging popup is open, from tapping its lodging bar.
    @State private var popupLodging: TripItem?

    /// Live horizontal progress of an in-flight page swipe, in day-units
    /// (-1…1, negative dragging toward a later day). Lets the day picker track
    /// the drag and settle in sync with the page.
    @State private var pageDragProgress: CGFloat = 0

    /// Flips once when the itinerary first shows, playing the entrance animation: the
    /// pinned header and lodging and the day picker fade in, then each card slides in
    /// after the one before, then the Add Activity line. Never reset, so reloads and
    /// later pages don't replay it.
    @State private var hasRevealed = false

    /// Height of the pinned header block, so the cards can scroll up underneath it and
    /// fade out at its top edge.
    @State private var pinnedHeight: CGFloat = 0

    /// How far each day's page has scrolled toward revealing the top fade, 0 at rest to
    /// 1 once scrolled `topFadeReach`. Keyed by day number.
    @State private var topFadeProgress: [Int: CGFloat] = [:]

    /// How far below the pinned block cards start fading once a page is scrolled.
    private static let topFadeReach: CGFloat = 60

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
                    // The pages draw past their top edge so cards slide up under the
                    // pinned block; this cuts them off at the block's top, fading in over
                    // the first stretch so they dissolve rather than end at a hard line.
                    .mask(alignment: .top) {
                        VStack(spacing: 0) {
                            LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
                                .frame(height: 32)
                            Rectangle()
                        }
                        .padding(.top, -max(pinnedHeight - 8, 0))
                    }
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
        // The system bar is replaced by the header chip pinned above the itinerary.
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            // The header and the day's lodging stay pinned while the cards scroll, joined
            // into one block: square where they meet, rounded on the outside.
            VStack(spacing: 0) {
                header(joinsLodging: selectedDay != nil)
                if let selectedDay {
                    if selectedDay.lodging.isEmpty {
                        addLodgingStrip(for: selectedDay)
                    } else {
                        lodgingStrip(selectedDay.lodging.sorted { $0.phase.dayOrder < $1.phase.dayOrder })
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pinnedHeight = $0 }
            .revealIn(hasRevealed || days == nil)
        }
        .overlay { lodgingPopup }
        .sheet(item: $addItemRequest) { request in
            TripItemFormView(tripId: trip.id, defaultZone: defaultNewItemZone, defaultDate: request.date, defaultKind: request.kind, onSaved: { saved in
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

    // MARK: - Header

    /// A solid chip standing in for the navigation bar: back on the left, then the trip's
    /// title and the day being viewed (left aligned, taking the free width, truncating the
    /// title first), then add and more on the right. Squared off at the bottom when the
    /// day's lodging strip hangs below it.
    private func header(joinsLodging: Bool) -> some View {
        HStack(spacing: 4) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.backward")
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Back")

            HStack(spacing: 6) {
                Text(trip.title)
                if let selectedDay {
                    Text("Day \(selectedDay.dayNumber)")
                        .foregroundStyle(.white.opacity(0.6))
                        .contentTransition(.numericText(value: Double(selectedDay.dayNumber)))
                        .animation(.snappy, value: selectedDay.dayNumber)
                        .fixedSize()
                }
            }
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            Button {
                addItemRequest = AddItemRequest(date: selectedDay?.calendarDate)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Add Item")

            Menu {
                Button("Edit Trip", systemImage: "pencil") {
                    showingEditTrip = true
                }
                Button("Share", systemImage: "square.and.arrow.up") {}
                Button("Delete Trip", systemImage: "trash", role: .destructive) {}
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .contentShape(.rect)
            }
            .accessibilityLabel("More")
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            frosted(
                tint: Color.tripHeader.opacity(0.7),
                in: .rect(
                    topLeadingRadius: 10,
                    bottomLeadingRadius: joinsLodging ? 0 : 10,
                    bottomTrailingRadius: joinsLodging ? 0 : 10,
                    topTrailingRadius: 10
                )
            )
        )
    }

    /// A frosted fill for the pinned header: blurs the cards scrolling underneath, with
    /// `tint` laid over the blur. Kept dark whatever the system appearance.
    private func frosted(tint: Color, in shape: some Shape) -> some View {
        shape
            .fill(.ultraThinMaterial)
            .overlay(shape.fill(tint))
            .environment(\.colorScheme, .dark)
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
                if day.entries.isEmpty && day.lodging.isEmpty {
                    Text("Nothing planned")
                        .font(.subheadline)
                        .foregroundStyle(Color.appForeground.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)
                        .revealIn(hasRevealed, delay: Self.cardRevealDelay(0))
                } else {
                    ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                        itemRow(entry, topFade: topFadeProgress[day.dayNumber] ?? 0)
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
        // Let cards keep drawing as they scroll up past the top, under the pinned block.
        .scrollClipDisabled()
        // Clamped, so it stops updating once scrolled past the reach.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            min(max((geometry.contentOffset.y + geometry.contentInsets.top) / Self.topFadeReach, 0), 1)
        } action: { _, progress in
            topFadeProgress[day.dayNumber] = progress
        }
    }

    /// When the card at `index` starts its entrance: just after the pinned header and
    /// day picker, then each card a beat after the one before. Capped so a long day
    /// doesn't keep the cards further down waiting.
    private static func cardRevealDelay(_ index: Int) -> Double {
        0.12 + Double(min(index, 6)) * 0.07
    }

    // MARK: - Rows

    private func itemRow(_ entry: ItineraryEntry, topFade: CGFloat) -> some View {
        ItineraryEntryCard(entry: entry, places: places, placeDetails: placeDetails)
            .contentShape(.rect)
            // Every entry of an item (each end, each layover) opens the same record.
            .onTapGesture { selectedItem = entry.item }
            .mask {
                GeometryReader { geo in
                    let detailHeight = geo.bounds(of: .named(Self.detailSpace))?.height ?? geo.size.height
                    cardFadeGradient(cardFrame: geo.frame(in: .named(Self.detailSpace)), detailHeight: detailHeight, topFade: topFade)
                }
            }
    }

    /// A per-card vertical gradient that fades the card as it scrolls into either band
    /// where chrome sits over the itinerary: down into the day picker at the bottom, or
    /// up under the pinned header block at the top. Each fades to a 30% floor. Driven
    /// purely by the card's own position, so only the cards fade, not the chrome.
    private func cardFadeGradient(cardFrame: CGRect, detailHeight: CGFloat, topFade: CGFloat) -> LinearGradient {
        let minOpacity = 0.3

        // The bottom band, measured up from the bottom of the detail view, roughly
        // covering the day picker. Content below `bottomFadeStart` fades down.
        let bottomFadeHeight: CGFloat = 120
        let bottomFadeStart = detailHeight - bottomFadeHeight

        // The top band runs from below the pinned block (whose bottom edge is y = 0 here)
        // up to the block's top edge, where the pager's mask cuts the cards off. It
        // reaches further below the block as the page scrolls (`topFade`, 0…1), so cards
        // at rest stay crisp. Content above `topFadeStart` fades down.
        let topFadeStart = Self.topFadeReach * topFade
        let topFadeEnd = -pinnedHeight
        let topFadeHeight = max(topFadeStart - topFadeEnd, 1)

        func opacity(atY y: CGFloat) -> Double {
            let bottom = min(max((y - bottomFadeStart) / bottomFadeHeight, 0), 1)
            let top = min(max((topFadeStart - y) / topFadeHeight, 0), 1)
            return minOpacity + (1 - minOpacity) * Double(1 - max(bottom, top))
        }

        // Stops at the card's edges and at every point where the fade curve bends, so
        // the parts of the card outside both bands stay fully opaque.
        let height = max(cardFrame.height, 1)
        let bends = [topFadeEnd, topFadeStart, bottomFadeStart, detailHeight]
            .filter { $0 > cardFrame.minY && $0 < cardFrame.maxY }
        let ys = ([cardFrame.minY] + bends + [cardFrame.maxY]).sorted()
        let stops = ys.map { y in
            Gradient.Stop(color: .white.opacity(opacity(atY: y)), location: (y - cardFrame.minY) / height)
        }

        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }

    /// The day's lodging as one band of equal-width halves, so a changeover day shows its
    /// check-out and check-in side by side, split by a faint line. Square on top, where it
    /// meets the header.
    ///
    /// A day with a lone check-in or check-out gives the stay 75% of the width and
    /// hatches the rest, on the side with no lodging: before arriving, or after leaving.
    private func lodgingStrip(_ lodging: [LodgingStay]) -> some View {
        Group {
            if lodging.count == 1, let stay = lodging.first, stay.phase != .staying {
                FractionSplit(leadingFraction: stay.phase == .checkIn ? 0.25 : 0.75) {
                    // A solid line marks where the stay begins or ends.
                    if stay.phase == .checkIn {
                        DiagonalHatch()
                            .overlay(alignment: .trailing) { hatchEdge }
                        lodgingRow(stay)
                    } else {
                        lodgingRow(stay)
                        DiagonalHatch()
                            .overlay(alignment: .leading) { hatchEdge }
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(lodging.enumerated()), id: \.element.item.id) { index, stay in
                        if index > 0 {
                            Rectangle()
                                .fill(.white.opacity(0.15))
                                .frame(width: 1)
                                .padding(.vertical, 8)
                        }
                        lodgingRow(stay)
                    }
                }
            }
        }
        // Size the separators and hatching to the strip's height.
        .fixedSize(horizontal: false, vertical: true)
        // Plain translucent fill, dark enough that cards scrolling underneath don't
        // compete with the lodging names.
        .background(Color(white: 0.12).opacity(0.8))
        .clipShape(.rect(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
    }

    /// A fully hatched strip for a day with no lodging, inviting one to be added: opens
    /// the add form set to lodging on that day.
    private func addLodgingStrip(for day: ItineraryDay) -> some View {
        Button {
            addItemRequest = AddItemRequest(date: day.calendarDate, kind: .lodging)
        } label: {
            // Sized by an invisible line in the lodging rows' font, so the block keeps
            // the same height when swiping between days with and without lodging.
            ZStack {
                Text(verbatim: " ")
                    .font(.subheadline.weight(.semibold))
                    .hidden()
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                    Text("add lodging")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appForeground.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(DiagonalHatch())
            .background(Color(white: 0.12).opacity(0.8))
            .clipShape(.rect(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// What to call a stay: its place's name, as the itinerary cards do, else its own
    /// title (which may be something generic like "Check-in").
    private func lodgingName(_ stay: LodgingStay) -> String {
        lodgingName(stay.item)
    }

    private func lodgingName(_ item: TripItem) -> String {
        let place = places.current(item.place)
        return place?.googlePlaceId.flatMap { placeDetails[$0] }?.name ?? place?.name ?? item.title
    }

    private func showLodgingPopup(_ item: TripItem) {
        withAnimation(.snappy(duration: 0.25)) { popupLodging = item }
    }

    private func closeLodgingPopup() {
        withAnimation(.snappy(duration: 0.2)) { popupLodging = nil }
    }

    /// The open lodging popup over a dimmed screen; tapping outside closes it.
    @ViewBuilder
    private var lodgingPopup: some View {
        if let item = popupLodging {
            let place = places.current(item.place)
            let name = lodgingName(item)
            let address = place?.googlePlaceId.flatMap { placeDetails[$0] }?.address ?? place?.address
            ZStack {
                Color.black.opacity(0.8)
                    .ignoresSafeArea()
                    .onTapGesture { closeLodgingPopup() }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                LodgingPopup(
                    name: name,
                    address: address,
                    googlePlaceId: place?.googlePlaceId,
                    onClose: closeLodgingPopup
                )
                .transition(.scale(scale: 0.94).combined(with: .opacity))
            }
        }
    }

    /// The solid line between a lone check-in or check-out and its hatched remainder.
    private var hatchEdge: some View {
        Rectangle()
            .fill(Color(white: 0.35))
            .frame(width: 1)
    }

    /// A lodging chip: bed icon and name, with an arrow marking the phase, on the left
    /// for a check-in (arriving) and on the right for a check-out (leaving). A stay in
    /// progress shows "Staying" instead.
    private func lodgingRow(_ stay: LodgingStay) -> some View {
        HStack(spacing: 8) {
            if stay.phase == .checkIn {
                lodgingArrow.padding(.trailing, 7)
            }
            Image(systemName: "bed.double.fill")
                .font(.caption)
            Text(lodgingName(stay))
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
            if stay.phase == .staying {
                Text(stay.phase.label)
                    .font(.caption)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
                    .fixedSize()
            }
            if stay.phase == .checkOut {
                lodgingArrow.padding(.leading, 7)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .contentShape(.rect)
        .onTapGesture { showLodgingPopup(stay.item) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lodgingName(stay)), \(stay.phase.label)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showLodgingPopup(stay.item) }
    }

    private var lodgingArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(Color(white: 0.15))
            .frame(width: 16, height: 16)
            .background(Color.appForeground, in: .circle)
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
    var kind: TripItemKind = .activity
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
            // Clip the neighboring pages off the sides only, so cards can still draw
            // above the top edge as they scroll under the pinned header.
            .clipShape(HorizontalClip())
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

/// Clips to its frame's width but leaves it unbounded vertically.
private struct HorizontalClip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: rect.minX, y: rect.minY - 10_000, width: rect.width, height: rect.height + 20_000))
    }
}

/// Lays out two views side by side, the first taking `leadingFraction` of the width and
/// the second the rest, both as tall as the taller of the two.
private struct FractionSplit: Layout {
    var leadingFraction: CGFloat

    private func widths(for total: CGFloat) -> [CGFloat] {
        [total * leadingFraction, total * (1 - leadingFraction)]
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
        let height = zip(subviews, widths(for: width))
            .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: proposal.height)).height }
            .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths(for: bounds.width)) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width
        }
    }
}

/// Faint diagonal stripes filling the space they're given, marking part of the lodging
/// strip with no stay.
private struct DiagonalHatch: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 7
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}
