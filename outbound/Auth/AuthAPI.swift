//
//  AuthAPI.swift
//  outbound
//

import Foundation

/// Request and response shapes for the backend's auth endpoints.
///
///     POST /auth/login     { email, password }                        -> TokenRead
///     POST /auth/register  { email, password, display_name, ... }     -> TokenRead (201)
///     POST /auth/logout                                               -> 204 (no body)
///     GET  /users/me                                                  -> UserRead
enum AuthAPI {
    /// `Credentials` — body for `POST /auth/login`.
    struct LoginRequest: Encodable {
        let email: String
        let password: String
    }

    /// `UserCreate` — body for `POST /auth/register`.
    struct RegisterRequest: Encodable {
        let email: String
        let password: String
        let displayName: String
        let avatarUrl: String?
    }

    /// `TokenRead` — returned by login and register.
    struct Session: Decodable {
        let token: String
        let expiresAt: Date
        let user: User
    }

    static func login(email: String, password: String) -> Endpoint {
        Endpoint(path: "/auth/login", method: .post, body: LoginRequest(email: email, password: password), requiresAuth: false)
    }

    static func register(email: String, password: String, displayName: String, avatarUrl: String? = nil) -> Endpoint {
        Endpoint(
            path: "/auth/register",
            method: .post,
            body: RegisterRequest(email: email, password: password, displayName: displayName, avatarUrl: avatarUrl),
            requiresAuth: false
        )
    }

    static let logout = Endpoint(path: "/auth/logout", method: .post)

    static let me = Endpoint(path: "/users/me")
}
