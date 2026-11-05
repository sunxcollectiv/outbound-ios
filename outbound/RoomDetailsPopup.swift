//
//  RoomDetailsPopup.swift
//  outbound
//

import SwiftUI

/// The card for one room of a stay: its type and number side by side, each with its
/// label above it, the number taking a quarter of the width; then who's in it. Edits
/// `room` in place; the lodging form puts it back on the stay when the popup closes.
///
/// Who's in it lists the stay's people first, then the rest of the trip (whom putting
/// in the room adds to the stay), then, dimmed and fixed, whoever is in another room.
/// A filled check marks someone in this room; an outlined one, another room.
struct RoomDetailsPopup: View {
    @Binding var room: LodgingRoom
    let assignments: RoomAssignments
    /// The signed-in user's id, so their row reads "You".
    let currentUserId: String?
    let onClose: () -> Void
    /// Removes the room from the stay; nil for a room being added, which closing
    /// without anything typed already discards.
    var onDelete: (() -> Void)? = nil

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
        VStack(alignment: .leading, spacing: 20) {
            fieldsRow
            occupantsSection
            if let onDelete {
                deleteButton(onDelete)
            }
        }
        .popupCard(background: .black, onClose: onClose)
    }

    private var fieldsRow: some View {
        HStack(alignment: .top, spacing: Self.fieldSpacing) {
            field("Room type", placeholder: "e.g. King, City View", text: text(\.roomType))
                .frame(maxWidth: .infinity)
            // Abbreviated: "Room number" doesn't fit a quarter of the row.
            field("Room No.", placeholder: "412", text: text(\.roomNumber))
                .frame(width: rowWidth > 0 ? numberWidth : nil)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
    }

    /// Red text across the bottom, like the forms' Delete. No confirmation: nothing
    /// is lost until the stay is saved.
    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button(role: .destructive, action: action) {
            Text("Delete Room")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appError)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Who's in it

    @ViewBuilder
    private var occupantsSection: some View {
        let hasAnyone = !assignments.participants.isEmpty || !assignments.others.isEmpty
            || !assignments.inOtherRooms.isEmpty
        if hasAnyone {
            VStack(alignment: .leading, spacing: 10) {
                label("Who's in this room")
                if !assignments.participants.isEmpty {
                    memberList(assignments.participants)
                }
                if !assignments.others.isEmpty {
                    Text("Assigning members below will add them to the lodging.")
                        .font(.footnote)
                        .foregroundStyle(Color.appForeground.opacity(0.6))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, assignments.participants.isEmpty ? 0 : 6)
                    memberList(assignments.others)
                }
                if !assignments.inOtherRooms.isEmpty {
                    placedList
                        .padding(.top, 6)
                }
            }
        }
    }

    /// Members who can go in this room, each toggled by a tap.
    private func memberList(_ members: [TripMember]) -> some View {
        listBackground {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                if index > 0 { divider }
                assignableRow(member)
            }
        }
    }

    private func assignableRow(_ member: TripMember) -> some View {
        let isIn = room.occupants.contains(member.id)
        return Button {
            withAnimation(.snappy(duration: 0.15)) {
                if isIn {
                    room.occupants.removeAll { $0 == member.id }
                } else {
                    room.occupants.append(member.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                MemberIdentity(member: member, currentUserId: currentUserId)
                Spacer(minLength: 8)
                Image(systemName: isIn ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isIn ? Color.appForeground : Color.appForeground.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isIn ? .isSelected : [])
    }

    /// Members already in another of the stay's rooms: dimmed, with that room's name
    /// and an outlined check, and not tappable.
    private var placedList: some View {
        listBackground {
            ForEach(Array(assignments.inOtherRooms.enumerated()), id: \.element.id) { index, placed in
                if index > 0 { divider }
                HStack(spacing: 12) {
                    MemberIdentity(member: placed.member, currentUserId: currentUserId, detail: "In \(placed.roomTitle)")
                    Spacer(minLength: 8)
                    Image(systemName: "checkmark.circle")
                        .font(.title3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .accessibilityElement(children: .combine)
            }
        }
        .opacity(0.45)
    }

    private func listBackground<Rows: View>(@ViewBuilder rows: () -> Rows) -> some View {
        VStack(spacing: 0, content: rows)
            .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
    }

    private var divider: some View {
        Divider().overlay(Color.appForeground.opacity(0.15))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Color.appForeground.opacity(0.8))
            .lineLimit(1)
    }

    /// One of the room's optional text fields as a field's text, empty for nil.
    private func text(_ field: WritableKeyPath<LodgingRoom, String?>) -> Binding<String> {
        Binding { room[keyPath: field] ?? "" } set: { room[keyPath: field] = $0 }
    }

    /// A label over its text field.
    private func field(_ label: String, placeholder: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            self.label(label)
            TextField(placeholder, text: text)
                .textInputAutocapitalization(.words)
                .appField()
        }
    }
}

#if DEBUG
#Preview {
    let sam = TripMember(id: "m1", email: "sam@example.com", user: User(id: "u1", email: "sam@example.com", displayName: "Sam", avatarUrl: nil, createdAt: .now), role: .organizer)
    let jesse = TripMember(id: "m2", email: "jesse@example.com", user: nil, role: .member)
    let alex = TripMember(id: "m3", email: "alex@example.com", user: nil, role: .member)
    ZStack {
        Color.black.ignoresSafeArea()
        RoomDetailsPopup(
            room: .constant(LodgingRoom(id: "r", roomNumber: "412", roomType: "1 King Bed, City view", occupants: ["m1"])),
            assignments: RoomAssignments(participants: [sam], others: [jesse], inOtherRooms: [.init(member: alex, roomTitle: "Room 2")]),
            currentUserId: "u1",
            onClose: {}
        )
    }
}
#endif
