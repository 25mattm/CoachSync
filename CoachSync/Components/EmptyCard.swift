/// Reusable empty-state card used across list and dashboard sections.
import SwiftUI

/// Displays an icon and message for empty content states.
struct EmptyCard: View {
    let message: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            Group {
                if #available(iOS 26, *) { Color.clear }
                else { RoundedRectangle(cornerRadius: 14).fill(.regularMaterial) }
            }
        )
        .ifAvailableiOS26 { $0.glassEffect(.regular, in: .rect(cornerRadius: 14)) }
    }
}
