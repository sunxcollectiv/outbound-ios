//
//  AddLodgingPopup.swift
//  outbound
//

import SwiftUI

/// A centered card offering the ways to add a stay: forward its confirmation email to
/// the trips inbox, upload an image of it, or fill in the form by hand. Shown over the
/// itinerary when a day's "add lodging" strip is tapped.
struct AddLodgingPopup: View {
    let onUploadImage: () -> Void
    let onAddManually: () -> Void
    let onClose: () -> Void

    /// The inbox that turns forwarded booking emails into trip items.
    static let tripsEmail = "trips@outbound.earth"

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label("Add Lodging", systemImage: "bed.double.fill")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Forward your booking confirmation email to")
                    .font(.subheadline)
                    .foregroundStyle(Color.appForeground.opacity(0.75))
                emailChip
            }

            HStack(spacing: 10) {
                Button(action: onUploadImage) {
                    optionLabel("Upload Image", systemImage: "photo.fill")
                        .foregroundStyle(Color.appForeground)
                        .background(Color.appForeground.opacity(0.12), in: .rect(cornerRadius: 10))
                }
                // Uploading saves straight away, so it waits for a connection.
                .requiresConnection()
                Button(action: onAddManually) {
                    optionLabel("Add Manually", systemImage: "square.and.pencil")
                        .foregroundStyle(Color(white: 0.15))
                        .background(Color.appForeground, in: .rect(cornerRadius: 10))
                }
            }
            // Both buttons as tall as the taller one.
            .fixedSize(horizontal: false, vertical: true)
            .buttonStyle(.plain)
        }
        .popupCard(onClose: onClose)
    }

    /// The trips address, tapped to copy so it can be pasted into a forwarded email.
    private var emailChip: some View {
        Button {
            UIPasteboard.general.string = Self.tripsEmail
            withAnimation(.snappy(duration: 0.2)) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.snappy(duration: 0.2)) { copied = false }
            }
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: Self.tripsEmail)
                    .font(.body.weight(.semibold))
                Spacer(minLength: 0)
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                    .contentTransition(.opacity)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.appForeground.opacity(0.3))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy \(Self.tripsEmail)")
    }

    /// Icon over title, matching the lodging popup's buttons.
    private func optionLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.body)
            Text(title)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        AddLodgingPopup(onUploadImage: {}, onAddManually: {}, onClose: {})
    }
}
