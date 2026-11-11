//
//  LodgingBar.swift
//  outbound
//

import SwiftUI

/// The day's lodging, pinned under the trip header: one band split between the day's
/// stays and hatched floor where there's none. Square on top, where it meets the header.
///
/// - No lodging: all floor, inviting a stay to be added.
/// - A lone check-in or check-out: the stay takes 75% and the rest is floor, on the side
///   with no lodging (before arriving, or after leaving).
/// - Otherwise the stays share the width equally, so a changeover day shows its
///   check-out and check-in side by side, split by a faint line.
///
/// Changing day slides the band along as if it were one long timeline: a stay that
/// carries over keeps its place and resizes, one that has ended slides off the side the
/// days are moving toward, and one that's starting slides in from the other. The floor
/// never moves; stays slide over it. With Reduce Motion on, the band crossfades instead.
struct LodgingBar: View {
    let dayNumber: Int
    let lodging: [LodgingStay]
    /// What to call a stay.
    let name: (TripItem) -> String
    /// A stay was tapped.
    let onOpen: (TripItem) -> Void
    /// A stay was long-pressed.
    let onEdit: (TripItem) -> Void
    /// The empty bar of a day with no lodging was tapped.
    let onAdd: () -> Void

    /// What's drawn: the day's segments, plus any still sliding off from the day before.
    @State private var segments: [LodgingBarSegment]
    /// Counts day changes, so a change that's overtaken by the next doesn't finish over it.
    @State private var generation = 0
    /// While segments are on the move; see `stayName(_:)`.
    @State private var isSliding = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The curve the segments slide on: the same steep ease a card's details open on.
    private static let slide: Animation = .steepEase(duration: 0.3)

    init(
        dayNumber: Int,
        lodging: [LodgingStay],
        name: @escaping (TripItem) -> String,
        onOpen: @escaping (TripItem) -> Void,
        onEdit: @escaping (TripItem) -> Void,
        onAdd: @escaping () -> Void
    ) {
        self.dayNumber = dayNumber
        self.lodging = lodging
        self.name = name
        self.onOpen = onOpen
        self.onEdit = onEdit
        self.onAdd = onAdd
        _segments = State(initialValue: LodgingBarSegment.resting(for: lodging))
    }

    /// What the bar is showing, to notice when it changes: another day, or the same day
    /// after its lodging was added to, edited or removed.
    private struct Shown: Equatable {
        var dayNumber: Int
        var lodging: [LodgingStay]
    }

    var body: some View {
        // An invisible row sets the height (a line of the stays' font, or the arrow
        // badge if that's taller), so the bar is the same height on every day and the
        // segments can be laid out against its measured width.
        ZStack {
            Text(verbatim: " ")
                .font(.subheadline.weight(.semibold))
            Color.clear.frame(height: Self.arrowSize)
        }
        .hidden()
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .overlay {
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                        segmentView(
                            segment,
                            barWidth: geo.size.width,
                            // How far along the bar the segment starts.
                            leading: segments[..<index].reduce(0) { $0 + $1.fraction }
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            }
        }
        // Plain translucent fill, dark enough that cards scrolling underneath don't
        // compete with the lodging names.
        .background(Color(white: 0.12).opacity(0.8))
        .clipShape(.rect(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
        .onChange(of: Shown(dayNumber: dayNumber, lodging: lodging)) { old, new in
            show(new.lodging, forward: new.dayNumber >= old.dayNumber)
        }
    }

    // MARK: - Changing day

    private func show(_ lodging: [LodgingStay], forward: Bool) {
        guard !reduceMotion else {
            withAnimation(.easeInOut(duration: 0.2)) {
                segments = LodgingBarSegment.resting(for: lodging, keepingIdentityOf: segments)
            }
            return
        }

        let transition = LodgingBarSegment.transition(from: segments, to: lodging, forward: forward)
        // Nothing to move: the same lodging as the bar is already showing, or heading for.
        guard transition.settled != segments else { return }
        generation += 1
        let generation = generation
        // Arriving segments go in at no width first, unseen, so that they have somewhere
        // to slide from; the slide starts once they're in place.
        withoutAnimation {
            segments = transition.staged
            isSliding = true
        }
        DispatchQueue.main.async {
            guard generation == self.generation else { return }
            settle(on: transition.settled, generation: generation)
        }
    }

    private func settle(on settled: [LodgingBarSegment], generation: Int) {
        withAnimation(Self.slide, completionCriteria: .logicallyComplete) {
            segments = settled
        } completion: {
            // Drop what slid off, unless a later change is still moving things.
            guard generation == self.generation else { return }
            withoutAnimation { segments.removeAll(where: \.isLeaving) }
            isSliding = false
        }
    }

    private func withoutAnimation(_ body: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, body)
    }

    // MARK: - Segments

    /// A segment as a window `fraction` of the bar wide, clipping what it shows.
    @ViewBuilder
    private func segmentView(_ segment: LodgingBarSegment, barWidth: CGFloat, leading: CGFloat) -> some View {
        let width = max(barWidth * segment.fraction, 0)
        Group {
            switch segment.content {
            case .gap:
                // A window onto floor that spans the whole bar and stays put, so the
                // hatching and the add label hold still while stays slide over them.
                Button(action: onAdd) {
                    floor(invitesAdd: segment.invitesAdd)
                        .frame(width: barWidth)
                        .padding(.leading, -barWidth * leading)
                        .frame(width: width, alignment: .leading)
                        .frame(maxHeight: .infinity)
                        .overlay(alignment: .leading) { floorEdge.opacity(segment.leadingRule ? 1 : 0) }
                        .overlay(alignment: .trailing) { floorEdge.opacity(segment.trailingRule ? 1 : 0) }
                        .clipped()
                        .contentShape(.rect)
                }
                .buttonStyle(DimWhenPressedButtonStyle())
                .allowsHitTesting(segment.invitesAdd && !segment.isLeaving)
                .accessibilityLabel("Add lodging")
                .accessibilityHidden(!segment.invitesAdd || segment.isLeaving)
            case .stay(let stay):
                // Laid out at its own width, which a stay sliding on or off keeps while
                // its window closes over it, holding to the edge that's moving.
                stayRow(stay)
                    .frame(width: max(barWidth * segment.contentFraction, 0))
                    .frame(width: width, alignment: segment.pin == .leading ? .leading : .trailing)
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .leading) { stayDivider.opacity(segment.leadingRule ? 1 : 0) }
                    .clipped()
                    .allowsHitTesting(!segment.isLeaving)
                    .accessibilityHidden(segment.isLeaving)
            }
        }
        .transition(.opacity)
    }

    /// The bar with no stay on it: hatching, and the invitation to add one on a day
    /// that has none at all.
    private func floor(invitesAdd: Bool) -> some View {
        ZStack {
            DiagonalHatch()
            HStack(spacing: 6) {
                Image(systemName: "plus")
                Text("add lodging")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.appForeground.opacity(0.7))
            .opacity(invitesAdd ? 1 : 0)
        }
    }

    /// A solid line marking where a stay begins or ends against the floor.
    private var floorEdge: some View {
        Rectangle()
            .fill(Color(white: 0.35))
            .frame(width: 1)
    }

    /// A faint line between two stays side by side.
    private var stayDivider: some View {
        Rectangle()
            .fill(.white.opacity(0.15))
            .frame(width: 1)
            .padding(.vertical, 8)
    }

    /// A lodging chip: bed icon and name, with an arrow marking the phase, on the left
    /// for a check-in (arriving) and on the right for a check-out (leaving). A stay in
    /// progress shows "Staying" instead. The markers swap in place when the same stay
    /// moves on to its next phase.
    private func stayRow(_ stay: LodgingStay) -> some View {
        HStack(spacing: 0) {
            arrow(shown: stay.phase == .checkIn, spacing: .trailing)
            Image(systemName: stay.item.lodging?.propertyType?.systemImage ?? "bed.double.fill")
                .font(.caption)
            stayName(stay.item)
                .padding(.leading, 8)
            Spacer(minLength: 8)
            if stay.phase == .staying {
                Text(stay.phase.label)
                    .font(.caption)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
                    .fixedSize()
                    .padding(.leading, 8)
                    .transition(.opacity)
            }
            arrow(shown: stay.phase == .checkOut, spacing: .leading)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(.rect)
        .onTapGesture { onOpen(stay.item) }
        .onLongPressGesture { onEdit(stay.item) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name(stay.item)), \(stay.phase.label)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onOpen(stay.item) }
        .accessibilityAction(named: "Edit") { onEdit(stay.item) }
    }

    /// A stay's name on one line, truncated to fit.
    ///
    /// While the bar slides, a copy at its full width shows instead, clipped to the same
    /// space. Text draws its final truncation as soon as a slide starts, centered in a
    /// frame that's still catching up, so a name that's gaining room (a changeover's
    /// half widening to a full stay) would jump sideways over the icon beside it. The
    /// copy never re-truncates, so it stays put. Once the bar has settled the truncated
    /// name is back at once and the copy fades off it, so the letters they share hold
    /// steady and only the cut-off end gives way to the ellipsis.
    private func stayName(_ item: TripItem) -> some View {
        let text = Text(name(item))
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
        return text
            .animation(nil) { $0.opacity(isSliding ? 0 : 1) }
            .overlay(alignment: .leading) {
                text
                    .fixedSize()
                    .animation(isSliding ? nil : .easeOut(duration: 0.15)) { $0.opacity(isSliding ? 1 : 0) }
            }
            .clipped()
    }

    private static let arrowSize: CGFloat = 16

    /// The phase arrow, with room on the side facing the name. Always in the row, at no
    /// size when not `shown`, so that it grows and shrinks where it sits as the row
    /// moves; one put in or taken out would hang where the row was or will be.
    private func arrow(shown: Bool, spacing edge: Edge.Set) -> some View {
        Image(systemName: "arrow.right")
            .font(.system(size: 8, weight: .heavy))
            .foregroundStyle(Color(white: 0.15))
            .frame(width: Self.arrowSize, height: Self.arrowSize)
            .background(Color.appForeground, in: .circle)
            .scaleEffect(shown ? 1 : 0.01)
            .opacity(shown ? 1 : 0)
            .frame(width: shown ? Self.arrowSize : 0)
            .padding(edge, shown ? 15 : 0)
    }
}

// MARK: - Layout

/// One stretch of the lodging bar: a stay, or floor where there's none.
struct LodgingBarSegment: Identifiable, Equatable {
    enum Content: Equatable {
        case stay(LodgingStay)
        case gap
    }

    /// What a segment is of, for following it from one day to the next.
    enum Key: Hashable {
        case stay(String)
        case gap
    }

    var id = UUID()
    var content: Content
    /// The share of the bar's width the segment takes. None once it has slid off, or
    /// before it slides on.
    var fraction: CGFloat
    /// The share of the bar's width its content is laid out at: its own, except while
    /// sliding on or off, when the content keeps its width and the segment clips it.
    var contentFraction: CGFloat
    /// The edge the content holds to while the segment is narrower than it.
    var pin: HorizontalEdge = .leading
    /// Sliding off; dropped once it's gone.
    var isLeaving = false
    /// A line on the leading edge: where floor meets the stay before it, or between two
    /// stays side by side.
    var leadingRule = false
    /// A line on the trailing edge, where floor meets the stay after it.
    var trailingRule = false
    /// Floor that's the whole bar, on a day with no lodging: shows the add label.
    var invitesAdd = false

    var key: Key {
        switch content {
        case .stay(let stay): .stay(stay.item.id)
        case .gap: .gap
        }
    }

    private var isStay: Bool { key != .gap }

    /// The bar at rest on a day with this lodging.
    static func resting(for lodging: [LodgingStay]) -> [LodgingBarSegment] {
        // A changeover day's stays in the order they happen: leaving one, then
        // arriving at the next.
        let stays = lodging.sorted { $0.phase.dayOrder < $1.phase.dayOrder }

        func segment(_ content: Content, _ fraction: CGFloat) -> LodgingBarSegment {
            LodgingBarSegment(content: content, fraction: fraction, contentFraction: fraction)
        }

        var segments: [LodgingBarSegment]
        if stays.isEmpty {
            segments = [segment(.gap, 1)]
        } else if stays.count == 1, let stay = stays.first, stay.phase != .staying {
            let chip = segment(.stay(stay), 0.75)
            let floor = segment(.gap, 0.25)
            segments = stay.phase == .checkIn ? [floor, chip] : [chip, floor]
        } else {
            segments = stays.map { segment(.stay($0), 1 / CGFloat(stays.count)) }
        }

        for index in segments.indices {
            let followsStay = index > 0 && segments[index - 1].isStay
            let precedesStay = index < segments.count - 1 && segments[index + 1].isStay
            if segments[index].isStay {
                segments[index].leadingRule = followsStay
            } else {
                segments[index].leadingRule = followsStay
                segments[index].trailingRule = precedesStay
                segments[index].invitesAdd = segments.count == 1
            }
        }
        return segments
    }

    /// The bar at rest, for swapping to without sliding. When it's the same arrangement
    /// as `current` (the same stays and floor at the same widths), the segments keep
    /// their identity, so only what changed within them updates.
    static func resting(for lodging: [LodgingStay], keepingIdentityOf current: [LodgingBarSegment]) -> [LodgingBarSegment] {
        var segments = resting(for: lodging)
        let current = current.filter { !$0.isLeaving }
        guard segments.map(\.key) == current.map(\.key),
              segments.map(\.fraction) == current.map(\.fraction) else { return segments }
        for index in segments.indices {
            segments[index].id = current[index].id
        }
        return segments
    }
}

/// A move of the lodging bar from one day's lodging to another's, in two steps.
struct LodgingBarTransition: Equatable {
    /// What's on the bar now, with the arriving segments added at no width. Set without
    /// animating; nothing visibly changes.
    var staged: [LodgingBarSegment]
    /// The same segments at where they end up, the departing ones at no width. Animate
    /// to this, then drop the ones marked `isLeaving`.
    var settled: [LodgingBarSegment]
}

extension LodgingBarSegment {
    /// Works out how the bar gets from `current` to a day with `lodging`.
    ///
    /// Segments on both days (the same stay, or floor) carry over and resize in place.
    /// The rest slide: the bar reads as a window on one long timeline, so whatever is
    /// only on the old day closes up against its neighbor and whatever is only on the
    /// new day opens out from it. Where old gives way directly to new (no segment in
    /// common between them), `forward` decides which side each is on: moving to a later
    /// day, the old slides off toward the leading edge as the new comes in from the
    /// trailing edge.
    ///
    /// `current` may hold segments still sliding off from an earlier change; they keep
    /// going, or carry on from where they are if the new day has them after all.
    static func transition(from current: [LodgingBarSegment], to lodging: [LodgingStay], forward: Bool) -> LodgingBarTransition {
        let target = resting(for: lodging)

        // The segments that carry over must sit in the same order on both days to
        // resize in place. Floor is the usual exception (a one-night stay has it before
        // the stay on arrival and after it on departure), so it's the first to be
        // treated as two different stretches; failing that, nothing carries over.
        var carried = pairs(of: target, in: current, includingGap: true)
        if !isInOrder(carried) { carried = pairs(of: target, in: current, includingGap: false) }
        if !isInOrder(carried) { carried = [] }

        var staged: [LodgingBarSegment] = []
        var settled: [LodgingBarSegment] = []

        /// Adds the stretch between two carried segments: what's leaving and what's
        /// arriving there.
        func addChanging(old: Range<Int>, new: Range<Int>, beforeFirstCarried: Bool) {
            let hasBoth = !old.isEmpty && !new.isEmpty
            // Content holds to the edge that moves: the boundary between old and new
            // where both are here, else the carried segment alongside.
            let alone: HorizontalEdge = beforeFirstCarried && !carried.isEmpty ? .trailing : .leading
            let oldPin: HorizontalEdge = hasBoth ? (forward ? .trailing : .leading) : alone
            let newPin: HorizontalEdge = hasBoth ? (forward ? .leading : .trailing) : alone

            var leavingStaged: [LodgingBarSegment] = []
            var leavingSettled: [LodgingBarSegment] = []
            for var segment in current[old] {
                // One already on its way out keeps going as it was.
                if !segment.isLeaving { segment.pin = oldPin }
                leavingStaged.append(segment)
                segment.fraction = 0
                segment.isLeaving = true
                leavingSettled.append(segment)
            }

            var arrivingStaged: [LodgingBarSegment] = []
            var arrivingSettled: [LodgingBarSegment] = []
            for var segment in target[new] {
                segment.pin = newPin
                arrivingSettled.append(segment)
                segment.fraction = 0
                arrivingStaged.append(segment)
            }

            staged += forward ? leavingStaged + arrivingStaged : arrivingStaged + leavingStaged
            settled += forward ? leavingSettled + arrivingSettled : arrivingSettled + leavingSettled
        }

        var oldIndex = 0
        var newIndex = 0
        for (position, pair) in carried.enumerated() {
            addChanging(old: oldIndex..<pair.old, new: newIndex..<pair.new, beforeFirstCarried: position == 0)
            staged.append(current[pair.old])
            var segment = target[pair.new]
            segment.id = current[pair.old].id
            segment.pin = current[pair.old].pin
            settled.append(segment)
            oldIndex = pair.old + 1
            newIndex = pair.new + 1
        }
        addChanging(old: oldIndex..<current.count, new: newIndex..<target.count, beforeFirstCarried: carried.isEmpty)

        return LodgingBarTransition(staged: staged, settled: settled)
    }

    /// Each target segment with the current one it continues, if any, in target order.
    /// Where there's a choice, one that's staying beats one that's sliding off.
    private static func pairs(of target: [LodgingBarSegment], in current: [LodgingBarSegment], includingGap: Bool) -> [(old: Int, new: Int)] {
        var taken: Set<Int> = []
        var pairs: [(old: Int, new: Int)] = []
        for (new, segment) in target.enumerated() where includingGap || segment.isStay {
            let candidates = current.indices.filter { current[$0].key == segment.key && !taken.contains($0) }
            guard let old = candidates.first(where: { !current[$0].isLeaving }) ?? candidates.first else { continue }
            taken.insert(old)
            pairs.append((old: old, new: new))
        }
        return pairs
    }

    private static func isInOrder(_ pairs: [(old: Int, new: Int)]) -> Bool {
        zip(pairs, pairs.dropFirst()).allSatisfy { $0.old < $1.old }
    }
}

// MARK: - Pieces

/// Faint diagonal stripes filling the space they're given, marking part of the lodging
/// bar with no stay.
private struct DiagonalHatch: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing: CGFloat = 7
            var x = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(.white.opacity(0.07)), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Dims its label while pressed, and otherwise leaves it alone.
private struct DimWhenPressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
