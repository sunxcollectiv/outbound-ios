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
            ZStack {
                Color.appBackground.ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 48))
                    Text("Hello, \(auth.currentUser?.displayName ?? "there")!")
                        .font(.largeTitle)
                        .bold()
                }
                .padding()
            }
            .foregroundStyle(Color.appForeground)
            .navigationTitle("Outbound")
            .toolbarBackground(Color.appBackground, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
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
        .appTheme()
        .environment(AuthStore())
}
