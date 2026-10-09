//
//  SignInView.swift
//  outbound
//

import SwiftUI

struct SignInView: View {
    enum Mode {
        case signIn, signUp
    }

    @Environment(AuthStore.self) private var auth

    @State private var mode: Mode = .signIn
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                VStack(spacing: 12) {
                    if mode == .signUp {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)
                            .fieldStyle()
                    }
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .fieldStyle()
                    SecureField("Password", text: $password)
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .fieldStyle()
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(action: submit) {
                    Group {
                        if isWorking {
                            ProgressView()
                        } else {
                            Text(mode == .signIn ? "Sign In" : "Create Account")
                                .bold()
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: fieldCornerRadius))
                .disabled(isWorking)

                Button(mode == .signIn ? "Don't have an account? Sign up" : "Already have an account? Sign in") {
                    withAnimation {
                        mode = mode == .signIn ? .signUp : .signIn
                        errorMessage = nil
                    }
                }
                .font(.footnote)
            }
            .padding(24)
            .padding(.top, 60)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image("OutboundWordmark")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 152)
                .padding(.bottom, 16)
                .accessibilityLabel("Outbound")
            Text(mode == .signIn ? "Where are we going next?" : "Create your account")
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        errorMessage = nil
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                switch mode {
                case .signIn: try await auth.signIn(email: email, password: password)
                case .signUp: try await auth.signUp(name: name, email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

/// Shared corner radius for input fields and the submit button.
private let fieldCornerRadius: CGFloat = 10

private extension View {
    func fieldStyle() -> some View {
        multilineTextAlignment(.center)
            .padding(14)
            .foregroundStyle(Color.black.opacity(0.85))
            .tint(Color.appAccent)
            .background(Color.white.opacity(0.9), in: .rect(cornerRadius: fieldCornerRadius))
    }
}

#Preview {
    SignInView()
        .appTheme()
        .environment(AuthStore())
}
