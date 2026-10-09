//
//  HomeView.swift
//  outbound
//

import SwiftUI

/// The main app screen, shown once the user is signed in.
struct HomeView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Hello, \(auth.currentUser?.name ?? "there")!")
                    .font(.largeTitle)
                    .bold()
            }
            .padding()
            .navigationTitle("Outbound")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign Out") {
                        auth.signOut()
                    }
                }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(AuthStore())
}
