//
//  FormBottomBar.swift
//  outbound
//

import SwiftUI

/// The bar pinned under the trip and trip item forms, so it stays in reach however far
/// the form scrolls: an optional notify checkbox, Save, and Delete under it when
/// there's something to delete (after a confirmation, since it can't be undone).
struct FormBottomBar: View {
    /// What deleting is called and confirmed with, and what it does.
    struct Delete {
        /// The button, e.g. "Delete Trip".
        let title: String
        /// The confirmation's question, e.g. "Delete this trip?".
        let confirmation: String
        let message: String
        let action: () -> Void
    }

    /// The notify checkbox's label; nil hides the checkbox.
    var notifyLabel: String?
    @Binding var notifyMembers: Bool
    let saveTitle: String
    /// Whether the form is complete enough to save, e.g. it has a title.
    let canSave: Bool
    let isSaving: Bool
    let onSave: () -> Void
    /// Nil hides Delete, e.g. for something not saved yet.
    var delete: Delete?
    let isDeleting: Bool
    /// The sheet's bottom safe area (the home indicator's strip), measured by the form
    /// so the bar can sit partway into it.
    let homeIndicatorInset: CGFloat
    let background: Color

    /// Showing the confirmation before deleting.
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 4) {
            if let notifyLabel {
                notifyMembersCheckbox(notifyLabel)
                    .padding(.bottom, 8)
            }
            saveButton
            if let delete {
                deleteButton(delete)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        // With Delete last, halfway into the home indicator's strip: closer to the edge,
        // but nothing tappable reaches the strip the home swipe starts in. With Save
        // last, a flat 50pt above the screen's bottom edge on every device.
        .padding(.bottom, delete != nil ? -homeIndicatorInset / 2 : 50 - homeIndicatorInset)
        .background(background.ignoresSafeArea())
    }

    private func notifyMembersCheckbox(_ label: String) -> some View {
        Button {
            notifyMembers.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: notifyMembers ? "checkmark.square.fill" : "square")
                    .font(.title3)
                Text(label)
                    .font(.subheadline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(notifyMembers ? .isSelected : [])
    }

    private var saveButton: some View {
        Button(action: onSave) {
            Group {
                if isSaving {
                    ProgressView()
                } else {
                    Text(saveTitle)
                        .bold()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: appFieldCornerRadius))
        .disabled(isSaving || isDeleting || !canSave)
    }

    private func deleteButton(_ delete: Delete) -> some View {
        Button(role: .destructive) {
            confirmingDelete = true
        } label: {
            Group {
                if isDeleting {
                    ProgressView().tint(Color.appError)
                } else {
                    Text(delete.title)
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.appError)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving || isDeleting)
        .confirmationDialog(delete.confirmation, isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive, action: delete.action)
        } message: {
            Text(delete.message)
        }
    }
}
