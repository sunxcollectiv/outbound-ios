//
//  OfflinePill.swift
//  outbound
//

import SwiftUI
import UIKit

/// A small pill saying there's no connection, with a word on what that means for the
/// screen on display, e.g. how old the saved copy is.
struct OfflinePill: View {
    var detail: Detail?

    enum Detail: Hashable {
        /// Showing a copy saved at this date.
        case saved(Date)
        /// Edits can be made, but not saved.
        case cantSave
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
            Text("Offline")
            if let detail {
                // A new view per detail, so a change crossfades the words.
                detailText(detail)
                    .foregroundStyle(.white.opacity(0.65))
                    .id(detail)
                    .transition(.opacity)
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // Keeps the outgoing words inside the pill while it narrows.
        .clipShape(.capsule)
        .background(Color(white: 0.15).opacity(0.95), in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    private func detailText(_ detail: Detail) -> Text {
        switch detail {
        case .saved(let date): Text("· saved \(date, format: .relative(presentation: .named))")
        case .cantSave: Text("· can't save yet")
        }
    }
}

/// Where the offline pill goes, and what it says, as told by the screens on display.
/// The pill itself is drawn in its own window over the whole app (see
/// `OfflinePillWindow`), so sheets and popups opened over a screen never hide it.
@Observable
final class OfflinePillCenter {
    static let shared = OfflinePillCenter()

    /// One screen's say on the pill.
    struct Placement: Equatable {
        /// Where the pill's bottom edge goes, in screen points from the top.
        var bottomY: CGFloat
        /// Forms can't save offline, so they say so instead of how old the copy is.
        var isForm: Bool
        var savedDate: Date?
        /// Shows the pill with a connection too, e.g. while the server is erroring
        /// and the saved copy is showing.
        var showsWhenOnline: Bool
        /// Steps aside for something else in the spot, like a toast.
        var isHidden: Bool
        /// Only moves the pill, keeping what the screen below says about it, e.g. for
        /// a popup over a form.
        var keepsScreenBelow = false
    }

    /// In the order the screens appeared; the last is the one on top.
    private(set) var placements: [(id: UUID, placement: Placement)] = []

    var current: Placement? { current(skipping: { _ in false }) }

    /// The top screen's placement, leaving out those `isLeaving` says are on their
    /// way out, with what the pill says taken from the first screen below that has
    /// its own say, if the top one only moves it.
    func current(skipping isLeaving: (Placement) -> Bool) -> Placement? {
        let placements = placements.map(\.placement).filter { !isLeaving($0) }
        guard var top = placements.last else { return nil }
        if top.keepsScreenBelow, let below = placements.dropLast().last(where: { !$0.keepsScreenBelow }) {
            top.isForm = below.isForm
            top.savedDate = below.savedDate
            top.showsWhenOnline = below.showsWhenOnline
            top.isHidden = below.isHidden
        }
        return top
    }

    func set(_ placement: Placement, for id: UUID) {
        if let index = placements.firstIndex(where: { $0.id == id }) {
            if placements[index].placement != placement { placements[index].placement = placement }
        } else {
            placements.append((id, placement))
        }
    }

    func remove(_ id: UUID) {
        placements.removeAll { $0.id == id }
    }
}

extension View {
    /// Places the offline pill `spacing` above this view's top edge while this screen
    /// is on display, and on top of anything later presented over it that doesn't
    /// place it itself.
    func offlinePillAnchor(
        spacing: CGFloat = 0,
        isForm: Bool = false,
        savedDate: Date? = nil,
        showsWhenOnline: Bool = false,
        isHidden: Bool = false,
        keepsScreenBelow: Bool = false,
        isActive: Bool = true
    ) -> some View {
        modifier(OfflinePillAnchor(spacing: spacing, isForm: isForm, savedDate: savedDate, showsWhenOnline: showsWhenOnline, isHidden: isHidden, keepsScreenBelow: keepsScreenBelow, isActive: isActive))
    }
}

extension View {
    /// Moves the offline pill down to 50pt above the screen's bottom edge (or the
    /// keyboard) while this view is on display, keeping what the screen below says,
    /// for things that cover a screen without a place of their own for it, like
    /// popups and detail sheets. Apply it to a view filling the screen.
    ///
    /// For a popup, apply it to the screen showing it, with `isActive` saying whether
    /// the popup is open, rather than inside the popup: the pill then moves back as
    /// soon as the popup starts closing. From inside, it would wait until SwiftUI is
    /// done removing the popup, which comes well after it looks gone.
    func offlinePillNearBottom(isActive: Bool = true) -> some View {
        overlay {
            Color.clear
                .frame(height: 0)
                .offlinePillAnchor(spacing: 50, keepsScreenBelow: true, isActive: isActive)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(.container, edges: .bottom)
                .allowsHitTesting(false)
        }
    }
}

private struct OfflinePillAnchor: ViewModifier {
    let spacing: CGFloat
    let isForm: Bool
    let savedDate: Date?
    let showsWhenOnline: Bool
    let isHidden: Bool
    let keepsScreenBelow: Bool
    let isActive: Bool

    @State private var id = UUID()
    @State private var top: CGFloat?
    @State private var isOnScreen = false

    private var placement: OfflinePillCenter.Placement? {
        top.map { .init(bottomY: $0 - spacing, isForm: isForm, savedDate: savedDate, showsWhenOnline: showsWhenOnline, isHidden: isHidden, keepsScreenBelow: keepsScreenBelow) }
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top = $0 }
            .onAppear { isOnScreen = true; update() }
            .onDisappear { isOnScreen = false; OfflinePillCenter.shared.remove(id) }
            .onChange(of: placement) { update() }
            .onChange(of: isActive) { update() }
    }

    private func update() {
        guard isActive else { return OfflinePillCenter.shared.remove(id) }
        guard isOnScreen, let placement else { return }
        OfflinePillCenter.shared.set(placement, for: id)
    }
}

/// Draws the offline pill where the screen on top placed it. It's the same pill
/// throughout: moving between screens slides it to the new spot and changes its words.
private struct OfflinePillOverlay: View {
    private var center = OfflinePillCenter.shared
    private var connectivity = Connectivity.shared

    /// The placement drawn. Holds on to the last one for a moment when none is left,
    /// since a screen leaving can drop its placement just before the next one adds
    /// its own, and the pill should move across rather than leave and come back.
    @State private var placement: OfflinePillCenter.Placement?
    @State private var clearTask: Task<Void, Never>?
    /// The words drawn after "Offline". Changed once the pill has stopped moving:
    /// words fading in or out mid-move are drawn where the pill was or will be,
    /// outside it.
    @State private var detail: OfflinePill.Detail?
    /// Moves to a new spot still under way.
    @State private var movesInFlight = 0
    /// The screen's bottom safe area, the home indicator's strip.
    @State private var bottomInset: CGFloat = 0
    @State private var screenHeight: CGFloat = 0

    /// The lowest the pill rests anywhere: the trips list's spot, 8pt over the
    /// bottom safe area.
    private var lowestGap: CGFloat { bottomInset + 8 }

    /// Where the pill should be. A screen whose spot is lower than any the pill rests
    /// in is on its way out, e.g. a sheet that has started sliding off the bottom,
    /// so the pill heads for the screen below right away instead of once it's gone.
    private var target: OfflinePillCenter.Placement? {
        guard screenHeight > 0 else { return center.current }
        return center.current { screenHeight - $0.bottomY < lowestGap - 1 }
    }

    var body: some View {
        GeometryReader { proxy in
            let isShowing = placement.map { !$0.isHidden && (!connectivity.isConnected || $0.showsWhenOnline) } ?? false
            ZStack(alignment: .bottom) {
                if isShowing, let placement {
                    OfflinePill(detail: detail)
                        .padding(.bottom, max(proxy.size.height - placement.bottomY, lowestGap))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .animation(.snappy, value: isShowing)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { screenHeight = $0 }
        }
        .ignoresSafeArea()
        // Measured outside the safe-area-ignoring reader above, which sees none.
        .background {
            Color.clear.onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
        }
        .onChange(of: target, initial: true) { _, current in
            clearTask?.cancel()
            if let current {
                if placement != nil, placement?.bottomY != current.bottomY {
                    movesInFlight += 1
                    withAnimation(.snappy) {
                        placement = current
                    } completion: {
                        movesInFlight -= 1
                        updateDetail()
                    }
                } else {
                    withAnimation(.snappy) { placement = current }
                }
                updateDetail()
            } else {
                clearTask = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled else { return }
                    placement = nil
                }
            }
        }
    }

    private static func detail(for placement: OfflinePillCenter.Placement) -> OfflinePill.Detail? {
        placement.isForm ? .cantSave : placement.savedDate.map(OfflinePill.Detail.saved)
    }

    /// Fades the words to what the current placement says, unless the pill is on
    /// its way to a new spot, in which case this runs again once it gets there.
    private func updateDetail() {
        guard movesInFlight == 0, let placement else { return }
        let newDetail = Self.detail(for: placement)
        guard newDetail != detail else { return }
        withAnimation(.easeInOut(duration: 0.2)) { detail = newDetail }
    }
}

/// A window over the app's own, holding only the offline pill. Taps pass straight
/// through to the app below.
enum OfflinePillWindow {
    private static var window: UIWindow?

    /// Puts the window up once, over the app's active scene.
    static func install() {
        guard window == nil,
              let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene
        else { return }
        let host = UIHostingController(rootView: OfflinePillOverlay())
        host.view.backgroundColor = .clear
        let window = PassthroughWindow(windowScene: scene)
        window.rootViewController = host
        window.windowLevel = .normal + 1
        window.isUserInteractionEnabled = false
        window.isHidden = false
        self.window = window
    }

    private final class PassthroughWindow: UIWindow {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }
}

#Preview {
    VStack {
        OfflinePill(detail: .saved(.now.addingTimeInterval(-3 * 60 * 60)))
        OfflinePill(detail: .cantSave)
        OfflinePill()
    }
        .padding()
        .background(.black)
}
