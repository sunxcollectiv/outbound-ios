//
//  AuthAPI.swift
//  outbound
//

import Foundation

/// Request and response shapes for the backend's auth endpoints.
///
///     POST /auth/signin   { email, password }        -> { token, user }
///     POST /auth/signup   { name, email, password }  -> { token, user }
///     POST /auth/signout                              -> 2xx (body ignored)
///     GET  /me                                        -> user
enum AuthAPI {
    struct SignInRequest: Encodable {
        let email: String
        let password: String
    }

    struct SignUpRequest: Encodable {
        let name: String
        let email: String
        let password: String
    }

    struct Session: Decodable {
        let token: String
        let user: User
    }

    static func signIn(email: String, password: String) -> Endpoint {
        Endpoint(path: "/auth/signin", method: .post, body: SignInRequest(email: email, password: password), requiresAuth: false)
    }

    static func signUp(name: String, email: String, password: String) -> Endpoint {
        Endpoint(path: "/auth/signup", method: .post, body: SignUpRequest(name: name, email: email, password: password), requiresAuth: false)
    }

    static let signOut = Endpoint(path: "/auth/signout", method: .post)

    static let me = Endpoint(path: "/me")
}
