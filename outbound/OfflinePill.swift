//
//  OfflinePill.swift
//  outbound
//

import SwiftUI

/// A small pill saying the screen is showing what was saved, because there's no
/// connection. `savedDate` adds how long ago that copy was saved.
struct OfflinePill: View {
    var text = "Offline"
    var savedDate: Date?

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "wifi.slash")
            Text(text)
            if let savedDate {
                Text("· saved \(savedDate, format: .relative(presentation: .named))")
                    .foregroundStyle(.white.opacity(0.65))
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(white: 0.15).opacity(0.95), in: .capsule)
        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    OfflinePill(text: "Offline · showing saved trips", savedDate: .now.addingTimeInterval(-3 * 60 * 60))
        .padding()
        .background(.black)
}
