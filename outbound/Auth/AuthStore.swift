//
//  AuthStore.swift
//  outbound
//

import Foundation
import Observation

struct User: Codable, Equatable {
    let id: String
    var name: String
    var email: String
}

enum AuthError: LocalizedError {
    case missingFields
    case invalidEmail
    case passwordTooShort

    var errorDescription: String? {
        switch self {
        case .missingFields: "Please fill in all fields."
        case .invalidEmail: "Please enter a valid email address."
        case .passwordTooShort: "Password must be at least 8 characters."
        }
    }
}

/// Holds the signed-in user and decides which screen the app shows.
///
/// The auth token lives in the Keychain; the user profile is cached in
/// UserDefaults so the app can show the main screen immediately on launch,
/// then refreshes it from `/me` in the background.
@Observable
final class AuthStore {
    private(set) var currentUser: User?

    var isSignedIn: Bool { currentUser != nil }

    private let api: APIClient
    private let tokenKey = "auth.token"
    private let userKey = "auth.currentUser"

    init(api: APIClient = .shared) {
        self.api = api
        if let token = Keychain.string(for: tokenKey),
           let data = UserDefaults.standard.data(forKey: userKey),
           let user = try? JSONDecoder().decode(User.self, from: data) {
            api.token = token
            currentUser = user
        }
    }

    func signIn(email: String, password: String) async throws {
        let email = try validate(email: email, password: password)
        let session = try await api.send(AuthAPI.signIn(email: email, password: password), as: AuthAPI.Session.self)
        save(session)
    }

    func signUp(name: String, email: String, password: String) async throws {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw AuthError.missingFields }
        let email = try validate(email: email, password: password)
        let session = try await api.send(AuthAPI.signUp(name: name, email: email, password: password), as: AuthAPI.Session.self)
        save(session)
    }

    func signOut() {
        // Tell the server to end the session, but sign out locally regardless of the result.
        if api.token != nil {
            let api = api
            Task { try? await api.send(AuthAPI.signOut) }
        }
        clear()
    }

    /// Re-fetches the user so profile changes show up, and signs out if the token is no longer valid.
    func refreshUser() async {
        guard isSignedIn else { return }
        do {
            setUser(try await api.send(AuthAPI.me, as: User.self))
        } catch APIError.unauthorized {
            clear()
        } catch {
            // Offline or server hiccup: keep the cached user.
        }
    }

    private func validate(email: String, password: String) throws -> String {
        let email = email.trimmingCharacters(in: .whitespaces).lowercased()
        guard !email.isEmpty, !password.isEmpty else { throw AuthError.missingFields }
        guard email.contains("@"), email.contains(".") else { throw AuthError.invalidEmail }
        guard password.count >= 8 else { throw AuthError.passwordTooShort }
        return email
    }

    private func save(_ session: AuthAPI.Session) {
        api.token = session.token
        Keychain.set(session.token, for: tokenKey)
        setUser(session.user)
    }

    private func clear() {
        api.token = nil
        Keychain.set(nil, for: tokenKey)
        setUser(nil)
    }

    private func setUser(_ user: User?) {
        currentUser = user
        if let user, let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: userKey)
        } else {
            UserDefaults.standard.removeObject(forKey: userKey)
        }
    }
}
