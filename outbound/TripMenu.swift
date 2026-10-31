//
//  TripMenu.swift
//  outbound
//

import SwiftUI

/// The dropdown under the itinerary header's more button: the trip's dates up top, then
/// adding items (by hand, one row per kind, or from a screenshot), then the trip's
/// actions. Drawn by hand rather than as a system `Menu`, so it can take the app's
/// styling and grow richer rows than a menu allows.
struct TripMenu: View {
    let trip: Trip
    /// Adds an item by hand, opening the form for the kind picked.
    let onAddItem: (TripItemKind) -> Void
    let onImportScreenshot: () -> Void
    let onCopyTripsEmail: () -> Void
    let onEditTrip: () -> Void
    let onShare: () -> Void
    /// Nil hides the row, for anyone but the trip's owner.
    let onDeleteTrip: (() -> Void)?
    @State private var connectivity = Connectivity.shared

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
            sectionHeading("Itinerary")
            row("Add Activity", systemImage: "plus") { onAddItem(.activity) }
            row("Add Lodging", systemImage: "bed.double") { onAddItem(.lodging) }
            row("Add Transit", systemImage: "airplane") { onAddItem(.transit) }
            // Offline, rows that save straight away are disabled; the forms the others open
            // stay editable and only block saving.
            row("Import from Screenshot", systemImage: "photo", isEnabled: connectivity.isConnected, action: onImportScreenshot)
            // Dotted rather than solid: forwarding is another way into the itinerary, so
            // it stays grouped with the rows above.
            dottedDivider
            forwardEmailRow
            divider
            row("Edit Trip", systemImage: "pencil", action: onEditTrip)
            row("Share", systemImage: "square.and.arrow.up", action: onShare)
            if let onDeleteTrip {
                divider
                row("Delete Trip", systemImage: "trash", tint: Color(red: 1, green: 0.45, blue: 0.42), isEnabled: connectivity.isConnected, action: onDeleteTrip)
            }
        }
        .foregroundStyle(.white)
        .frame(width: 260)
        .background {
            let shape = RoundedRectangle(cornerRadius: 14)
            shape
                .fill(.ultraThinMaterial)
                // Dark gray, the lodging popup's card color, nearly opaque over the blur.
                .overlay(shape.fill(Color(white: 0.15).opacity(0.92)))
                .overlay(shape.strokeBorder(.white.opacity(0.12)))
                .environment(\.colorScheme, .dark)
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
    }

    /// A small caption naming the rows below it.
    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }

    /// A reminder that booking emails can be forwarded to the trips inbox; tapping copies
    /// the address.
    private var forwardEmailRow: some View {
        Button(action: onCopyTripsEmail) {
            HStack(spacing: 12) {
                Image(systemName: "envelope")
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Or forward emails to")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                    Text(verbatim: AddLodgingPopup.tripsEmail)
                        .font(.subheadline.weight(.medium))
                }
                Spacer(minLength: 0)
                Image(systemName: "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(.rect)
        }
        .buttonStyle(TripMenuRowStyle())
        .accessibilityLabel("Copy \(AddLodgingPopup.tripsEmail)")
    }

    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
    }

    /// A lighter break within a section, inset to line up with the row text.
    private var dottedDivider: some View {
        DashedLine()
            .stroke(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            .frame(height: 1)
            .padding(.horizontal, 14)
    }

    private func row(_ title: String, systemImage: String, tint: Color = .white, isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
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
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// A horizontal line across the middle of its frame, for dashed strokes.
struct DashedLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
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
        TripMenu(trip: .sample, onAddItem: { _ in }, onImportScreenshot: {}, onCopyTripsEmail: {}, onEditTrip: {}, onShare: {}, onDeleteTrip: {})
            .padding()
    }
}
