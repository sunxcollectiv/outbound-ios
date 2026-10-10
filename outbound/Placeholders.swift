//
//  Placeholders.swift
//  outbound
//

import SwiftUI

/// A dashed outlined box marking where real content will go once the trip/itinerary
/// APIs are wired up. Styled to sit on the terracotta theme background.
struct DashedPlaceholder: View {
    var label: String?
    var height: CGFloat?
    var cornerRadius: CGFloat = 12

    init(_ label: String? = nil, height: CGFloat? = nil, cornerRadius: CGFloat = 12) {
        self.label = label
        self.height = height
        self.cornerRadius = cornerRadius
    }

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.appForeground.opacity(0.06))
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(Color.appForeground.opacity(0.45))
            }
            .overlay {
                if let label {
                    Text(label)
                        .font(.footnote)
                        .foregroundStyle(Color.appForeground.opacity(0.7))
                }
            }
    }
}

#Preview {
    VStack(spacing: 16) {
        DashedPlaceholder("Trip", height: 120)
        DashedPlaceholder(height: 60)
    }
    .padding()
    .appTheme()
}
