//
//  ProfileDrawer.swift
//  outbound
//

import SwiftUI

/// The account drawer on the trips screen: who's signed in, and signing out.
struct ProfileDrawer: View {
    @Environment(AuthStore.self) private var auth

    /// Called before signing out, so the drawer can close first.
    var onSignOut: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let user = auth.currentUser {
                AvatarView(user: user, size: 64)
                    .padding(.bottom, 16)
                Text(user.displayName)
                    .font(.title3.bold())
                Text(user.email)
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
            }

            Spacer()

            Button {
                onSignOut()
                auth.signOut()
            } label: {
                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.body.weight(.semibold))
            }
            .foregroundStyle(Color.appForeground)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(Color.appForeground)
        .background(Color.drawerBackground.ignoresSafeArea())
    }
}

/// A circular profile picture: the user's avatar image, or their initials when
/// there's no image (or while it loads).
struct AvatarView: View {
    let user: User
    var size: CGFloat = 32

    var body: some View {
        Group {
            if let urlString = user.avatarUrl, let url = URL(string: urlString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    initials
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay(Circle().strokeBorder(Color.appForeground.opacity(0.25), lineWidth: 1))
    }

    private var initials: some View {
        Text(Self.initials(from: user.displayName))
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(Color.appForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.appBackground)
    }

    /// The first letters of the first and last words of a name, e.g. "Sun Chen" → "SC".
    static func initials(from name: String) -> String {
        let words = name.split(separator: " ")
        let letters = [words.first, words.count > 1 ? words.last : nil].compactMap { $0?.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

#Preview {
    ProfileDrawer()
        .environment(AuthStore())
}
