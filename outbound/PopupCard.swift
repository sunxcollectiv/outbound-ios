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
    /// Whether the card is still animating to a new content height, during which its
    /// content stays clipped so what's being added doesn't spill out past the border.
    @State private var isResizing = false
    /// The height the card was given room for.
    @State private var shownHeight: CGFloat = 0

    /// Where the content is scrolled to, for the jump buttons to move.
    @State private var position = ScrollPosition(edge: .top)
    /// Whether the content is scrolled all the way up, or all the way down.
    @State private var atTop = true
    @State private var atBottom = true

    /// The tap area of the arrow buttons outside the card that jump to its top or bottom.
    static let jumpButtonSize: CGFloat = 32
    /// The gap between a jump button and the card's edge.
    static let jumpButtonGap: CGFloat = 8
    /// The room a jump button takes above the card, for a popup to keep clear.
    static var jumpButtonRoom: CGFloat { jumpButtonSize + jumpButtonGap }

    /// Whether the content fits without scrolling. Only then may it draw past the
    /// card's edge, like a suggestion list; scrolled content has to stay inside.
    private var fits: Bool { contentHeight > 0 && shownHeight >= contentHeight - 0.5 }

    /// Whether the jump buttons may show: only once the content scrolls, and not mid
    /// resize, when growing content that will still fit would flash them.
    private var showsJumpButtons: Bool { !fits && !isResizing }

    func body(content: Content) -> some View {
        // Always in a scroll view, rather than only when needed, so the content keeps
        // its identity, and a focused field its focus, as the room changes (e.g. when
        // the keyboard comes up).
        ScrollView {
            content
                .padding(20)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resize(to: $0) }
        }
        .frame(maxHeight: contentHeight > 0 ? contentHeight : nil)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
        .scrollPosition($position)
        .onScrollGeometryChange(for: [Bool].self) { geometry in
            [geometry.visibleRect.minY <= 1, geometry.visibleRect.maxY >= geometry.contentSize.height - 1]
        } action: { _, edges in
            withAnimation(.easeInOut(duration: 0.2)) {
                atTop = edges[0]
                atBottom = edges[1]
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        // The indicator runs right along the card's edge (iOS insets it a few points),
        // kept off the rounded corners at its ends.
        .contentMargins(.trailing, -3, for: .scrollIndicators)
        .contentMargins(.vertical, Self.cornerRadius / 2, for: .scrollIndicators)
        .scrollDisabled(fits)
        .scrollClipDisabled(fits && !isResizing)
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
        // Just outside the card's top and bottom right corners, each showing only
        // while there's more to scroll that way.
        .overlay(alignment: .topTrailing) {
            jumpButton(to: .top, isShowing: showsJumpButtons && !atTop)
                .alignmentGuide(.top) { $0[.bottom] + Self.jumpButtonGap }
        }
        .overlay(alignment: .bottomTrailing) {
            jumpButton(to: .bottom, isShowing: showsJumpButtons && !atBottom)
                .alignmentGuide(.bottom) { $0[.top] - Self.jumpButtonGap }
        }
        .padding(.horizontal, Self.sideMargin)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    /// Grows or shrinks the card to its content's new height, animated, so content
    /// added or removed inside (an expanding section, a new row) eases the card along
    /// instead of snapping it. The first measurement just sizes it.
    private func resize(to height: CGFloat) {
        guard contentHeight > 0 else { return contentHeight = height }
        guard abs(height - contentHeight) > 0.5 else { return }
        isResizing = true
        withAnimation(Self.resizeAnimation) {
            contentHeight = height
        } completion: {
            isResizing = false
        }
    }

    /// How the card eases to a new height; content fading in or out inside it should
    /// match, e.g. by changing in `withAnimation(PopupCard.resizeAnimation)`.
    static let resizeAnimation = Animation.snappy(duration: 0.3)

    /// For content added inside a card: fades in once the card has grown part of the
    /// way, so it shows up into room already made for it, and fades straight out when
    /// removed, so the card isn't left waiting to shrink.
    static var contentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity.animation(.easeOut(duration: 0.25).delay(0.12)),
            removal: .opacity.animation(.easeIn(duration: 0.12))
        )
    }

    private func jumpButton(to edge: Edge, isShowing: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { position.scrollTo(edge: edge) }
        } label: {
            JumpToEdgeIcon(edge: edge)
                .foregroundStyle(Color.appForeground.opacity(0.6))
                // A bare glyph, with a frame big enough to tap easily.
                .frame(width: Self.jumpButtonSize, height: Self.jumpButtonSize)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(edge == .top ? "Scroll to Top" : "Scroll to Bottom")
        .opacity(isShowing ? 1 : 0)
        .scaleEffect(isShowing ? 1 : 0.8)
        .allowsHitTesting(isShowing)
        .accessibilityHidden(!isShowing)
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
            // Room above for the card's jump-to-top button.
            .padding(.top, Self.edgeGap + PopupCard.jumpButtonRoom)
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

/// A chevron with a bar across its tip, pointing to the top or bottom edge: like
/// the `arrow.up.to.line` symbol without the arrow's shaft, which SF Symbols lacks.
private struct JumpToEdgeIcon: View {
    let edge: Edge

    @ScaledMetric(relativeTo: .body) private var width: CGFloat = 12

    var body: some View {
        VStack(spacing: width * 0.2) {
            if edge == .top { bar }
            Image(systemName: edge == .top ? "chevron.up" : "chevron.down")
                .font(.system(size: width, weight: .semibold))
            if edge == .bottom { bar }
        }
        .accessibilityHidden(true)
    }

    private var bar: some View {
        Capsule()
            .frame(width: width * 1.1, height: width * 0.14)
    }
}
