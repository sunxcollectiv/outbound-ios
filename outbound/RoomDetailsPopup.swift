//
//  RoomDetailsPopup.swift
//  outbound
//

import SwiftUI

/// The card for one room of a stay: its type and number side by side, each with its
/// label above it, the number taking a quarter of the width. Edits `room` in place;
/// the lodging form puts it back on the stay when the popup closes.
struct RoomDetailsPopup: View {
    @Binding var room: LodgingRoom
    let onClose: () -> Void

    /// The fields row's width, so the number can take a fixed share of it.
    @State private var rowWidth: CGFloat = 0

    /// The share of the row the room number takes.
    private static let numberShare: CGFloat = 0.25
    private static let fieldSpacing: CGFloat = 10

    /// The number field's width: a quarter of the row, less its share of the gap.
    private var numberWidth: CGFloat {
        max(0, (rowWidth - Self.fieldSpacing) * Self.numberShare)
    }

    var body: some View {
        HStack(alignment: .top, spacing: Self.fieldSpacing) {
            field("Room type", placeholder: "e.g. King, City View", text: text(\.roomType))
                .frame(maxWidth: .infinity)
            // Abbreviated: "Room number" doesn't fit a quarter of the row.
            field("Room No.", placeholder: "412", text: text(\.roomNumber))
                .frame(width: rowWidth > 0 ? numberWidth : nil)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .popupCard(background: .black, onClose: onClose)
    }

    /// One of the room's optional text fields as a field's text, empty for nil.
    private func text(_ field: WritableKeyPath<LodgingRoom, String?>) -> Binding<String> {
        Binding { room[keyPath: field] ?? "" } set: { room[keyPath: field] = $0 }
    }

    /// A label over its text field.
    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.appForeground.opacity(0.8))
                .lineLimit(1)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .appField()
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        RoomDetailsPopup(room: .constant(LodgingRoom(id: "r", roomNumber: "412", roomType: "1 King Bed, City view")), onClose: {})
    }
}
