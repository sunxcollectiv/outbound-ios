//
//  TripItemDetailView.swift
//  outbound
//

import SwiftUI

/// A sheet showing the details of a single trip item — an activity, a piece of
/// lodging, or a transit leg.
///
/// For now the layout is generic across all three kinds. The `content` switch is
/// the seam for later: each `TripItemKind` will grow its own tailored layout
/// (e.g. check-in/check-out emphasis for lodging, route/leg details for transit).
struct TripItemDetailView: View {
    let item: TripItem

    @Environment(\.dismiss) private var dismiss

    /// A soft off-white sheet — 90% white so it reads as light without the glare
    /// of pure white — with near-black text for contrast.
    private let sheetBackground = Color(white: 0.9)
    private let sheetForeground = Color(white: 0.1)

    var body: some View {
        NavigationStack {
            ZStack {
                sheetBackground.ignoresSafeArea()
                ScrollView {
                    content
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .foregroundStyle(sheetForeground)
            .tint(Color.appAccent)
            .navigationTitle(item.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(sheetBackground, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(sheetBackground)
    }

    /// The per-kind body. Every kind currently funnels to the same generic layout;
    /// this switch is where activity / lodging / transit layouts will diverge.
    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .activity, .lodging, .transit:
            genericDetail
        }
    }

    // MARK: - Generic layout

    private var genericDetail: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            detailSection(title: startLabel) {
                Text(item.startsAt, format: .dateTime.weekday().month().day().hour().minute())
            }

            if let endsAt = item.endsAt {
                detailSection(title: endLabel) {
                    Text(endsAt, format: .dateTime.weekday().month().day().hour().minute())
                }
            }

            if let notes = item.notes, !notes.isEmpty {
                detailSection(title: "Notes") {
                    Text(notes)
                }
            }

            if !item.tags.isEmpty {
                detailSection(title: "Tags") {
                    tagChips
                }
            }
        }
    }

    /// Kind and scope badges across the top.
    private var header: some View {
        HStack(spacing: 8) {
            badge(item.kind.label.uppercased())
            badge(item.scope.label.uppercased())
            Spacer()
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(1.5)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(sheetForeground.opacity(0.1), in: .capsule)
    }

    private var tagChips: some View {
        HStack(spacing: 8) {
            ForEach(item.tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(sheetForeground.opacity(0.1), in: .capsule)
            }
        }
    }

    /// A titled block: a small caption label above its content.
    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1)
                .foregroundStyle(sheetForeground.opacity(0.6))
            content()
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var startLabel: String { item.kind == .lodging ? "Check-in" : "Starts" }
    private var endLabel: String { item.kind == .lodging ? "Check-out" : "Ends" }
}

#Preview {
    TripItemDetailView(item: .sample)
}
