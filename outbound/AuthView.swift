//
//  AuthView.swift
//  outbound
//
//  Created by Sun Chen on 10/9/26.
//

import SwiftUI

/// Root of the app: shows the main screen when signed in, otherwise sign in / sign up.
struct AuthView: View {
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
            if auth.isSignedIn {
                HomeView()
            } else {
                SignInView()
            }
        }
        .animation(.default, value: auth.isSignedIn)
        .task {
            await auth.refreshUser()
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthStore())
}
