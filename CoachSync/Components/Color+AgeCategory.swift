/// Maps age categories to shared UI colors.
import SwiftUI

/// Shared color helpers for age-category presentation.
extension Color {
    /// Returns the accent color associated with an age category.
    static func ageCategory(_ category: String) -> Color {
        switch category {
        case "U10": return .purple
        case "U12": return .blue
        case "U14": return .green
        case "U16": return .orange
        case "U18": return .red
        default:    return .gray
        }
    }
}
