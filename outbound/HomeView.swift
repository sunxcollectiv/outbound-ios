//
//  HomeView.swift
//  outbound
//

import SwiftUI

/// The main app screen, shown once the user is signed in: a list of the user's trips.
/// Tapping a trip opens its itinerary.
struct HomeView: View {
    @Environment(AuthStore.self) private var auth

    @State private var store = TripStore()
    @State private var showingAddTrip = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                content
            }
            .foregroundStyle(Color.appForeground)
            .navigationTitle("Trips")
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        auth.signOut()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddTrip = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Trip")
                }
            }
            .sheet(isPresented: $showingAddTrip) {
                AddTripView(onCreated: { store.add($0) })
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
                VStack(spacing: 16) {
                    ForEach(store.trips) { trip in
                        NavigationLink {
                            TripDetailView(trip: trip)
                        } label: {
                            TripCard(trip: trip)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .refreshable { await store.load() }
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
