//
//  TripMenu.swift
//  outbound
//

import SwiftUI

/// The dropdown under the itinerary header's more button: the trip's dates up top, then
/// its actions. Drawn by hand rather than as a system `Menu`, so it can match the
/// header and grow richer rows than a menu allows.
struct TripMenu: View {
    let trip: Trip
    let onEditTrip: () -> Void
    let onShare: () -> Void
    let onDeleteTrip: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(trip.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(trip.dateRangeText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            divider
            row("Edit Trip", systemImage: "pencil", action: onEditTrip)
            row("Share", systemImage: "square.and.arrow.up", action: onShare)
            divider
            row("Delete Trip", systemImage: "trash", tint: Color(red: 1, green: 0.45, blue: 0.42), action: onDeleteTrip)
        }
        .foregroundStyle(.white)
        .frame(width: 230)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14)
            shape
                .fill(.ultraThinMaterial)
                .overlay(shape.fill(Color.tripHeader.opacity(0.85)))
                .overlay(shape.strokeBorder(.white.opacity(0.12)))
                .environment(\.colorScheme, .dark)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
    }

    private func row(_ title: String, systemImage: String, tint: Color = .white, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .frame(width: 20)
                Text(title)
                Spacer(minLength: 0)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(.rect)
        }
        .buttonStyle(TripMenuRowStyle())
    }
}

/// Highlights a row while it's pressed, as a system menu does.
private struct TripMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.white.opacity(configuration.isPressed ? 0.12 : 0))
    }
}

#Preview {
    ZStack(alignment: .topTrailing) {
        Color.black.ignoresSafeArea()
        TripMenu(trip: .sample, onEditTrip: {}, onShare: {}, onDeleteTrip: {})
            .padding()
    }
}
