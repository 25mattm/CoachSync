/// Capsule-style status label used for session state.
import SwiftUI

/// Presents a session status with matching color treatment.
/// Returns EmptyView for open sessions — only completed and cancelled sessions display a visible badge.
struct StatusPill: View {
    let status: SessionStatus

    var body: some View {
        if status == .completed || status == .cancelled {
            Text(status.rawValue)
                .font(.caption2)
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(status.color.opacity(0.15))
                .foregroundStyle(status.color)
                .clipShape(Capsule())
                .accessibilityLabel("Practice status")
                .accessibilityValue(status.rawValue)
        }
    }
}
