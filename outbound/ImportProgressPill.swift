//
//  ImportProgressPill.swift
//  outbound
//

import SwiftUI

/// A pill above the day picker tracking a booking screenshot as the server turns it
/// into itinerary items: one line saying what's happening, over a green fill that
/// grows from the left until the pill is fully green. It doesn't block the itinerary;
/// you can keep scrolling and editing while it works.
struct ImportProgressPill: View {
    /// How far along the import is, 0 to 1.
    let progress: Double

    /// What's happening at this point of the import.
    private var title: String {
        switch progress {
        case ..<0.25: "Uploading screenshot…"
        case ..<0.7: "Reading booking…"
        case ..<1: "Adding to itinerary…"
        default: "Added to itinerary"
        }
    }

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
            .padding(.horizontal, 12)
            .background(alignment: .leading) {
                GeometryReader { proxy in
                    Self.fill
                        .frame(width: proxy.size.width * min(max(progress, 0), 1))
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
            .accessibilityValue(Text(progress, format: .percent.precision(.fractionLength(0))))
    }
}

#Preview {
    ZStack {
        Color(white: 0.1).ignoresSafeArea()
        VStack(spacing: 16) {
            ForEach([0.1, 0.45, 0.85, 1], id: \.self) { progress in
                ImportProgressPill(progress: progress)
            }
        }
        .padding(24)
    }
    .appTheme()
}
