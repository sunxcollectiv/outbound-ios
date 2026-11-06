//
//  TripDetailView.swift
//  outbound
//

import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// The itinerary for a single trip, presented one day per page. You swipe
/// horizontally between days, and a day picker pinned to the bottom stays in
/// sync (tap a day to jump, swipe to scrub). The day-by-day itinerary loads
/// asynchronously, showing placeholder scaffolding while in flight.
struct TripDetailView: View {
    @State private var trip: Trip

    @State private var days: [ItineraryDay]?
    /// The trips merged into the itinerary (this one and the user's others in its
    /// group), for the members of whichever one an item sits on.
    @State private var itineraryTrips: [Trip] = []
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
    /// When the itinerary showing is the copy saved by an earlier load (opened before
    /// this load finished, or with no connection), the time that copy was saved; nil
    /// once a load succeeds.
    @State private var savedCopyDate: Date?
    /// Whether the last load couldn't reach the server, leaving the saved copy showing.
    @State private var loadFailed = false
    /// A pending add-item sheet, carrying the day that was shown when add was tapped.
    /// Presented via `.sheet(item:)` so the form receives the value directly; with
    /// `.sheet(isPresented:)` the content closure could capture a stale date.
    @State private var addItemRequest: AddItemRequest?
    /// The trip open in the edit form: this one, or the extension the viewed day is on.
    @State private var tripToEdit: Trip?
    /// The trip the delete popup is open for (see `menuTrip`).
    @State private var tripToDelete: Trip?
    /// A pending add-segment sheet, from the day picker's plus at either end.
    @State private var segmentRequest: SegmentRequest?
    /// Whether the dropdown under the header's more button is open.
    @State private var showingTripMenu = false
    /// The status pill above the day picker (an address copied, a screenshot uploading).
    @State private var toast: TripToast?
    /// Hides the current toast after a moment; replaced whenever a new toast shows.
    @State private var toastHideTask: Task<Void, Never>?
    /// Where an in-flight screenshot import has got to, shown in the progress pill;
    /// nil when none is running.
    @State private var importStep: ImportProgressPill.Step?
    /// A fresh id per import, so each one's pill starts from empty.
    @State private var importID = UUID()
    /// The header chip's frame on screen, to hang the trip menu just below its trailing edge.
    @State private var headerFrame: CGRect = .zero
    /// The entry whose details are folded open beneath its card, from tapping it;
    /// tapping it again (or another card) folds them away. Keyed by entry, not item,
    /// so the panel opens under the card that was tapped (a transit's departure or
    /// its arrival).
    @State private var expandedEntryID: ItineraryEntry.ID?
    /// The stay whose lodging popup is open, from tapping its lodging bar.
    @State private var popupLodging: TripItem?
    /// An item opened straight into its edit form: long-pressing its card or lodging
    /// strip, or Edit in the lodging popup.
    @State private var editingItem: TripItem?
    /// Bumped on each long press, to play a haptic as the edit form opens.
    @State private var editHaptic = 0
    /// The day whose add-lodging popup is open, from tapping its empty lodging strip.
    @State private var addLodgingDay: ItineraryDay?
    /// Showing the photo picker for a screenshot of a booking, from the add-lodging popup
    /// or the trip menu.
    @State private var showingBookingImagePicker = false
    /// The booking screenshot picked from the photo picker.
    @State private var bookingImageSelection: PhotosPickerItem?

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

    /// The space under the pinned block before the itinerary starts.
    private static let pinnedBlockBottomPadding: CGFloat = 8

    /// Where the day picker's circles start, in the detail space: the top of the
    /// band the itinerary is fully visible in.
    @State private var dayPickerTop: CGFloat = 0

    /// While the page scrolls an opened card into view; touch scrolling is off so the
    /// two don't fight.
    @State private var isAutoScrolling = false

    /// The card just tapped open, while its details are laid out unseen to measure
    /// them. Nothing moves until that's done; then the details open, any open card
    /// closes and the page scrolls, all in one animation, so they stay in step.
    @State private var measuringEntryID: ItineraryEntry.ID?
    /// The tapped card's row as it sits now, and its details' height, from that
    /// unseen layout.
    @State private var measuredRowFrame: CGRect?
    @State private var measuredPanelHeight: CGFloat?

    /// How much taller the open card's row is than the card alone, so opening
    /// another card can allow for this one closing.
    @State private var openRowExtra: CGFloat = 0

    /// The latest open's id, so a stale cleanup from an earlier one leaves a newer
    /// one alone.
    @State private var autoScrollID = UUID()

    /// Each day page's scroll position and current scroll geometry, by day number.
    /// (A position is only held while an opened card scrolls into place; see
    /// `scrollPositionBinding`.)
    @State private var scrollPositions: [Int: ScrollPosition] = [:]
    @State private var pageScroll: [Int: PageScroll] = [:]

    /// Extra blank space under a day's itinerary while an opened card scrolls into
    /// place. The page's real height only catches up once the details finish
    /// unfolding, so without it a scroll that starts alongside them is cut short at
    /// the old bottom. Removed once the scroll lands, which never goes past the real
    /// bottom, so nothing moves when it goes.
    @State private var scrollRunway: [Int: CGFloat] = [:]
    private static let scrollRunwayHeight: CGFloat = 2000

    /// How long a card's details take to fold open or shut, and the page to scroll
    /// the opened card into place.
    private static let expandDuration: Double = 0.27

    /// The least space left between the pinned block and an opened card too tall to
    /// center.
    private static let expandedHeaderGap: CGFloat = 20

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var auth
    @Environment(CreditStore.self) private var credits

    private let api = APIClient.shared
    private var connectivity = Connectivity.shared

    /// Coordinate space used to measure each card's position for the fade behind the picker.
    private static let detailSpace = "itineraryDetail"

    /// The user's other trips in this trip's group; an end of the day picker one of them
    /// reaches gets no add-segment button.
    private let groupTrips: [Trip]
    /// Called with a segment created from the day picker, for the trip list.
    private let onSegmentCreated: (Trip) -> Void
    /// Called after the trip is deleted from its edit form; the presenter closes this screen.
    private let onDeleted: () -> Void

    init(
        trip: Trip,
        days: [ItineraryDay]? = nil,
        groupTrips: [Trip] = [],
        onSegmentCreated: @escaping (Trip) -> Void = { _ in },
        onDeleted: @escaping () -> Void = {}
    ) {
        self.groupTrips = groupTrips
        self.onSegmentCreated = onSegmentCreated
        self.onDeleted = onDeleted
        _trip = State(initialValue: trip)
        // Without days given, start from the itinerary saved by an earlier load (or the
        // trip list's background save), so it shows at once, and offline; the load
        // then replaces it.
        let endpoint = TripsAPI.itinerary(tripId: trip.id)
        let saved = days == nil ? APIClient.shared.cached(endpoint, as: Itinerary.self) : nil
        _days = State(initialValue: days ?? saved?.days)
        _itineraryTrips = State(initialValue: saved?.trips ?? [])
        _places = State(initialValue: saved.map { ItineraryPlaces(days: $0.days) } ?? ItineraryPlaces())
        _savedCopyDate = State(initialValue: saved == nil ? nil : APIClient.shared.cachedDate(for: endpoint))
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
                        DaySelectorBar(days: days, selection: $selection, dragProgress: pageDragProgress, onAddSegment: { edge in
                            segmentRequest = SegmentRequest(edge: edge)
                        }, segmentEdges: openSegmentEdges, primaryTripId: trip.id)
                        // Below its 40pt fade, where the circles start.
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(Self.detailSpace)).minY + 40 } action: { dayPickerTop = $0 }
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
            .padding(.bottom, Self.pinnedBlockBottomPadding)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { pinnedHeight = $0 }
            .revealIn(hasRevealed || days == nil)
        }
        .overlay { tripMenu }
        .overlay(alignment: .bottom) { offlinePillAnchor }
        .overlay(alignment: .bottom) { toastView }
        .overlay(alignment: .bottom) { importProgressPill }
        .overlay { lodgingPopup }
        .overlay { addLodgingPopup }
        .overlay { deleteTripPopup }
        .offlinePillNearBottom(isActive: popupLodging != nil || addLodgingDay != nil || tripToDelete != nil)
        .photosPicker(isPresented: $showingBookingImagePicker, selection: $bookingImageSelection, matching: .images)
        .onChange(of: bookingImageSelection) { _, item in
            guard let item else { return }
            // Cleared so picking the same image again still triggers an upload.
            bookingImageSelection = nil
            Task { await importScreenshot(item) }
        }
        .sheet(item: $addItemRequest) { request in
            TripItemFormView(tripId: trip.id, kind: request.kind, members: trip.members ?? [], tripsByDate: tripsByDate, tripDates: trip.dateRange, defaultDate: request.date, onSaved: { saved in
                Task { await load(focusItemId: saved.id) }
            })
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: editHaptic)
        .sheet(item: $editingItem) { item in
            TripItemFormView(tripId: item.tripId, members: members(onTripOf: item.tripId), tripDates: trip.dateRange, item: item, viewedDay: selectedDay?.calendarDate) { saved in
                Task { await load(focusItemId: saved.id) }
            } onDeleted: {
                removeItem(item.id)
            }
        }
        .sheet(item: $tripToEdit) { edited in
            TripFormView(
                trip: edited,
                groupPart: TripGroupPart.forEditing(
                    edited, primary: trip, extensions: itineraryTrips.filter { $0.id != trip.id },
                    userId: auth.currentUser?.id
                )
            ) { updated in
                if updated.id == trip.id { trip = updated }
                // Dates may have shifted, so rebuild the day-by-day itinerary.
                Task { await load() }
            } onDeleted: {
                tripDeleted(edited)
            }
        }
        .sheet(item: $segmentRequest) { request in
            TripFormView(segmentOf: trip, segmentEdge: request.edge) { segment in
                onSegmentCreated(segment)
                // The itinerary merges the user's trips in a group, so it now has the new days.
                Task { await load() }
                showToast(TripToast(text: "Added \(segment.title)", systemImage: "checkmark.circle.fill"))
            }
        }
        .task { if days == nil || savedCopyDate != nil { await load() } }
        .onChange(of: connectivity.isConnected) { _, isConnected in
            // Back online: swap the saved copy (or the error) for the server's.
            if isConnected, loadFailed { Task { await load() } }
        }
        .onDisappear {
            if days != nil { LastVisitedDay.record(selection, for: trip.id) }
        }
    }

    // MARK: - Header

    /// A solid chip standing in for the navigation bar: back on the left, then the trip's
    /// title and the day being viewed (left aligned, taking the free width, truncating the
    /// title first), then more on the right, which opens the trip menu (adding items too). Squared off at the bottom when the
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
                withAnimation(.snappy(duration: 0.25)) { showingTripMenu.toggle() }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 32, height: 32)
                    .background(.white.opacity(showingTripMenu ? 0.18 : 0), in: .circle)
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { headerFrame = $0 }
    }

    /// Copies the trips inbox address and shows a toast confirming it for a moment.
    private func copyTripsEmail() {
        UIPasteboard.general.string = AddLodgingPopup.tripsEmail
        showToast(TripToast(text: "Email address copied", systemImage: "checkmark.circle.fill"))
    }

    /// Sends a picked booking screenshot to be processed into itinerary items, then
    /// reloads the itinerary to pick up what the server made of it. The progress pill
    /// shows the upload, then the server's work once the image is sent, then done once
    /// the server answers (it responds only when processing has finished).
    private func importScreenshot(_ item: PhotosPickerItem) async {
        let id = UUID()
        importID = id
        withAnimation(.snappy) { importStep = .uploading }
        // Moves this import's pill on, unless it's been dismissed or replaced since.
        func show(_ step: ImportProgressPill.Step) {
            guard importID == id, importStep != nil else { return }
            importStep = step
            if step == .added || step == .failed { hideImportPill(id, after: .seconds(60)) }
        }
        do {
            let file = try await Self.uploadFile(for: item)
            let api = api
            // A request's own timeout only limits gaps between data, so cap the whole
            // call here.
            let result = try await Self.withTimeout(ReceivedImagesAPI.processTimeout) {
                try await api.send(ReceivedImagesAPI.process(file), as: ImageImportResult.self) {
                    // Only forward: on a quick response this can land after the steps below.
                    Task { @MainActor in if importStep == .uploading { show(.extracting) } }
                }
            }
            // Anything but placing the booking in a trip (not a booking, no matching
            // trip, or several) counts as a failed import.
            guard result.outcome == "placed" else {
                show(.failed)
                return
            }
            show(.added)
            await load()
        } catch {
            show(.failed)
        }
    }

    /// Hides import `id`'s pill, after `delay` if given; a newer import's pill is left
    /// alone.
    private func hideImportPill(_ id: UUID, after delay: Duration? = nil) {
        Task {
            if let delay { try? await Task.sleep(for: delay) }
            guard importID == id else { return }
            withAnimation(.snappy) { importStep = nil }
        }
    }

    /// Runs `work`, throwing `ScreenshotError.timedOut` if it takes longer than
    /// `seconds`; the work is cancelled either way once one side finishes.
    private static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval, _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw ScreenshotError.timedOut
            }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }

    /// The picked image as an upload: PNGs and JPEGs as they are, anything else (e.g.
    /// HEIC photos) re-encoded as JPEG so the server can read it.
    private static func uploadFile(for item: PhotosPickerItem) async throws -> MultipartFile {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw ScreenshotError.unreadable
        }
        if let type = item.supportedContentTypes.first,
           type.conforms(to: .png) || type.conforms(to: .jpeg),
           let mime = type.preferredMIMEType {
            let ext = type.preferredFilenameExtension ?? "jpg"
            return MultipartFile(field: "file", filename: "screenshot.\(ext)", contentType: mime, data: data)
        }
        guard let jpeg = UIImage(data: data)?.jpegData(compressionQuality: 0.9) else {
            throw ScreenshotError.unreadable
        }
        return MultipartFile(field: "file", filename: "screenshot.jpg", contentType: "image/jpeg", data: jpeg)
    }

    /// Shows a toast, hiding it after `hideAfter` (nil keeps it up until replaced).
    private func showToast(_ newToast: TripToast, hideAfter: Duration? = .seconds(1.8)) {
        toastHideTask?.cancel()
        AccessibilityNotification.Announcement(newToast.text).post()
        withAnimation(.snappy(duration: 0.25)) { toast = newToast }
        guard let hideAfter else { return }
        toastHideTask = Task {
            try? await Task.sleep(for: hideAfter)
            guard !Task.isCancelled else { return }
            withAnimation(.snappy(duration: 0.25)) { toast = nil }
        }
    }

    /// The screenshot import's progress, above the day picker. Tapping it dismisses it
    /// (the import carries on); it also goes by itself a minute after finishing.
    @ViewBuilder
    private var importProgressPill: some View {
        if let importStep {
            ImportProgressPill(step: importStep)
                .id(importID)
                // 60% of the screen's width, centered.
                .containerRelativeFrame(.horizontal) { width, _ in width * 0.6 }
                // Just above the day picker pinned to the bottom.
                .padding(.bottom, 72)
                .onTapGesture { hideImportPill(importID) }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Dismisses")
                // Drops a short way while fading out (and rises the same way in), rather
                // than sliding off the screen.
                .transition(.offset(y: 50).combined(with: .opacity))
        }
    }

    /// Places the offline pill just above the day picker, saying how old the saved
    /// copy is. Steps aside while a toast or the import pill has the spot.
    private var offlinePillAnchor: some View {
        Color.clear
            .frame(height: 72)
            .offlinePillAnchor(
                savedDate: loadFailed ? savedCopyDate : nil,
                // With a connection too, while the server can't be reached.
                showsWhenOnline: savedCopyDate != nil && loadFailed,
                isHidden: toast != nil || importStep != nil
            )
            .allowsHitTesting(false)
    }

    /// A small pill above the day picker: a spinner or icon, then the message.
    @ViewBuilder
    private var toastView: some View {
        if let toast {
            HStack(spacing: 8) {
                if let systemImage = toast.systemImage {
                    Image(systemName: systemImage)
                } else {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }
                Text(toast.text)
                    .multilineTextAlignment(.leading)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .floatingPillBackground(in: .rect(cornerRadius: 20))
            .padding(.horizontal, 24)
            // Clear of the day picker pinned to the bottom.
            .padding(.bottom, 96)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .id(toast)
        }
    }

    /// Deletes the trip from its menu, then leaves it for the presenter to close.
    private func deleteTrip(_ target: Trip) {
        Task {
            do {
                try await api.send(TripsAPI.delete(id: target.id))
                // The refund, if any, is on the balance now.
                Task { await credits.load() }
                tripDeleted(target)
            } catch {
                showToast(TripToast(text: "Couldn't delete the trip", systemImage: "exclamationmark.triangle.fill"))
            }
        }
    }

    /// After `deleted` is gone: this trip closes the screen; an extension of it just
    /// drops out of the merged itinerary.
    private func tripDeleted(_ deleted: Trip) {
        if deleted.id == trip.id {
            onDeleted()
        } else {
            Task { await load() }
        }
    }

    /// The trip the menu's trip actions apply to: the extension the viewed day is on,
    /// or this trip (also for days no trip covers).
    private var menuTrip: Trip {
        guard let tripId = selectedDay?.tripId, tripId != trip.id,
              let dayTrip = itineraryTrips.first(where: { $0.id == tripId }) else { return trip }
        return dayTrip
    }

    private func closeTripMenu() {
        withAnimation(.snappy(duration: 0.2)) { showingTripMenu = false }
    }

    /// The ends of the trip with no group trip of the user's past them yet; one segment
    /// on each side is all a user needs.
    private var openSegmentEdges: Set<HorizontalEdge> {
        var edges: Set<HorizontalEdge> = [.leading, .trailing]
        for other in groupTrips where other.id != trip.id {
            // `trip`'s dates may already span its group (as the list sends them), so a
            // trip reaching either end counts.
            if other.startDate <= trip.startDate { edges.remove(.leading) }
            if other.endDate >= trip.endDate { edges.remove(.trailing) }
        }
        return edges
    }

    /// The open trip menu, hung below the header's trailing edge; tapping anywhere else
    /// closes it.
    @ViewBuilder
    private var tripMenu: some View {
        if showingTripMenu {
            GeometryReader { proxy in
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .contentShape(.rect)
                        .onTapGesture { closeTripMenu() }
                        .accessibilityHidden(true)
                    TripMenu(
                        trip: menuTrip,
                        onAddItem: { kind in
                            closeTripMenu()
                            addItemRequest = AddItemRequest(date: selectedDay?.calendarDate, kind: kind)
                        },
                        onImportScreenshot: {
                            closeTripMenu()
                            showingBookingImagePicker = true
                        },
                        onCopyTripsEmail: {
                            closeTripMenu()
                            copyTripsEmail()
                        },
                        onEditTrip: {
                            closeTripMenu()
                            tripToEdit = menuTrip
                        },
                        // Not built yet.
                        onShare: { closeTripMenu() },
                        onDeleteTrip: menuTrip.ownerId == auth.currentUser?.id ? {
                            closeTripMenu()
                            withAnimation(.snappy(duration: 0.2)) { tripToDelete = menuTrip }
                        } : nil
                    )
                    .padding(.top, headerFrame.maxY + 6)
                    .padding(.trailing, max(proxy.size.width - headerFrame.maxX, 0))
                    .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
                }
            }
            .ignoresSafeArea()
        }
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
        // Gap days between the user's trips show only in the day picker.
        DayPager(days: days.filter { !$0.isGap }, selection: $selection, dragProgress: $pageDragProgress, onSettled: collapseOpenCard) { day, scrollLocked in
            dayPage(day, scrollLocked: scrollLocked)
        }
    }

    /// Once a day change has landed, folds away any open card's details, without
    /// animating: the day it was on is off screen by then, and comes back as it
    /// first appears, at the top with every card shut. Left alone until then so the
    /// page doesn't change as it slides away.
    private func collapseOpenCard() {
        guard expandedEntryID != nil || measuringEntryID != nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            expandedEntryID = nil
            measuringEntryID = nil
        }
    }

    private func dayPage(_ day: ItineraryDay, scrollLocked: Bool) -> some View {
        let zoneChanges = ItineraryZoneChanges.changes(in: days ?? [])
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if day.entries.isEmpty && day.lodging.isEmpty {
                    Text("Nothing planned")
                        .font(.subheadline.italic())
                        .foregroundStyle(Color.appForeground.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 100)
                        .revealIn(hasRevealed, delay: Self.cardRevealDelay(0))
                } else {
                    ForEach(Array(day.entries.enumerated()), id: \.element.id) { index, entry in
                        if let zone = zoneChanges[entry.id] {
                            zoneChangeDivider(zone, at: entry.displayInstant)
                                .revealIn(hasRevealed, delay: Self.cardRevealDelay(index))
                        }
                        itemRow(entry, on: day, topFade: topFadeProgress[day.dayNumber] ?? 0)
                            .revealIn(hasRevealed, delay: Self.cardRevealDelay(index), slide: 16)
                    }
                }

                // Centered between faint rules that run out to the content's edges.
                HStack(spacing: 12) {
                    addActivityRule
                    // One plus for both: "+ ACTIVITY | TRANSIT", each word its own button.
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .accessibilityHidden(true)
                        addItemButton("Activity", kind: .activity, on: day.calendarDate)
                        Rectangle()
                            .fill(Color.appForeground.opacity(0.3))
                            .frame(width: 1, height: 10)
                            .accessibilityHidden(true)
                        addItemButton("Transit", kind: .transit, on: day.calendarDate)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                    // Keep the label on one line; the rules take whatever width is left.
                    .fixedSize()
                    addActivityRule
                }
                // Less the buttons' own 6pt above and below.
                .padding(.top, 8)
                .padding(.bottom, 4)
                .revealIn(hasRevealed, delay: Self.cardRevealDelay(day.entries.count) + 0.05)

                // Clear the bottom day-picker bar and the offline pill just above it,
                // whether or not the pill is showing, so the end of the day never shifts.
                Color.clear.frame(height: 168 + (scrollRunway[day.dayNumber] ?? 0))
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition(scrollPositionBinding(for: day.dayNumber))
        .scrollDisabled(scrollLocked)
        // Untouchable while an opened card scrolls into place, so a finger can't fight
        // it. (Not `scrollDisabled`, which would stop the programmatic scroll too.)
        .allowsHitTesting(!isAutoScrolling)
        // Let cards keep drawing as they scroll up past the top, under the pinned block.
        .scrollClipDisabled()
        // Clamped, so it stops updating once scrolled past the reach.
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            min(max((geometry.contentOffset.y + geometry.contentInsets.top) / Self.topFadeReach, 0), 1)
        } action: { _, progress in
            topFadeProgress[day.dayNumber] = progress
        }
        // One scroll view per day. The pager's three slots are reused as days slide
        // through them, and without this a slot's scroll view would carry the last
        // day's offset over to the next one for a frame before snapping to the top.
        .id(day.dayNumber)
        .onScrollGeometryChange(for: PageScroll.self) { PageScroll($0) } action: { _, scroll in
            pageScroll[day.dayNumber] = scroll
        }
    }

    /// A day page's scroll position, kept per day so an opened card can scroll its
    /// own page.
    private func scrollPositionBinding(for dayNumber: Int) -> Binding<ScrollPosition> {
        Binding {
            scrollPositions[dayNumber] ?? ScrollPosition()
        } set: {
            // Only an opened card's scroll is kept; the page's own scrolling isn't
            // saved, or a day paged back to would jump to where it was left.
            guard isAutoScrolling else { return }
            scrollPositions[dayNumber] = $0
        }
    }

    /// When the card at `index` starts its entrance: just after the pinned header and
    /// day picker, then each card a beat after the one before. Capped so a long day
    /// doesn't keep the cards further down waiting.
    private static func cardRevealDelay(_ index: Int) -> Double {
        0.12 + Double(min(index, 6)) * 0.07
    }

    /// What `finishOpening` needs of a day page's scroll view: how far it's
    /// scrolled (from the top of the content, below the pinned block's inset, as
    /// `ScrollPosition` counts it), how tall its content is, and how tall the scroll
    /// view itself is.
    private struct PageScroll: Equatable {
        var y: CGFloat
        var contentHeight: CGFloat
        var containerHeight: CGFloat

        init(_ geometry: ScrollGeometry) {
            y = geometry.contentOffset.y + geometry.contentInsets.top
            contentHeight = geometry.contentSize.height
            containerHeight = geometry.containerSize.height
        }

        /// The furthest it can scroll once its content is `contentHeight` tall: the
        /// content's end level with the scroll view's bottom edge.
        func maxY(contentHeight: CGFloat) -> CGFloat {
            max(contentHeight - containerHeight, 0)
        }
    }

    // MARK: - Rows

    /// Opens an item's edit form directly, with a haptic tap to confirm the long press.
    private func editItem(_ item: TripItem) {
        editHaptic += 1
        editingItem = places.resolving(item)
    }

    /// Where an opened card's row should sit, measured down from the top of the page's
    /// visible area (just under the pinned block's bottom padding): the card and its
    /// details centered between the pinned block and the day picker, or, when they're
    /// too tall for that, `expandedHeaderGap` below the pinned block.
    ///
    /// The row carries the card's 6pt padding above and below, which doesn't count
    /// toward what's seen.
    private func expandedRowTop(rowHeight: CGFloat) -> CGFloat {
        let rowPadding: CGFloat = 6
        let bandTop = -Self.pinnedBlockBottomPadding
        let band = dayPickerTop - bandTop
        let visibleHeight = rowHeight - rowPadding * 2
        let gap = max((band - visibleHeight) / 2, Self.expandedHeaderGap)
        return bandTop + gap - rowPadding
    }

    /// Starts opening a card: makes room to scroll into, holds off touches, and lays
    /// its details out unseen to measure them (see `finishOpening`).
    private func beginOpening(_ entry: ItineraryEntry, on day: ItineraryDay) {
        let id = UUID()
        autoScrollID = id
        scrollRunway[day.dayNumber] = Self.scrollRunwayHeight
        isAutoScrolling = true
        measuredRowFrame = nil
        measuredPanelHeight = nil
        measuringEntryID = entry.id
        // Should the measuring never finish, don't leave the page stuck.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard autoScrollID == id, measuringEntryID == entry.id else { return }
            measuringEntryID = nil
            withAnimation(.snappy(duration: Self.expandDuration)) {
                expandedEntryID = entry.id
            }
            endAutoScroll(id, on: day.dayNumber)
        }
    }

    /// Once the tapped card's details are measured: works out where its row will
    /// sit once open (allowing for any other open card on the page closing), then
    /// opens it, closes the other and scrolls the page there in a single animation.
    private func finishOpening(_ entry: ItineraryEntry, on day: ItineraryDay, anchor: CGFloat) {
        guard measuringEntryID == entry.id,
              let rowFrame = measuredRowFrame,
              let panelHeight = measuredPanelHeight else { return }
        measuringEntryID = nil
        let id = autoScrollID
        let dayNumber = day.dayNumber

        // The card open now on this page (if any) closes as this one opens, taking its
        // extra height with it; if it's above, this row moves up by that much.
        let entryIDs = day.entries.map(\.id)
        let closingIndex = expandedEntryID.flatMap { entryIDs.firstIndex(of: $0) }
        let closingExtra = closingIndex == nil ? 0 : openRowExtra
        let closingAbove = closingIndex.map { $0 < (entryIDs.firstIndex(of: entry.id) ?? 0) } ?? false

        // The row's added height: its details, less where they tuck under the card.
        let addedHeight = panelHeight - (6 + anchor)
        let finalTop = rowFrame.minY - (closingAbove ? closingExtra : 0)
        let finalHeight = rowFrame.height + addedHeight

        var y: CGFloat?
        if let scroll = pageScroll[dayNumber] {
            // Kept within how far the page can scroll once settled (without the
            // runway), so a card near the end of a short day stops short of centered
            // rather than overshooting and snapping back when the runway goes.
            let finalContentHeight = scroll.contentHeight - (scrollRunway[dayNumber] ?? 0) - closingExtra + addedHeight
            y = min(max(scroll.y + finalTop - expandedRowTop(rowHeight: finalHeight), 0), scroll.maxY(contentHeight: finalContentHeight))
        }

        withAnimation(.snappy(duration: Self.expandDuration)) {
            expandedEntryID = entry.id
            if let y {
                scrollPositions[dayNumber, default: ScrollPosition()].scrollTo(y: y)
            }
        }
        // On a timer, not the animation's completion: that fires as soon as SwiftUI's
        // own animations are done, which doesn't wait for the scroll.
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.expandDuration + 0.15) {
            endAutoScroll(id, on: dayNumber)
        }
    }

    /// Takes the runway away and lets touches back in, unless a newer open has
    /// started since.
    private func endAutoScroll(_ id: UUID, on dayNumber: Int) {
        guard autoScrollID == id else { return }
        scrollRunway[dayNumber] = nil
        isAutoScrolling = false
        // Done with it: the pager's pages are reused across days, and a target left
        // here would send whichever page shows this day back to it.
        scrollPositions[dayNumber] = nil
    }

    private func itemRow(_ entry: ItineraryEntry, on day: ItineraryDay, topFade: CGFloat) -> some View {
        let itemMembers = memberSelection(onTripOf: entry.item.tripId)
        let going = itemMembers.initialSelection(for: entry.item)
        // Open items others are doing shrink to a one-line card.
        let isCondensed = entry.item.visibility == .open && itemMembers.includesCurrentUser(entry.item) == false
        let isExpanded = expandedEntryID == entry.id
        // The condensed card is see-through, so the panel can't sit up behind it.
        let panelAnchor = isCondensed ? 0 : TripItemDetailPanel.anchor
        // Pulls the panel's top up over the card's own 6pt bottom padding, then
        // `panelAnchor` further, behind the card's bottom edge.
        return VStack(spacing: -(6 + panelAnchor)) {
            ItineraryEntryCard(
                entry: entry,
                places: places,
                placeDetails: placeDetails,
                // A redacted item's participants are blanked, so there's no one to count.
                membersSummary: entry.item.redacted ? nil : itemMembers.summary(of: going),
                membersCount: going.count,
                isCondensed: isCondensed,
                isExpanded: isExpanded
            )
            .contentShape(.rect)
            // Tapping folds the item's details open beneath the card, or shut again; a
            // long press skips them and goes straight to editing the item.
            .onTapGesture {
                if isExpanded {
                    withAnimation(.snappy(duration: Self.expandDuration)) {
                        expandedEntryID = nil
                    }
                } else {
                    beginOpening(entry, on: day)
                }
            }
            .onLongPressGesture { editItem(entry.item) }
            .accessibilityAction(named: "Edit") { editItem(entry.item) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(isExpanded ? "Hides details" : "Shows details")
            // Over the panel, whose top sits behind the card's bottom edge.
            .zIndex(1)

            if isExpanded {
                TripItemDetailPanel(item: places.resolving(entry.item), anchor: panelAnchor) {
                    editItem(entry.item)
                }
                // In place of the card's bottom padding, which the panel covers.
                .padding(.bottom, 6)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    openRowExtra = height - (6 + panelAnchor)
                }
                .transition(UnfoldTransition())
            }
        }
        // Just tapped: where the row sits now, and its details laid out unseen at
        // their natural height, for `finishOpening` to work out the scroll from.
        .background(alignment: .top) {
            if measuringEntryID == entry.id {
                Color.clear
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.detailSpace)) } action: { frame in
                        measuredRowFrame = frame
                        finishOpening(entry, on: day, anchor: panelAnchor)
                    }
                    .overlay(alignment: .top) {
                        TripItemDetailPanel(item: places.resolving(entry.item), anchor: panelAnchor) {}
                            .padding(.bottom, 6)
                            .fixedSize(horizontal: false, vertical: true)
                            .hidden()
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                                measuredPanelHeight = height
                                finishOpening(entry, on: day, anchor: panelAnchor)
                            }
                    }
            }
        }
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
    /// the add-lodging popup for that day.
    private func addLodgingStrip(for day: ItineraryDay) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { addLodgingDay = day }
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
        return place?.googlePlaceId.flatMap { placeDetails[$0] }?.name ?? place?.name ?? item.displayTitle
    }

    private func showLodgingPopup(_ item: TripItem) {
        withAnimation(.snappy(duration: 0.25)) { popupLodging = item }
    }

    private func closeDeleteTrip() {
        withAnimation(.snappy(duration: 0.2)) { tripToDelete = nil }
    }

    /// Asks before deleting a trip from its menu, with the credits it refunds.
    @ViewBuilder
    private var deleteTripPopup: some View {
        if let target = tripToDelete {
            DimmedPopup(onClose: closeDeleteTrip) {
                DeleteTripPopup(tripId: target.id, onDelete: {
                    closeDeleteTrip()
                    deleteTrip(target)
                }, onClose: closeDeleteTrip)
            }
        }
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
            DimmedPopup(onClose: closeLodgingPopup) {
                LodgingPopup(
                    name: name,
                    propertyType: item.lodging?.propertyType,
                    address: address,
                    googlePlaceId: place?.googlePlaceId,
                    onEdit: {
                        closeLodgingPopup()
                        editingItem = places.resolving(item)
                    },
                    onClose: closeLodgingPopup
                )
            }
        }
    }

    private func memberSelection(onTripOf tripId: String?) -> ItemMemberSelection {
        ItemMemberSelection(members: members(onTripOf: tripId), currentUserId: auth.currentUser?.id)
    }

    /// The trip owning each itinerary day, by date, for a new item to save to the trip
    /// its date falls in. Days no trip covers are left out.
    private var tripsByDate: [String: Trip] {
        let trips = Dictionary(itineraryTrips.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Dictionary((days ?? []).compactMap { day in
            day.tripId.flatMap { trips[$0] }.map { (day.date, $0) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// The members of one of the itinerary's trips: an item's participants are member
    /// rows on its own trip. Falls back to this trip's.
    private func members(onTripOf tripId: String?) -> [TripMember] {
        itineraryTrips.first { $0.id == tripId }?.members ?? trip.members ?? []
    }

    private func closeAddLodgingPopup() {
        withAnimation(.snappy(duration: 0.2)) { addLodgingDay = nil }
    }

    /// The open add-lodging popup over a dimmed screen; tapping outside closes it.
    @ViewBuilder
    private var addLodgingPopup: some View {
        if let day = addLodgingDay {
            DimmedPopup(onClose: closeAddLodgingPopup) {
                AddLodgingPopup(
                    onUploadImage: {
                        closeAddLodgingPopup()
                        showingBookingImagePicker = true
                    },
                    onAddManually: {
                        closeAddLodgingPopup()
                        addItemRequest = AddItemRequest(date: day.calendarDate, kind: .lodging)
                    },
                    onClose: closeAddLodgingPopup
                )
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
            Image(systemName: stay.item.lodging?.propertyType?.systemImage ?? "bed.double.fill")
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
        .onLongPressGesture { editItem(stay.item) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(lodgingName(stay)), \(stay.phase.label)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showLodgingPopup(stay.item) }
        .accessibilityAction(named: "Edit") { editItem(stay.item) }
    }

    private var lodgingArrow: some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(Color(white: 0.15))
            .frame(width: 16, height: 16)
            .background(Color.appForeground, in: .circle)
    }

    /// One word of the add line under a day's items, adding that kind on the day.
    private func addItemButton(_ label: String, kind: TripItemKind, on date: Date?) -> some View {
        Button {
            addItemRequest = AddItemRequest(date: date, kind: kind)
        } label: {
            Text(label.uppercased())
                .tracking(1.5)
                // A taller target than the caption's own line.
                .padding(.vertical, 6)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Add \(label)")
    }

    /// A faint hairline flanking the Add Activity button.
    /// Where the clock changes, e.g. after landing in a new zone: the new zone between
    /// dotted rules, over the first card in it. Times from here on are that zone's wall
    /// clock, until the next divider.
    private func zoneChangeDivider(_ zone: TimeZone, at instant: Date) -> some View {
        HStack(spacing: 10) {
            zoneChangeRule
            Label(ItineraryZoneChanges.label(for: zone, at: instant), systemImage: "clock")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(Color.appForeground.opacity(0.6))
                .fixedSize()
            zoneChangeRule
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Times below are in \(ItineraryZoneChanges.label(for: zone, at: instant).replacingOccurrences(of: " · ", with: ", "))")
    }

    private var zoneChangeRule: some View {
        DashedLine()
            .stroke(Color.appForeground.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [2, 4]))
            .frame(height: 1)
            .frame(maxWidth: .infinity)
    }

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

    /// The day to show after a reload: the day holding the just-saved item when given,
    /// otherwise the current day if it still exists, falling back to the first day. Never
    /// a gap day, which has no page (e.g. once the last item on a day outside the trips
    /// is deleted).
    private func resolveSelection(in days: [ItineraryDay], focusItemId: String?) -> Int {
        if let focusItemId,
           let day = days.first(where: { day in
               day.uniqueItems.contains { $0.id == focusItemId }
           }) {
            return day.dayNumber
        }
        if days.contains(where: { $0.dayNumber == selection && !$0.isGap }) {
            return selection
        }
        return days.first?.dayNumber ?? 1
    }

    /// Drops a deleted item from the itinerary straight away, then reloads to pick up
    /// anything the server derived from it.
    private func removeItem(_ id: String) {
        withAnimation(.snappy) {
            days = days?.map { $0.removing(itemId: id) }
        }
        Task { await load() }
    }

    /// Reloads the itinerary. Pass `focusItemId` after a save to land on the day that
    /// item sits on; otherwise the current day is kept (falling back to the first).
    private func load(focusItemId: String? = nil) async {
        do {
            let itinerary = try await api.send(TripsAPI.itinerary(tripId: trip.id), as: Itinerary.self)
            days = itinerary.days
            itineraryTrips = itinerary.trips
            places = ItineraryPlaces(days: itinerary.days)
            selection = resolveSelection(in: itinerary.days, focusItemId: focusItemId)
            errorMessage = nil
            savedCopyDate = nil
            loadFailed = false
            // The itinerary is already on screen; stale places refresh alongside the
            // Google details and patch their cards when they land.
            async let refresh: Void = refreshStalePlaces(itinerary.stalePlaceIds)
            await loadPlaceDetails(for: itinerary.days)
            await refresh
        } catch {
            // With a saved copy showing, this just marks it as possibly out of date.
            errorMessage = error.localizedDescription
            loadFailed = true
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

/// A request to present the add-segment form, for days on `edge`'s side of the trip.
private struct SegmentRequest: Identifiable {
    let id = UUID()
    let edge: HorizontalEdge
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
    /// Called once a slide to another day has landed and the day left behind is off
    /// screen.
    var onSettled: () -> Void = {}
    @ViewBuilder let content: (ItineraryDay, Bool) -> Content

    /// Starts on the selected day rather than the first, so the pager never swaps
    /// pages right after it appears (which would show through the entrance animation).
    @State private var index: Int

    init(
        days: [ItineraryDay],
        selection: Binding<Int>,
        dragProgress: Binding<CGFloat>,
        onSettled: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (ItineraryDay, Bool) -> Content
    ) {
        self.onSettled = onSettled
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
                // Each page flattened into one layer before it fades, so it fades as a
                // whole. Otherwise every view in it fades on its own, and wherever two
                // overlap (an open card over the top of its details) the two half-faded
                // layers stack into a darker band.
                slot(for: -1, width: w, scrollLocked: scrollLocked)
                    .compositingGroup()
                    .opacity(slotOpacity(for: -1, width: w))
                slot(for: 0, width: w, scrollLocked: scrollLocked)
                    .compositingGroup()
                    .opacity(slotOpacity(for: 0, width: w))
                slot(for: 1, width: w, scrollLocked: scrollLocked)
                    .compositingGroup()
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
            onSettled()
        }
    }
}

#Preview {
    NavigationStack {
        TripDetailView(trip: .sample, days: ItineraryDay.sampleDays)
    }
    .appTheme()
    .environment(AuthStore())
    .environment(CreditStore())
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

/// A short status message for the itinerary's toast. A nil `systemImage` shows a
/// spinner, for work still in progress.
private struct TripToast: Hashable {
    var text: String
    var systemImage: String?
}

private enum ScreenshotError: LocalizedError {
    case unreadable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unreadable: "Couldn't read that image. Please try another."
        case .timedOut: "The server took too long to respond. Please try again."
        }
    }
}
