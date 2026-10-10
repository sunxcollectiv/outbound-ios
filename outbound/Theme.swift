//
//  Theme.swift
//  outbound
//

import SwiftUI

/// Central color palette for the app, matching the warm terracotta travel theme.
extension Color {
    /// Warm terracotta/clay used as the primary background.
    static let appBackground = Color(red: 0.69, green: 0.42, blue: 0.27)

    /// Cream/off-white used for primary text and icons.
    static let appForeground = Color(red: 0.95, green: 0.91, blue: 0.84)

    /// Accent used for buttons and highlights — a slightly deeper rust.
    static let appAccent = Color(red: 0.55, green: 0.30, blue: 0.18)

    /// Translucent card surface that sits over the background.
    static let appCard = Color(red: 0.62, green: 0.36, blue: 0.23)
}

/// Applies the app's warm terracotta color theme: background, foreground, and tint.
///
/// Apply this at the top of a screen hierarchy. It's also used in `#Preview`s so
/// previews match what runs in the simulator (where theming comes from `AuthView`).
struct AppTheme: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Color.appBackground.ignoresSafeArea())
            .foregroundStyle(Color.appForeground)
            .tint(Color.appAccent)
    }
}

extension View {
    func appTheme() -> some View {
        modifier(AppTheme())
    }

    /// White, rounded input field used across forms (auth and trip creation).
    func appField(cornerRadius: CGFloat = appFieldCornerRadius) -> some View {
        foregroundStyle(Color.black.opacity(0.85))
            .tint(Color.appAccent)
            .padding(14)
            .background(Color.white.opacity(0.9), in: .rect(cornerRadius: cornerRadius))
    }
}

/// Shared corner radius for input fields and buttons, keeping them visually in sync.
let appFieldCornerRadius: CGFloat = 10
