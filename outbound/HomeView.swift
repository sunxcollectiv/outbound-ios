//
//  HomeView.swift
//  outbound
//

import SwiftUI
import UserNotifications

/// The main app screen, shown once the user is signed in: a list of the user's trips.
/// Tapping a trip opens its itinerary; long-pressing one opens the edit form.
struct HomeView: View {
    @Environment(AuthStore.self) private var auth

    @State private var store = TripStore()
    @State private var notifications = NotificationStore()
    @State private var showingNotifications = false
    @State private var showingAddTrip = false
    /// The trip whose itinerary is pushed, by id so the screen reads the latest copy.
    @State private var openedTripId: String?
    /// The trip being edited from a long press.
    @State private var editingTrip: Trip?
    @State private var isDrawerOpen = false
    @Environment(\.scenePhase) private var scenePhase
    private var push = PushNotifications.shared
    /// Pairs each trip's tile with its itinerary for the zoom transition.
    @Namespace private var tripZoom

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        LeadingDrawer(isOpen: $isDrawerOpen, edgeSwipeEnabled: openedTripId == nil && !showingNotifications) {
            tripsStack
        } drawer: {
            ProfileDrawer(onSignOut: { isDrawerOpen = false })
        }
        // Behind the whole stack, over the app's terracotta, so a trip zooming in or out
        // shows this at its rounded corners.
        .background(LinearGradient.tripsBackground.ignoresSafeArea())
    }

    private var tripsStack: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // As the navigation container's backdrop rather than a view behind the
                // grid, so the zoom transition to a trip never shows the system's white.
                .containerBackground(LinearGradient.tripsBackground, for: .navigation)
                .foregroundStyle(Color.appForeground)
                .navigationTitle("Trips")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbar {
                    // A step larger than the system's inline title.
                    ToolbarItem(placement: .principal) {
                        Text("Trips")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .accessibilityAddTraits(.isHeader)
                    }
                    if let user = auth.currentUser {
                        AppToolbarButton(placement: .topBarLeading) {
                            withAnimation(.snappy(duration: 0.3)) { isDrawerOpen = true }
                        } label: {
                            AvatarView(user: user, size: 32)
                                // The bar insets its items past the screen's 16pt margin;
                                // pull the avatar back so it lines up with the title and grid.
                                .offset(x: -18)
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                                .accessibilityLabel("Profile")
                        }
                    }
                    AppToolbarButton(placement: .topBarTrailing) {
                        showingNotifications = true
                    } label: {
                        NotificationBell(unreadCount: notifications.unreadCount)
                    }
                    AppToolbarButton(placement: .topBarTrailing) {
                        showingAddTrip = true
                    } label: {
                        Image(systemName: "plus")
                            .accessibilityLabel("Add Trip")
                    }
                }
                .sheet(isPresented: $showingAddTrip) {
                    TripFormView(onSaved: { store.add($0) })
                }
                .sheet(item: $editingTrip) { trip in
                    TripFormView(trip: trip, onSaved: { store.update($0) })
                }
                .navigationDestination(item: $openedTripId) { id in
                    if let trip = store.trips.first(where: { $0.id == id }) {
                        TripDetailView(trip: trip)
                            .navigationTransition(.zoom(sourceID: id, in: tripZoom))
                    }
                }
                .navigationDestination(isPresented: $showingNotifications) {
                    NotificationsView(store: notifications, trip: trip(id:))
                }
                .task { await store.load() }
                .task(id: scenePhase) {
                    if scenePhase == .active { await notifications.refreshUnreadCount() }
                }
                .task { await push.registerIfAllowed() }
                .task(id: push.receivedCount) {
                    // A push arrived or was tapped: the inbox has something new.
                    guard push.receivedCount > 0 else { return }
                    if showingNotifications {
                        await notifications.load()
                    } else {
                        await notifications.refreshUnreadCount()
                    }
                }
                .task(id: push.pendingTripId) { await openPendingTrip() }
                .onChange(of: notifications.unreadCount) { _, count in
                    Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
                }
        }
    }

    /// A trip from the list for a notification to open, reloading the list first if
    /// it isn't there (e.g. someone just added this user to it).
    private func trip(id: String) async -> Trip? {
        if let trip = store.trips.first(where: { $0.id == id }) { return trip }
        await store.load()
        return store.trips.first(where: { $0.id == id })
    }

    /// Opens the trip a tapped push is about, over whatever the trips screen shows.
    private func openPendingTrip() async {
        guard let id = push.pendingTripId else { return }
        // Cleared only once the lookup is done: clearing restarts this task, which
        // would cancel a trips load still in flight on a cold launch.
        let found = await trip(id: id)
        guard !Task.isCancelled else { return }
        push.pendingTripId = nil
        guard let trip = found else { return }
        isDrawerOpen = false
        showingNotifications = false
        openedTripId = trip.id
    }

    @ViewBuilder
    private var content: some View {
        if store.isLoading && store.trips.isEmpty {
            ProgressView()
                .controlSize(.large)
                .tint(Color.appForeground)
        } else if store.trips.isEmpty {
            emptyState
        } else {
            let (upcoming, past) = Trip.upcomingAndPast(store.trips)
            ScrollView {
                VStack(spacing: 0) {
                    // Upcoming and current trips lead the screen unlabeled.
                    tripSection(nil, trips: upcoming, emptyText: "No upcoming trips", featuresFirst: true)
                        .padding()
                        .padding(.bottom, 8)
                    tripSection("Past", trips: past, emptyText: "No past trips")
                        .padding()
                        .padding(.top, 4)
                        .background(alignment: .top) { pastBackground }
                }
            }
            .refreshable { await store.load() }
            .sensoryFeedback(.impact, trigger: editingTrip?.id) { _, new in new != nil }
        }
    }

    /// A grid of trips under an optional title, or a placeholder line when there are none,
    /// so the section keeps its place on the screen. With `featuresFirst`, the first trip spans the grid
    /// as a large square above the rest.
    private func tripSection(_ title: String?, trips: [Trip], emptyText: String, featuresFirst: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                    .accessibilityAddTraits(.isHeader)
            }
            if trips.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground.opacity(0.5))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .overlay {
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                            .foregroundStyle(Color.appForeground.opacity(0.3))
                    }
            } else {
                let featured = featuresFirst ? trips.first : nil
                if let featured {
                    tripTile(featured, isFeatured: true)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(featured == nil ? trips : Array(trips.dropFirst())) { trip in
                        tripTile(trip)
                    }
                }
                .padding(.top, featured == nil ? 0 : 4)
            }
        }
    }

    /// A lighter panel behind the past trips, rounded on top and running far past their
    /// bottom so it fills the rest of the screen however few there are, and stays put
    /// when the list bounces.
    private var pastBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
            .fill(Color.white.opacity(0.06))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
                    .strokeBorder(.white.opacity(0.08))
                    .frame(height: 48)
                    .mask(LinearGradient(colors: [.white, .clear], startPoint: .top, endPoint: .bottom))
            }
            .padding(.bottom, -2000)
    }

    private func tripTile(_ trip: Trip, isFeatured: Bool = false) -> some View {
        // Gestures rather than a NavigationLink: a link fires on release
        // even after a long hold, so the long press would also navigate.
        TripCard(trip: trip, isFeatured: isFeatured)
            .matchedTransitionSource(id: trip.id, in: tripZoom) { source in
                source.clipShape(.rect(cornerRadius: 16))
            }
            .contentShape(.rect(cornerRadius: 16))
            .onTapGesture { openedTripId = trip.id }
            .onLongPressGesture { editingTrip = trip }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { openedTripId = trip.id }
            .accessibilityAction(named: "Edit Trip") { editingTrip = trip }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No trips yet")
                .font(.title3.bold())
            Text(store.errorMessage ?? "Tap + to plan your first trip.")
                .font(.subheadline)
                .foregroundStyle(Color.appForeground.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}

#Preview {
    HomeView()
        .appTheme()
        .environment(AuthStore())
}
