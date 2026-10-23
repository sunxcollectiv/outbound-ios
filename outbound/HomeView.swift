//
//  HomeView.swift
//  outbound
//

import SwiftUI

/// The main app screen, shown once the user is signed in: a list of the user's trips.
/// Tapping a trip opens its itinerary; long-pressing one opens the edit form.
struct HomeView: View {
    @Environment(AuthStore.self) private var auth

    @State private var store = TripStore()
    @State private var showingAddTrip = false
    /// The trip whose itinerary is pushed, by id so the screen reads the latest copy.
    @State private var openedTripId: String?
    /// The trip being edited from a long press.
    @State private var editingTrip: Trip?
    @State private var isDrawerOpen = false
    /// Pairs each trip's tile with its itinerary for the zoom transition.
    @Namespace private var tripZoom

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        LeadingDrawer(isOpen: $isDrawerOpen, edgeSwipeEnabled: openedTripId == nil) {
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
                .task { await store.load() }
        }
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
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(store.trips) { trip in
                        // Gestures rather than a NavigationLink: a link fires on release
                        // even after a long hold, so the long press would also navigate.
                        TripCard(trip: trip)
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
                }
                .padding()
            }
            .refreshable { await store.load() }
            .sensoryFeedback(.impact, trigger: editingTrip?.id) { _, new in new != nil }
        }
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
