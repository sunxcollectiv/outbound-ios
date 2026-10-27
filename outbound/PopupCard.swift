//
//  PopupCard.swift
//  outbound
//

import SwiftUI

/// Shared look for the centered popup cards (members, invites, lodging, dates): the
/// card's size, shape, border and shadow, so every popup matches.
struct PopupCard: ViewModifier {
    var background: Color
    var border: Color
    let onClose: () -> Void

    /// The widest a card gets, on larger screens.
    static let maxWidth: CGFloat = 400
    /// The gap between a card and the screen edge on phones.
    static let sideMargin: CGFloat = 16
    static let cornerRadius: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .foregroundStyle(Color.appForeground)
            .padding(20)
            .frame(maxWidth: Self.maxWidth)
            .background(background, in: .rect(cornerRadius: Self.cornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(border))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
            .padding(.horizontal, Self.sideMargin)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onClose)
    }
}

extension View {
    /// Styles this as a popup card; `onClose` backs VoiceOver's escape gesture.
    func popupCard(
        background: Color = Color(white: 0.15),
        border: Color = .white.opacity(0.08),
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(PopupCard(background: background, border: border, onClose: onClose))
    }
}

/// A popup card centered over a dimmed screen; tapping the dimmed area closes it.
/// Show it from an `.overlay` while the popup is open, changing that state inside
/// `withAnimation` so the backdrop fades and the card scales in and out.
struct DimmedPopup<Card: View>: View {
    let onClose: () -> Void
    @ViewBuilder let card: () -> Card

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
                .transition(.opacity)
            card()
                .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
    }
}
