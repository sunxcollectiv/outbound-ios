//
//  LeadingDrawer.swift
//  outbound
//

import SwiftUI

/// Wraps a screen with a drawer that slides in over it from the leading edge.
/// It opens through `isOpen` or by swiping right from the screen's left edge, and
/// closes by tapping the dimmed screen or swiping it back to the left.
struct LeadingDrawer<Content: View, Drawer: View>: View {
    @Binding var isOpen: Bool
    /// Whether a swipe from the left edge opens the drawer. Turned off while another
    /// screen is pushed, so the swipe stays the system back gesture there.
    var edgeSwipeEnabled = true
    @ViewBuilder let content: () -> Content
    @ViewBuilder let drawer: () -> Drawer

    /// The horizontal distance the current drag has moved the drawer.
    @State private var dragTranslation: CGFloat = 0
    /// Whether the current drag is moving the drawer, decided when it starts so a
    /// vertical scroll or a swipe away from the edge leaves the drawer alone.
    @State private var isTracking: Bool?

    /// How close to the left edge a swipe must start to open the drawer.
    private let edgeWidth: CGFloat = 28

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width * 0.8, 320)
            let revealed = min(max((isOpen ? width : 0) + dragTranslation, 0), width)
            let progress = revealed / width

            ZStack(alignment: .leading) {
                content()
                    .accessibilityHidden(isOpen)

                Color.black
                    .opacity(0.5 * progress)
                    .ignoresSafeArea()
                    .allowsHitTesting(isOpen)
                    .onTapGesture { setOpen(false) }
                    .accessibilityHidden(!isOpen)
                    .accessibilityLabel("Close Menu")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { setOpen(false) }

                drawer()
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .offset(x: revealed - width)
                    .accessibilityHidden(!isOpen)
                    .accessibilityAddTraits(.isModal)
            }
            .simultaneousGesture(drag(width: width), including: isOpen || edgeSwipeEnabled ? .all : .subviews)
        }
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                if isTracking == nil {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height)
                    let fromEdge = value.startLocation.x <= edgeWidth
                    isTracking = horizontal && (isOpen || fromEdge)
                }
                if isTracking == true {
                    dragTranslation = value.translation.width
                }
            }
            .onEnded { value in
                defer { isTracking = nil }
                guard isTracking == true else { return }
                let projected = (isOpen ? width : 0) + value.predictedEndTranslation.width
                setOpen(projected > width / 2)
            }
    }

    private func setOpen(_ open: Bool) {
        withAnimation(.snappy(duration: 0.3)) {
            isOpen = open
            dragTranslation = 0
        }
    }
}
