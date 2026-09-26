/// Pure, testable helpers for the coach-facing insight signals shown on
/// the athlete profile and the dashboard "Needs Attention" list.
///
/// The previous implementation duplicated regression and coefficient-of-variation
/// math across `AthleteInsightSection` and `NeedsAttentionSection`. Moving the
/// computations into top-level functions + an `Athlete` extension means:
/// - One canonical algorithm per signal type
/// - Magic numbers (slope thresholds, CV cutoff, recent-session windows) live
///   in one named place
/// - The math is unit-testable without any SwiftUI machinery
///
/// View code keeps its own thin wrappers / inline calls so the body markup
/// stays unchanged.

import Foundation

// MARK: - Tunable thresholds

/// Named magic numbers controlling how the insight signals fire.
enum InsightThresholds {
    /// Slope (ms per session-index step) above which a block is "declining"
    /// (the athlete is getting slower).
    static let decliningSlopeMs: Double = 50

    /// Slope below which a block is "most improved" (the athlete is getting
    /// faster). Negative because times decrease as athletes improve.
    static let improvingSlopeMs: Double = -50

    /// Coefficient-of-variation cutoff above which rep-to-rep pacing is
    /// flagged as inconsistent. 0.10 == 10%.
    static let pacingCVAlert: Double = 0.10

    /// When averaging per-session CV values for a block, only consider the N
    /// most recent sessions so a single bad day doesn't flag the athlete.
    static let recentSessionsForCV: Int = 5

    /// Minimum number of timed sessions for a block before a regression slope
    /// is meaningful.
    static let minPointsForRegression: Int = 3

    /// Minimum number of reps within a single block before CV is meaningful.
    static let minPointsForCV: Int = 2

    /// Rolling window for the development-coverage gap signal — how many days
    /// back to count DevelopmentNotes when deciding whether a focus area is
    /// covered. Matches a typical CKC macro-cycle.
    static let coverageWindowDays: Int = 60

    /// Caps how many of an athlete's most-recent `PerformanceRecord`s the needs-attention
    /// signals (`decliningBlockName`, `mostImprovedBlockName`, `inconsistentPacingBlock`) scan.
    /// Every signal only needs `recentSessionsForCV`/`minPointsForRegression`-sized windows per
    /// block anyway, so after a few seasons this keeps per-render cost bounded to a few hundred
    /// records instead of an athlete's entire multi-season history. Generous enough that no
    /// realistic single-season record count is ever truncated.
    static let maxRecordsForSignals: Int = 300
}

// MARK: - Math primitives

/// Least-squares slope of `ys` against evenly spaced x values (0, 1, 2, …).
/// Returns nil when fewer than 2 points or when the x-variance is zero
/// (impossible for the evenly-spaced case but guarded anyway).
func leastSquaresSlope(_ ys: [Double]) -> Double? {
    guard ys.count >= 2 else { return nil }
    let n = Double(ys.count)
    let meanX = (n - 1) / 2
    let meanY = ys.reduce(0, +) / n
    let num = ys.enumerated().reduce(0.0) { acc, pair in
        acc + (Double(pair.offset) - meanX) * (pair.element - meanY)
    }
    let den = (0..<ys.count).reduce(0.0) { acc, i in
        acc + (Double(i) - meanX) * (Double(i) - meanX)
    }
    return den == 0 ? nil : num / den
}

/// Coefficient of variation (stddev / mean) for the given samples.
/// Returns nil for fewer than 2 points or when the mean is zero or negative
/// (CV is undefined / meaningless there).
func coefficientOfVariation(_ values: [Double]) -> Double? {
    guard values.count >= 2 else { return nil }
    let mean = values.reduce(0, +) / Double(values.count)
    guard mean > 0 else { return nil }
    let variance = values.reduce(0.0) { acc, v in
        acc + (v - mean) * (v - mean)
    } / Double(values.count)
    return variance.squareRoot() / mean
}

// MARK: - Development coverage

/// One focus-area entry surfaced by `Athlete.developmentCoverage()`.
///
/// `noteCount` is how many DevelopmentNotes inside the rolling window carry a
/// tag whose name appears (case-insensitive substring) in the rating's factor.
/// A `noteCount` of zero is the "uncovered gap" the focus panel surfaces.
struct DevelopmentCoverage: Identifiable {
    let rating: TechnicalRating
    let noteCount: Int
    var id: UUID { rating.id }
    var isCovered: Bool { noteCount > 0 }
}

// MARK: - Athlete signals

extension Athlete {

    /// Caps a `performanceRecords` scan to the most recent `maxRecordsForSignals`, so the
    /// needs-attention signals below cost a bounded amount of work instead of scaling with an
    /// athlete's entire multi-season history. Below the cap this is a no-op (skips the sort
    /// entirely) — the common case for most of a season.
    fileprivate static func recentWindow(_ records: [PerformanceRecord]) -> [PerformanceRecord] {
        guard records.count > InsightThresholds.maxRecordsForSignals else { return records }
        return records
            .sorted {
                ($0.sessionBlock?.session?.scheduledDate ?? .distantPast)
                    > ($1.sessionBlock?.session?.scheduledDate ?? .distantPast)
            }
            .prefix(InsightThresholds.maxRecordsForSignals)
            .map { $0 }
    }

    /// Name of the most recently trained block whose timed results show a
    /// positive regression slope (the athlete is getting slower at it).
    var decliningBlockName: String? {
        regressedBlockName(slopeMatches: { $0 > InsightThresholds.decliningSlopeMs })
    }

    /// Name of the most recently trained block whose timed results show a
    /// clearly negative regression slope (the athlete is getting faster).
    var mostImprovedBlockName: String? {
        regressedBlockName(slopeMatches: { $0 < InsightThresholds.improvingSlopeMs })
    }

    /// Block whose recent same-block sessions show rep-to-rep variability
    /// above the CV alert threshold. Returns the worst offender + its CV%.
    var inconsistentPacingBlock: (name: String, cvPercent: Int)? {
        let valid = Self.recentWindow(performanceRecords ?? []).filter {
            $0.status == .complete && $0.recordedTimeMs != nil
        }
        // Each session-block (one block on one date) is one CV sample. Drop
        // records whose block was deleted (orphaned) explicitly, rather than
        // relying on a fresh `UUID()` per record to isolate them into singleton
        // groups that the `count >= 2` guard later discards.
        let withBlock = valid.filter { $0.sessionBlock != nil }
        let bySessionBlock = Dictionary(grouping: withBlock) { $0.sessionBlock!.id }

        struct BlockCV {
            let blockName: String
            let sessionDate: Date
            let cv: Double
        }

        var allCVs: [BlockCV] = []
        for (_, records) in bySessionBlock {
            let times = records.compactMap(\.recordedTimeMs).map(Double.init)
            guard let cv = coefficientOfVariation(times) else { continue }
            let blockName = records.first?.sessionBlock?.blockName ?? "Unknown"
            let sessionDate = records.first?.sessionBlock?.session?.scheduledDate
                ?? .distantPast
            allCVs.append(BlockCV(
                blockName: blockName,
                sessionDate: sessionDate,
                cv: cv
            ))
        }

        // Average CV across the N most recent sessions per block name.
        let byBlock = Dictionary(grouping: allCVs) { $0.blockName }
        let flagged: [(name: String, avgCV: Double)] = byBlock.compactMap { blockName, entries in
            let recent = entries
                .sorted { $0.sessionDate > $1.sessionDate }
                .prefix(InsightThresholds.recentSessionsForCV)
            guard recent.count >= InsightThresholds.minPointsForCV else { return nil }
            let avgCV = recent.map(\.cv).reduce(0, +) / Double(recent.count)
            guard avgCV > InsightThresholds.pacingCVAlert else { return nil }
            return (name: blockName, avgCV: avgCV)
        }

        guard let worst = flagged.max(by: { $0.avgCV < $1.avgCV }) else { return nil }
        return (name: worst.name, cvPercent: Int((worst.avgCV * 100).rounded()))
    }

    /// Number of KTC assessments if the score trend is going down (slope < 0).
    /// Returns nil when fewer than the minimum number of assessments exist
    /// or when the trend is flat / improving.
    var ktcDecliningCount: Int? {
        let sorted = (ktcAssessments ?? []).sorted { $0.date < $1.date }
        guard sorted.count >= InsightThresholds.minPointsForRegression else { return nil }
        guard let slope = leastSquaresSlope(sorted.map(\.averageScore)),
              slope < 0 else { return nil }
        return sorted.count
    }

    /// Shared helper: find the most recently trained block whose slope
    /// passes the supplied predicate. Used by both decliningBlockName and
    /// mostImprovedBlockName.
    fileprivate func regressedBlockName(slopeMatches: (Double) -> Bool) -> String? {
        let valid = Self.recentWindow(performanceRecords ?? []).filter {
            $0.status == .complete && $0.recordedTimeMs != nil
        }
        let grouped = Dictionary(grouping: valid) {
            $0.sessionBlock?.blockName ?? "Unknown"
        }

        let matched: [(name: String, mostRecent: Date)] = grouped.compactMap { name, records in
            guard records.count >= InsightThresholds.minPointsForRegression else { return nil }
            let sorted = records.sorted {
                ($0.sessionBlock?.session?.scheduledDate ?? .distantPast)
                    < ($1.sessionBlock?.session?.scheduledDate ?? .distantPast)
            }
            let times = sorted.compactMap(\.recordedTimeMs).map(Double.init)
            guard let slope = leastSquaresSlope(times),
                  slopeMatches(slope) else { return nil }
            return (name, sorted.last?.sessionBlock?.session?.scheduledDate ?? .distantPast)
        }
        return matched.max { $0.mostRecent < $1.mostRecent }?.name
    }

    /// Newest TechnicalAssessment by date, breaking ties with `createdAt`.
    /// Lifted out of `DevelopmentFocusPanel` so the panel and the coverage
    /// signal share one source of "latest" rather than each recomputing it.
    var latestTechnicalAssessment: TechnicalAssessment? {
        (technicalAssessments ?? []).max {
            $0.date == $1.date ? $0.createdAt < $1.createdAt : $0.date < $1.date
        }
    }

    /// For each focus area in the latest TechnicalAssessment (rating with
    /// score ≤ 2), how many DevelopmentNotes inside the rolling window carry
    /// a tag whose name appears (case-insensitive substring) in the rating's
    /// factor or category. (The predefined tags are category themes, so most
    /// matches come via the category.) A `noteCount` of zero is an uncovered gap — the coach flagged
    /// the area but hasn't logged any matching journal entries.
    ///
    /// Entries are returned in the same sort order `DevelopmentFocusPanel`
    /// uses for its Focus Areas list (by category).
    func developmentCoverage(
        windowDays: Int = InsightThresholds.coverageWindowDays,
        referenceDate: Date = .now,
        calendar: Calendar = .current
    ) -> [DevelopmentCoverage] {
        guard let assessment = latestTechnicalAssessment else { return [] }
        let cutoff = calendar.date(
            byAdding: .day,
            value: -windowDays,
            to: referenceDate
        ) ?? referenceDate
        let recentNotes = (developmentNotes ?? []).filter { $0.date >= cutoff }
        let focusAreas = (assessment.ratings ?? [])
            .filter { $0.score <= 2 }
            .sorted { $0.category < $1.category }
        return focusAreas.map { rating in
            let matching = recentNotes.filter { note in
                note.tags.contains { rating.matchesDevelopmentTag($0) }
            }
            return DevelopmentCoverage(rating: rating, noteCount: matching.count)
        }
    }
}

/// Development-coverage tag matching — the SINGLE source of truth shared by
/// `Athlete.developmentCoverage()` (counts covering notes) and
/// `DevelopmentFocusPanel`'s focus-row pre-tagging, so the two can't drift.
extension TechnicalRating {
    /// Text a journal tag is matched against: the rating's factor plus its
    /// category. The predefined tags are category themes, so most matches come
    /// via the category (e.g. "Position and posture in boat" matches via its
    /// "Balance Set-Up" category).
    var developmentTagHaystack: String { "\(factor) \(category)" }

    /// True when `tag` is non-empty and appears (case-insensitive) in the
    /// rating's factor or category.
    func matchesDevelopmentTag(_ tag: String) -> Bool {
        !tag.isEmpty && developmentTagHaystack.localizedCaseInsensitiveContains(tag)
    }
}
