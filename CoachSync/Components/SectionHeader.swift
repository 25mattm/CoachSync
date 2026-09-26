/// Shared section title styling for stacked dashboard-style layouts.
import SwiftUI

/// Bold section header used in custom scroll-based screens.
struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.title3)
            .fontWeight(.bold)
            .padding(.top, 4)
    }
}
