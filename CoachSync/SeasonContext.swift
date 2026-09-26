/// Centralizes season-year calculations shared across views, models, and reports.
import Foundation

/// Single source of truth for all season-year, date-window, and age-category
/// logic. Models and views must defer to these helpers rather than duplicating
/// season math, so the rules stay consistent and don't go stale across Jan 1.
enum SeasonContext {
    /// The calendar year of `referenceDate` (defaults to now) — the active season year.
    static func currentYear(calendar: Calendar = .current, referenceDate: Date = Date()) -> Int {
        calendar.component(.year, from: referenceDate)
    }

    /// The calendar year of an arbitrary date — e.g. a past regatta. Use this
    /// rather than `currentYear(referenceDate:)` when the date is not "now".
    static func year(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: date)
    }

    static func dateInterval(
        forYear year: Int = currentYear(),
        calendar: Calendar = .current
    ) -> DateInterval {
        let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)) ?? .distantPast
        let end = calendar.date(byAdding: .year, value: 1, to: start) ?? .distantFuture
        return DateInterval(start: start, end: end)
    }

    static func contains(
        _ date: Date,
        inYear year: Int = currentYear(),
        calendar: Calendar = .current
    ) -> Bool {
        let interval = dateInterval(forYear: year, calendar: calendar)
        return date >= interval.start && date < interval.end
    }

    /// Age as (season year − birth year). Uses the calendar year only — not a
    /// configurable cutoff date — per the app's age-category business rule.
    static func athleteAge(
        for dateOfBirth: Date,
        inYear year: Int = currentYear(),
        calendar: Calendar = .current
    ) -> Int {
        year - calendar.component(.year, from: dateOfBirth)
    }

    /// Competitive age category for a birth date. Under-5 returns "N/A", 19+
    /// returns "Senior"; everything else maps to U10–U18 by season-year age.
    static func ageCategory(for dateOfBirth: Date, inYear year: Int = currentYear()) -> String {
        let age = athleteAge(for: dateOfBirth, inYear: year)
        switch age {
        case ..<5:   return "N/A"
        case 5...10: return "U10"
        case ...12:  return "U12"
        case ...14:  return "U14"
        case ...16:  return "U16"
        case ...18:  return "U18"
        default:     return "Senior"
        }
    }

    /// Every category `ageCategory(for:)` can produce, in roster display order.
    /// "N/A" (under-5) must stay in this list — age-grouped lists only render
    /// categories that appear here, so dropping it hides those athletes.
    static let ageCategoryDisplayOrder: [String] = ["U10", "U12", "U14", "U16", "U18", "Senior", "N/A"]

    static func ageCategoryReferenceRows(forYear year: Int = currentYear()) -> [(category: String, rule: String)] {
        [
            ("U10", "Born \(year - 10) or later"),
            ("U12", "Born \(year - 12) or later"),
            ("U14", "Born \(year - 14) or later"),
            ("U16", "Born \(year - 16) or later"),
            ("U18", "Born \(year - 18) or later")
        ]
    }

    /// Completed sessions whose scheduled date falls in the given season year.
    static func completedSessions(
        from sessions: [CoachSession],
        inYear year: Int = currentYear(),
        calendar: Calendar = .current
    ) -> [CoachSession] {
        sessions.filter { $0.status == .completed && contains($0.scheduledDate, inYear: year, calendar: calendar) }
    }

    /// Completed sessions within the trailing `days`-day window ending at `referenceDate`.
    static func completedSessions(
        from sessions: [CoachSession],
        duringLastDays days: Int,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> [CoachSession] {
        let intervalStart = calendar.date(byAdding: .day, value: -days, to: referenceDate) ?? referenceDate
        return sessions.filter {
            $0.status == .completed &&
            $0.scheduledDate >= intervalStart &&
            $0.scheduledDate <= referenceDate
        }
    }

    /// Total training-load km across the given sessions' blocks, excluding the
    /// recovery zone (recovery km never counts toward load, per the load rules).
    static func loadKilometers(from sessions: [CoachSession]) -> Double {
        sessions
            .flatMap { $0.sessionBlocks ?? [] }
            .filter { $0.trainingZone != .recovery }
            .compactMap(\.effectiveDistanceKm)
            .reduce(0, +)
    }

    // MARK: - LTAD targets

    /// Yearly km training-load target range by age category, derived from
    /// CKC's Long-Term Athlete Development guidance. Returned as
    /// `(min, max)` km per season. Unrecognised categories fall through to
    /// the Senior range.
    static func ltadKmTarget(for ageCategory: String) -> (min: Double, max: Double) {
        switch ageCategory {
        case "U10": return (200, 300)
        case "U12": return (300, 700)
        case "U14": return (700, 1530)
        case "U16": return (2000, 3500)
        case "U18": return (3600, 4000)
        default:    return (3600, 4000)
        }
    }

    // MARK: - Development thresholds

    /// Annualised growth velocity (cm/year) at which an athlete is flagged
    /// as being in peak height velocity. Coaches reduce intensity around
    /// this threshold to protect joints and bones during rapid growth.
    static let phvVelocityThresholdCmPerYear: Double = 6.0
}
