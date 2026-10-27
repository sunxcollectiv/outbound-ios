//
//  MemberInvitePopup.swift
//  outbound
//

import SwiftUI

/// A centered card for inviting people to a trip by email, shown over the trip form.
/// Each submitted address is added to `emails` straight away and listed beneath the
/// field, so several can be entered in a row before closing.
struct MemberInvitePopup: View {
    @Binding var emails: [String]
    let onClose: () -> Void

    @State private var text = ""
    @State private var errorMessage: String?
    /// Natural height of the email list, so the card hugs it until it needs to scroll.
    @State private var listHeight: CGFloat = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                Label("Add Members", systemImage: "person.2.fill")
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

            VStack(alignment: .leading, spacing: 8) {
                emailField
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.appForeground.opacity(0.75))
                        .padding(.horizontal, 4)
                }
            }

            emailList

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
        .onAppear { isFocused = true }
    }

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var emailField: some View {
        HStack(spacing: 8) {
            Image(systemName: "envelope")
                .foregroundStyle(Color.black.opacity(0.45))
            TextField("Email address", text: $text)
                .keyboardType(.emailAddress)
                .textContentType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(add)
                .onChange(of: text) { _, _ in errorMessage = nil }
            Button("Add", action: add)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.appAccent)
                .buttonStyle(.plain)
                .disabled(trimmedText.isEmpty)
                .opacity(trimmedText.isEmpty ? 0.4 : 1)
        }
        .appField()
    }

    /// The invited emails, scrolling once there are more than fit in the card.
    @ViewBuilder
    private var emailList: some View {
        if emails.isEmpty {
            Text("Invited members will appear here.")
                .font(.footnote)
                .foregroundStyle(Color.appForeground.opacity(0.6))
                .padding(.horizontal, 4)
        } else {
            ScrollView {
                MemberEmailList(emails: $emails)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .frame(height: min(listHeight, 240))
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    /// Adds the typed address to the list, keeping focus so the next one can be typed.
    private func add() {
        let email = trimmedText.lowercased()
        guard !email.isEmpty else { return }
        guard Self.isValidEmail(email) else {
            errorMessage = "That doesn't look like an email address."
            isFocused = true
            return
        }
        guard !emails.contains(email) else {
            errorMessage = "\(email) is already on the list."
            isFocused = true
            return
        }
        withAnimation(.snappy(duration: 0.2)) { emails.append(email) }
        text = ""
        isFocused = true
    }

    /// A loose shape check: something@something.tld, no spaces.
    static func isValidEmail(_ email: String) -> Bool {
        email.wholeMatch(of: /[^@\s]+@[^@\s]+\.[^@\s]+/) != nil
    }
}

/// Rows of invited emails, each with an avatar initial and a remove button.
struct MemberEmailList: View {
    @Binding var emails: [String]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(emails.enumerated()), id: \.element) { index, email in
                HStack(spacing: 12) {
                    Text(String(email.first(where: \.isLetter) ?? "?").uppercased())
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(Color.appForeground.opacity(0.18), in: .circle)
                    Text(email)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button {
                        withAnimation(.snappy(duration: 0.2)) { emails.removeAll { $0 == email } }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.footnote.weight(.semibold))
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.appForeground.opacity(0.7))
                    .accessibilityLabel("Remove \(email)")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

                if index < emails.count - 1 {
                    Divider().overlay(Color.appForeground.opacity(0.15))
                }
            }
        }
        .background(Color.appForeground.opacity(0.08), in: .rect(cornerRadius: appFieldCornerRadius))
    }
}

#Preview {
    @Previewable @State var emails = ["sam@example.com"]
    ZStack {
        Color.black.ignoresSafeArea()
        MemberInvitePopup(emails: $emails, onClose: {})
    }
}
