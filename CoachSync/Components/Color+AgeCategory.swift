/// Maps age categories to shared UI colors.
import SwiftUI

/// Shared color helpers for age-category presentation.
extension Color {
    /// Returns the accent color associated with an age category.
    static func ageCategory(_ category: String) -> Color {
        switch category {
        case "U10": return .readablePurple
        case "U12": return .readableBlue
        case "U14": return .readableGreen
        case "U16": return .readableOrange
        case "U18": return .readableRed
        default:    return .readableGray
        }
    }
}
