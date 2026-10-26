//
//  ImportProgressPill.swift
//  outbound
//

import SwiftUI

/// A pill above the day picker tracking a booking screenshot as the server turns it
/// into itinerary items: one line saying which step it's on, over a green fill that
/// grows from the left until the pill is fully green. It doesn't block the itinerary;
/// you can keep scrolling and editing while it works.
///
/// Each step fills on to its share of the pill over a few seconds, so it keeps moving
/// while the server works, and the check lands once the last one fills. A step that
/// arrives before the fill has finished the one before first catches the fill up to
/// where the new step starts, quickly, then fills from there.
///
/// If the import fails at any point, the fill carries on to the full width while
/// gradually turning red, and the circle shows an x.
struct ImportProgressPill: View {
    enum Step: CaseIterable {
        case uploading, extracting, added, failed

        var title: String {
            switch self {
            case .uploading: "Uploading image"
            case .extracting: "Extracting details"
            case .added: "Added to itinerary"
            case .failed: "Image process failed"
            }
        }

        /// How much of the pill is filled by the end of this step.
        var progress: Double {
            switch self {
            case .uploading: 1 / 3
            case .extracting: 2 / 3
            case .added, .failed: 1
            }
        }

        /// How much is filled as this step starts: where the step before it ends. A
        /// failure fills straight from wherever the fill had got to.
        var startProgress: Double {
            switch self {
            case .uploading, .failed: 0
            case .extracting: Step.uploading.progress
            case .added: Step.extracting.progress
            }
        }
    }

    let step: Step

    /// How long each step takes to fill to its share.
    static let stepDuration: Double = 3
    /// How long a lagging fill takes to catch up to the start of the next step.
    static let catchUpDuration: Double = 0.5
    /// How long a failure takes to fill the pill and turn it red.
    static let failDuration: Double = 1

    /// The fill's animation target, which SwiftUI draws toward.
    @State private var shownProgress: Double = 0
    /// The fill's current run, so we can tell roughly how far along it is mid-animation
    /// (SwiftUI only exposes where an animation is headed), to decide whether a new
    /// step needs a catch-up first.
    @State private var run = FillRun(from: 0, to: 0, start: .now, duration: 0)
    /// Bumped on each step, so a superseded run's completion doesn't carry on.
    @State private var generation = 0
    /// Set once the last step's fill has finished, to show the check (or the x).
    @State private var isComplete = false
    /// How far the fill has turned from green to red, 0 to 1, once the import fails.
    @State private var failedTint: Double = 0

    /// One linear stretch of the fill.
    private struct FillRun {
        let from: Double
        let to: Double
        let start: Date
        let duration: Double

        func progress(at date: Date) -> Double {
            guard duration > 0 else { return to }
            let elapsed = min(max(date.timeIntervalSince(start) / duration, 0), 1)
            return from + (to - from) * elapsed
        }
    }

    private var title: String { step.title }

    /// The fill's green: deep enough that white text stays readable on it.
    static let fill = Color(red: 0.24, green: 0.55, blue: 0.36)
    /// The failed fill: a red with a touch of pink, deep enough for white text too.
    static let failedFill = Color(red: 0.84, green: 0.27, blue: 0.33)

    private var fillColor: Color { step == .failed ? Self.failedFill : Self.fill }

    var body: some View {
        Text(title)
            // Caption 2 is 11pt.
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            // Shrinks rather than truncating when the pill is narrow.
            .minimumScaleFactor(0.85)
            .contentTransition(.opacity)
            // Only the text crossfades; the fill tracks progress as it comes.
            .animation(.snappy, value: title)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            // Room on both sides for the status circle, so the text stays centered.
            .padding(.horizontal, 28)
            .overlay(alignment: .trailing) { statusCircle.padding(.trailing, 7) }
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    // Red blended over the green, so a failure changes the color in
                    // place rather than painting a new bar in from the left.
                    Self.fill
                        .overlay(Self.failedFill.opacity(failedTint))
                        .frame(width: proxy.size.width * min(max(shownProgress, 0), 1))
                }
            }
            .background {
                // Frosted like the trip menu, so cards scrolling behind don't show through.
                let shape = Capsule()
                shape
                    .fill(.ultraThinMaterial)
                    .overlay(shape.fill(Color(white: 0.15).opacity(0.92)))
                    .environment(\.colorScheme, .dark)
            }
            .clipShape(.capsule)
            .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue(Text(step.progress, format: .percent.precision(.fractionLength(0))))
            .onAppear { advance(to: step) }
            .onChange(of: step) { _, step in advance(to: step) }
    }

    /// Fills on to `step`'s share over `stepDuration`, first catching up to where the
    /// step starts over `catchUpDuration` if the fill is still short of it.
    private func advance(to step: Step) {
        generation += 1
        let current = generation
        let now = Date.now
        let drawn = run.progress(at: now)
        if step == .failed {
            // On to full from wherever the fill is, turning red as it goes: nothing
            // more is coming.
            isComplete = false
            run = FillRun(from: drawn, to: 1, start: now, duration: Self.failDuration)
            withAnimation(.easeInOut(duration: Self.failDuration)) {
                shownProgress = 1
                failedTint = 1
            } completion: {
                guard generation == current else { return }
                isComplete = true
            }
        } else if drawn < step.startProgress - 0.001 {
            // Rush to the step's start; SwiftUI carries on from wherever the fill is.
            run = FillRun(from: drawn, to: step.startProgress, start: now, duration: Self.catchUpDuration)
            withAnimation(.easeOut(duration: Self.catchUpDuration)) {
                shownProgress = step.startProgress
            } completion: {
                guard generation == current else { return }
                fill(step, from: step.startProgress)
            }
        } else {
            fill(step, from: drawn)
        }
    }

    private func fill(_ step: Step, from start: Double) {
        let current = generation
        run = FillRun(from: start, to: step.progress, start: .now, duration: Self.stepDuration)
        withAnimation(.linear(duration: Self.stepDuration)) {
            shownProgress = step.progress
        } completion: {
            guard generation == current else { return }
            isComplete = step == .added
        }
    }

    /// An empty ring while the import runs, then filled white with a check in the
    /// fill's color once done, or an x once failed.
    private var statusCircle: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
            Circle()
                .fill(.white)
                .scaleEffect(isComplete ? 1 : 0.2)
                .opacity(isComplete ? 1 : 0)
            Image(systemName: step == .failed ? "xmark" : "checkmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(fillColor)
                .scaleEffect(isComplete ? 1 : 0.5)
                .opacity(isComplete ? 1 : 0)
        }
        .frame(width: 15, height: 15)
        .animation(.spring(duration: 0.35, bounce: 0.4), value: isComplete)
    }
}

#Preview {
    ZStack {
        Color(white: 0.1).ignoresSafeArea()
        VStack(spacing: 16) {
            ForEach(ImportProgressPill.Step.allCases, id: \.self) { step in
                ImportProgressPill(step: step)
            }
        }
        .padding(24)
    }
    .appTheme()
}
