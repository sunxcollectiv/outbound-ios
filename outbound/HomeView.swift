//
//  HomeView.swift
//  outbound
//

import SwiftUI

/// The main app screen, shown once the user is signed in: a list of the user's trips.
/// Tapping a trip opens its itinerary. Content is placeholder until `GET /trips` is wired up.
struct HomeView: View {
    @Environment(AuthStore.self) private var auth

    @State private var showingAddTrip = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(0..<4, id: \.self) { _ in
                            NavigationLink {
                                TripDetailView()
                            } label: {
                                DashedPlaceholder("Trip", height: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
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
                AddTripView()
            }
        }
    }
}

#Preview {
    HomeView()
        .appTheme()
        .environment(AuthStore())
}
