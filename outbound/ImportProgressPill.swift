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
/// Each step eases the fill on to its share of the pill over a few seconds, so it
/// keeps moving while the server works, and the check lands once the last one fills.
struct ImportProgressPill: View {
    enum Step: CaseIterable {
        case uploading, extracting, added

        var title: String {
            switch self {
            case .uploading: "Uploading image"
            case .extracting: "Extracting details"
            case .added: "Added to itinerary"
            }
        }

        /// How much of the pill is green by the end of this step.
        var progress: Double {
            switch self {
            case .uploading: 1 / 3
            case .extracting: 2 / 3
            case .added: 1
            }
        }
    }

    let step: Step

    /// How long each step takes to fill to its share.
    static let stepDuration: Double = 3

    /// The fill as drawn, animated toward `step.progress`.
    @State private var shownProgress: Double = 0
    /// Set once the last step's fill has finished, to show the check.
    @State private var isComplete = false

    private var title: String { step.title }

    /// The fill's green: deep enough that white text stays readable on it.
    static let fill = Color(red: 0.24, green: 0.55, blue: 0.36)

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
                    Self.fill
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

    private func advance(to step: Step) {
        withAnimation(.linear(duration: Self.stepDuration)) {
            shownProgress = step.progress
        } completion: {
            isComplete = step == .added && shownProgress >= 1
        }
    }

    /// An empty ring while the import runs, filled white with a green check once done.
    private var statusCircle: some View {
        ZStack {
            Circle()
                .strokeBorder(.white.opacity(0.6), lineWidth: 1.5)
            Circle()
                .fill(.white)
                .scaleEffect(isComplete ? 1 : 0.2)
                .opacity(isComplete ? 1 : 0)
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(Self.fill)
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
