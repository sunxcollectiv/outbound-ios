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

    /// Slightly lifted dark gray for the profile drawer, so it reads as a layer above
    /// the trips grid.
    static let drawerBackground = Color(red: 0.20, green: 0.20, blue: 0.21)

    /// Dark gray behind modal form sheets, such as adding or editing a trip item.
    static let sheetBackground = Color(red: 0.20, green: 0.20, blue: 0.21)

    /// Slightly pinkish red for error and warning text, readable on the dark surfaces.
    static let appError = Color(red: 1.0, green: 0.42, blue: 0.47)

    /// Muted slate blue filling the header chip at the top of a trip's itinerary.
    static let tripHeader = Color(red: 0.29, green: 0.39, blue: 0.51)
}

extension LinearGradient {
    /// Very dark backdrop behind the trips grid, so the colored trip cards stand out: a
    /// subtle fade from a warmer, lighter gray at the top to near-black at the bottom.
    static let tripsBackground = LinearGradient(
        colors: [
            Color(red: 0.21, green: 0.19, blue: 0.18),
            Color(red: 0.10, green: 0.10, blue: 0.11)
        ],
        startPoint: .top,
        endPoint: .bottom
    )
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

/// A navigation-bar button styled consistently across the app: the system
/// Liquid Glass background is suppressed so the control reads as a plain glyph
/// or label rather than a circular capsule.
///
/// For icon buttons, bake the accessibility label into the label content, e.g.
/// `Image(systemName: "plus").accessibilityLabel("Add Trip")`.
struct AppToolbarButton<Label: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            Button(action: action, label: label)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// A navigation-bar menu with the same glass-free styling as `AppToolbarButton`:
/// a label (typically an icon) that presents a dropdown of actions on tap.
struct AppToolbarMenu<Label: View, Content: View>: ToolbarContent {
    let placement: ToolbarItemPlacement
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> Label

    var body: some ToolbarContent {
        ToolbarItem(placement: placement) {
            Menu(content: content, label: label)
        }
        .sharedBackgroundVisibility(.hidden)
    }
}
