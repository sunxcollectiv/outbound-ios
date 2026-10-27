//
//  ItemMembersPopup.swift
//  outbound
//

import SwiftUI

/// A centered card for choosing which of the trip's members an item is for, shown
/// over the item form. Tapping a member toggles them in `selectedIds`.
struct ItemMembersPopup: View {
    let members: [TripMember]
    /// The signed-in user's id, so their row reads "You".
    let currentUserId: String?
    @Binding var selectedIds: Set<String>
    let onClose: () -> Void

    /// Natural height of the member list, so the card hugs it until it needs to scroll.
    @State private var listHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label("Who's Going", systemImage: "person.2.fill")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase)
                    .tracking(1)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .frame(width: 28, height: 28)
                        .background(Color.appForeground.opacity(0.12), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if members.isEmpty {
                Text("Add people to the trip to include them here.")
                    .font(.footnote)
                    .foregroundStyle(Color.appForeground.opacity(0.6))
                    .padding(.horizontal, 4)
            } else {
                ScrollView {
                    memberList
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .frame(height: min(listHeight, 320))
                .scrollBounceBehavior(.basedOnSize)
            }

            Button(action: onClose) {
                Text("Done")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(Color(white: 0.15))
                    .background(Color.appForeground, in: .rect(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(Color.appForeground)
        .padding(20)
        .frame(maxWidth: 360)
        .background(Color(white: 0.15), in: .rect(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.08)))
        .shadow(color: .black.opacity(0.4), radius: 24, y: 10)
        .padding(.horizontal, 24)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    private var memberList: some View {
        VStack(spacing: 0) {
            ForEach(Array(members.enumerated()), id: \.element.id) { index, member in
                memberRow(member)
                if index < members.count - 1 {
                    Divider().overlay(Color.appForeground.opacity(0.15))
                }
            }
        }
        .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
    }

    private func memberRow(_ member: TripMember) -> some View {
        let isSelected = selectedIds.contains(member.id)
        let isYou = member.user?.id != nil && member.user?.id == currentUserId
        let name = member.user?.displayName ?? member.email
        return Button {
            withAnimation(.snappy(duration: 0.15)) {
                if isSelected {
                    selectedIds.remove(member.id)
                } else {
                    selectedIds.insert(member.id)
                }
            }
        } label: {
            HStack(spacing: 12) {
                Text(String(name.first(where: \.isLetter) ?? "?").uppercased())
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
                    .background(Color.appForeground.opacity(0.18), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isYou ? "\(name) (You)" : name)
                        .font(.subheadline)
                        .lineLimit(1)
                    // Members without an account only have their email, already shown.
                    if member.user != nil {
                        Text(member.email)
                            .font(.caption)
                            .foregroundStyle(Color.appForeground.opacity(0.6))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.appForeground : Color.appForeground.opacity(0.35))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#if DEBUG
#Preview {
    @Previewable @State var selected: Set<String> = ["m1"]
    let members = [
        TripMember(id: "m1", email: "sam@example.com", user: User(id: "u1", email: "sam@example.com", displayName: "Sam", avatarUrl: nil, createdAt: .now), role: .organizer),
        TripMember(id: "m2", email: "jesse@example.com", user: nil, role: .member),
    ]
    ZStack {
        Color.black.ignoresSafeArea()
        ItemMembersPopup(members: members, currentUserId: "u1", selectedIds: $selected, onClose: {})
    }
}
#endif
