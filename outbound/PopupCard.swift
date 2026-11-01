//
//  PopupCard.swift
//  outbound
//

import SwiftUI

/// Shared look for the centered popup cards (members, invites, lodging, dates): the
/// card's size, shape, border and shadow, so every popup matches. A card hugs its
/// content, and scrolls inside its border once that's taller than the room it's given.
struct PopupCard: ViewModifier {
    var background: Color
    var border: Color
    let onClose: () -> Void

    /// The widest a card gets, on larger screens.
    static let maxWidth: CGFloat = 400
    /// The gap between a card and the screen edge on phones.
    static let sideMargin: CGFloat = 16
    static let cornerRadius: CGFloat = 20

    /// The content's natural height, padding included.
    @State private var contentHeight: CGFloat = 0
    /// The height the card was given room for.
    @State private var shownHeight: CGFloat = 0

    /// Whether the content fits without scrolling. Only then may it draw past the
    /// card's edge, like a suggestion list; scrolled content has to stay inside.
    private var fits: Bool { contentHeight > 0 && shownHeight >= contentHeight - 0.5 }

    func body(content: Content) -> some View {
        // Always in a scroll view, rather than only when needed, so the content keeps
        // its identity, and a focused field its focus, as the room changes (e.g. when
        // the keyboard comes up).
        ScrollView {
            content
                .padding(20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .frame(maxHeight: contentHeight > 0 ? contentHeight : nil)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(fits)
        .scrollClipDisabled(fits)
        .foregroundStyle(Color.appForeground)
        .frame(maxWidth: Self.maxWidth)
        // The border sits behind the content (not over it), so anything floating out
        // past the card's edge, like a suggestion list, covers it.
        .background {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(background)
                .overlay(RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(border))
        }
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

/// A popup card centered over a dimmed screen, with a round close button just below
/// it; tapping the button or the dimmed area closes it. Show it from an `.overlay`
/// while the popup is open, changing that state inside `withAnimation` so the
/// backdrop fades and the card scales in and out, and move the offline pill down to
/// meet it with `offlinePillNearBottom(isActive:)` on the same screen.
///
/// The card and close button keep clear of the offline pill at the bottom; a card
/// taller than the room left scrolls (see `PopupCard`).
struct DimmedPopup<Card: View>: View {
    let onClose: () -> Void
    @ViewBuilder let card: () -> Card

    /// The coordinate space spanning the visible area a popup sits in, so a card can
    /// tell how much room is left above or below a view of its own.
    static var space: NamedCoordinateSpace { .named("DimmedPopup") }

    /// Height of the visible area, which shrinks while the keyboard is up.
    @State private var visibleHeight: CGFloat = 0
    /// The offline pill's height at the current text size.
    @ScaledMetric(relativeTo: .footnote) private var pillHeight = OfflinePill.height

    /// The gap kept between a popup and the top of the screen, and the offline pill.
    private static var edgeGap: CGFloat { 12 }

    /// Room kept free at the bottom of the screen (or above the keyboard) for the
    /// offline pill, which sits there over a popup.
    private var pillClearance: CGFloat {
        OfflinePill.nearBottomGap + pillHeight + Self.edgeGap
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)
                .accessibilityHidden(true)
                .transition(.opacity)
            VStack(spacing: 16) {
                card()
                    // Above the close button, so anything floating off the card's bottom
                    // edge (like a suggestion list) draws over it.
                    .zIndex(1)
                closeButton
            }
            .padding(.top, Self.edgeGap)
            // Measured from the screen's bottom edge, like the pill's own spot; the
            // keyboard still pushes it up.
            .padding(.bottom, pillClearance)
            .ignoresSafeArea(.container, edges: .bottom)
            .transition(.scale(scale: 0.94).combined(with: .opacity))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { visibleHeight = $0 }
        .coordinateSpace(Self.space)
        .environment(\.popupVisibleHeight, visibleHeight)
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.appForeground)
                .frame(width: 44, height: 44)
                .background(Color(white: 0.15), in: .circle)
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
                .shadow(color: .black.opacity(0.4), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
    }
}

extension EnvironmentValues {
    /// Height of the visible area a `DimmedPopup` fills (above the keyboard when it's
    /// up), measured in `DimmedPopup.space`; zero outside a popup.
    @Entry var popupVisibleHeight: CGFloat = 0
}
