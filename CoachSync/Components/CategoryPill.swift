/// Capsule-style label used to display an athlete age category.
import SwiftUI

/// Presents an age category using the shared category color mapping.
struct CategoryPill: View {
    let category: String

    var body: some View {
        Text(category)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.ageCategory(category).opacity(0.15))
            .foregroundStyle(Color.ageCategory(category))
            .clipShape(Capsule())
    }
}
