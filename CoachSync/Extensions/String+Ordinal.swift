/// String helpers used for formatting coach-facing text.
import Foundation

/// Shared string formatting helpers.
extension String {
    /// Formats an integer as an English ordinal such as `1st` or `22nd`.
    static func ordinal(_ number: Int) -> String {
        // Derive the suffix from the magnitude so negative inputs (which Swift's
        // `%` would leave negative) still get a grammatical suffix.
        let magnitude = abs(number)
        let suffix: String
        let tens = (magnitude / 10) % 10
        let ones = magnitude % 10

        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }

        return "\(number)\(suffix)"
    }
}
