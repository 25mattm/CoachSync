/// Displays fitness test history and benchmark comparisons for an athlete.
import SwiftUI
import SwiftData

/// Supported on-water test names for ordering and creation.
let fitnessTestTypes: [String] = [
    "2000m Time Trial",
    "100m Sprint",
    "250m Sprint",
    "500m Sprint",
    "1000m Sprint",
    "200m Sprint",
    "1500m Run"
]

/// CKC mandatory physical test battery with units.
let ckcPhysicalTestTypes: [(name: String, unit: String)] = [
    ("2km Erg Time Trial",       "seconds"),
    ("Bench Pull",               "reps"),
    ("Vertical Jump",            "cm"),
    ("20m Sprint",               "seconds"),
    ("Sit-ups (1 min)",          "reps"),
    ("Push-ups (max)",           "reps"),
    ("Back Extension (max)",     "reps"),
    ("Overhead Med Ball Throw",  "m"),
    ("Standing Long Jump",       "cm")
]

/// Quarterly CKC testing window months (Jan, Apr, Jul, Oct).
private let testingWindowMonths: [Int] = [1, 4, 7, 10]

/// Returns a human-readable label for the next upcoming CKC testing window.
func nextTestingWindowLabel(from date: Date = Date()) -> String {
    let calendar = Calendar.current
    let currentMonth = calendar.component(.month, from: date)
    let currentYear  = SeasonContext.currentYear(calendar: calendar, referenceDate: date)
    for month in testingWindowMonths where month >= currentMonth {
        let comps = DateComponents(year: currentYear, month: month)
        if let d = calendar.date(from: comps) {
            return d.formatted(.dateTime.month(.wide).year())
        }
    }
    let comps = DateComponents(year: currentYear + 1, month: testingWindowMonths[0])
    if let d = Calendar.current.date(from: comps) {
        return d.formatted(.dateTime.month(.wide).year())
    }
    return "January"
}

/// Returns the unit string for a CKC physical test, or "seconds" if not CKC.
func ckcUnit(for testType: String) -> String {
    ckcPhysicalTestTypes.first { $0.name == testType }?.unit ?? "seconds"
}

/// Returns true if this test type records a time value (lower = better).
func isTimeBased(_ testType: String) -> Bool {
    if fitnessTestTypes.contains(testType) { return true }
    return ckcUnit(for: testType) == "seconds"
}

/// Formats a fitness result for display, respecting its unit.
func displayResult(_ result: FitnessTestResult) -> String {
    switch result.unit {
    case "seconds": return result.formattedTime
    case "reps":    return "\(Int(result.result)) reps"
    case "cm":      return String(format: "%.0f cm", result.result)
    case "m":       return String(format: "%.2f m", result.result)
    default:        return String(format: "%.2f \(result.unit)", result.result)
    }
}

// MARK: - FitnessTestView

/// Lists fitness test results grouped by category and test type.
struct FitnessTestView: View {
    @Bindable var athlete: Athlete
    @State private var showingNewResult = false

    var onWaterGrouped: [(testType: String, results: [FitnessTestResult])] {
        makeGrouped(from: fitnessTestTypes)
    }

    var ckcGrouped: [(testType: String, results: [FitnessTestResult])] {
        makeGrouped(from: ckcPhysicalTestTypes.map(\.name))
    }

    private func makeGrouped(from orderedTypes: [String]) -> [(testType: String, results: [FitnessTestResult])] {
        let dict = Dictionary(grouping: athlete.fitnessTestResults ?? []) { $0.testType }
        return orderedTypes.compactMap { type in
            guard let results = dict[type], !results.isEmpty else { return nil }
            let sorted = results.sorted {
                $0.testDate != $1.testDate ? $0.testDate > $1.testDate : $0.createdAt > $1.createdAt
            }
            return (type, sorted)
        }
    }

    var hasResults: Bool { !onWaterGrouped.isEmpty || !ckcGrouped.isEmpty }

    var body: some View {
        List {
            Section {
                TestingWindowBanner()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            }

            if !hasResults {
                EmptyCard(message: "No fitness tests logged yet", systemImage: "figure.run")
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !onWaterGrouped.isEmpty {
                Section {
                    ForEach(onWaterGrouped, id: \.testType) { group in
                        testTypeRows(group: group)
                    }
                } header: {
                    Label("On-Water Performance", systemImage: "water.waves")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }

            if !ckcGrouped.isEmpty {
                Section {
                    ForEach(ckcGrouped, id: \.testType) { group in
                        testTypeRows(group: group)
                    }
                } header: {
                    Label("CKC Physical Tests", systemImage: "figure.strengthtraining.traditional")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .textCase(nil)
                }
            }
        }
#if os(iOS)
        .listStyle(.insetGrouped)
#else
        .listStyle(.inset)
#endif
        .navigationTitle("Fitness Tests")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button { showingNewResult = true } label: {
                    Label("Log Test", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingNewResult) {
            NewFitnessTestResultSheet(athlete: athlete)
#if os(macOS)
                .frame(minWidth: 520, minHeight: 680)
#endif
        }
    }

    @ViewBuilder
    private func testTypeRows(group: (testType: String, results: [FitnessTestResult])) -> some View {
        let isCKC = ckcPhysicalTestTypes.contains(where: { $0.name == group.testType })
        let timeBased = isTimeBased(group.testType)

        Text(group.testType)
            .font(.footnote)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .padding(.top, 4)

        ForEach(group.results) { result in
            FitnessResultRow(
                result: result,
                isPersonalBest: isPersonalBest(result, higherIsBetter: !timeBased)
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
        }

        if isCKC {
            CKCTrendFooter(results: group.results, isTimeBased: timeBased)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
        } else {
            FitnessBenchmarkFooter(
                athlete: athlete,
                testType: group.testType,
                bestResult: bestResult(for: group.testType, higherIsBetter: false)
            )
            .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
        }
    }

    private func bestResult(for testType: String, higherIsBetter: Bool) -> FitnessTestResult? {
        let results = (athlete.fitnessTestResults ?? []).filter { $0.testType == testType }
        return higherIsBetter
            ? results.max(by: { $0.result < $1.result })
            : results.min(by: { $0.result < $1.result })
    }

    private func isPersonalBest(_ result: FitnessTestResult, higherIsBetter: Bool) -> Bool {
        guard let best = bestResult(for: result.testType, higherIsBetter: higherIsBetter) else { return false }
        return best.id == result.id
    }
}

// MARK: - TestingWindowBanner

private struct TestingWindowBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .foregroundStyle(Color.accentColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next CKC Testing Window")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(nextTestingWindowLabel())
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            Spacer()
            Text("Oct · Jan · Apr · Jul")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - FitnessResultRow

/// Displays a single fitness test result, optionally marked as a personal best.
struct FitnessResultRow: View {
    let result: FitnessTestResult
    let isPersonalBest: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(result.testDate.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let notes = result.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if isPersonalBest {
                    Text("PB")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                Text(displayResult(result))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - CKCTrendFooter

/// Shows improving/declining/stable trend for CKC physical tests (no external benchmark).
struct CKCTrendFooter: View {
    let results: [FitnessTestResult]
    let isTimeBased: Bool

    private var trendInfo: (label: String, color: Color)? {
        guard results.count >= 2 else { return nil }
        let delta = results[0].result - results[1].result
        let unit = results[0].unit
        let threshold: Double = {
            switch unit {
            case "seconds": return 0.5
            case "cm":      return 2.0
            case "m":       return 0.1
            default:        return 1.0  // reps and unknown units
            }
        }()
        if isTimeBased {
            if delta < -threshold { return ("↑ Improving", .green) }
            if delta >  threshold { return ("↓ Declining", .orange) }
        } else {
            if delta >  threshold { return ("↑ Improving", .green) }
            if delta < -threshold { return ("↓ Declining", .orange) }
        }
        return ("— Stable", .secondary)
    }

    var body: some View {
        HStack {
            Text("Trend")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let info = trendInfo {
                Text(info.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(info.color)
            } else {
                Text("Log 2+ results to see trend")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - FitnessBenchmarkFooter

/// Shows the best result against the LTAD benchmark for the selected test.
struct FitnessBenchmarkFooter: View {
    let athlete: Athlete
    let testType: String
    let bestResult: FitnessTestResult?

    var benchmarkSeconds: Double? {
        ltadBenchmarkSeconds(for: athlete, testType: testType)
    }

    var percentOfBenchmark: Double? {
        guard let best = bestResult?.result, let benchmark = benchmarkSeconds else { return nil }
        guard benchmark > 0 else { return nil }
        return (best / benchmark) * 100
    }

    var awayFromBenchmarkPercent: Double? {
        guard let percent = percentOfBenchmark else { return nil }
        return max(0, percent - 100)
    }

    var statusColor: Color {
        guard let away = awayFromBenchmarkPercent else { return .secondary }
        if away <= 10 { return .green }
        if away <= 25 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let benchmark = benchmarkSeconds {
                HStack {
                    Text("LTAD Benchmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatSecondsForDisplay(benchmark))
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                if let percent = percentOfBenchmark {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Best vs Benchmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f%%", percent))
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(statusColor)
                        }

                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.gray.opacity(0.18))
                                    .frame(height: 8)

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(statusColor)
                                    .frame(width: geo.size.width * progressFraction, height: 8)
                            }
                        }
                        .frame(height: 8)
                    }
                } else {
                    Text("Log a result to compare against the benchmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(athlete.gender == nil
                     ? "Set athlete gender to see LTAD benchmark."
                     : "No LTAD benchmark available for this test type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    var progressFraction: CGFloat {
        guard let percent = percentOfBenchmark else { return 0 }
        if percent <= 100 { return 1 }
        let over = min(percent - 100, 50)
        return CGFloat(max(0, 1 - (over / 50)))
    }
}

// MARK: - NewFitnessTestResultSheet

/// Collects and validates a new fitness test result, supporting both time and numeric inputs.
struct NewFitnessTestResultSheet: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory = "On-Water"
    @State private var selectedTestType = fitnessTestTypes.first ?? "2000m Time Trial"
    @State private var timeEntry = ""
    @State private var numericEntry = ""
    @State private var testDate = Date()
    @State private var notes = ""
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    private var currentTestTypeNames: [String] {
        selectedCategory == "On-Water"
            ? fitnessTestTypes
            : ckcPhysicalTestTypes.map(\.name)
    }

    private var currentUnit: String {
        selectedCategory == "On-Water" ? "seconds" : ckcUnit(for: selectedTestType)
    }

    private var testIsTimeBased: Bool {
        isTimeBased(selectedTestType)
    }

    var parsedMs: Int? { parseTimeToMs(timeEntry) }

    var parsedSeconds: Double? {
        guard let ms = parsedMs else { return nil }
        return Double(ms) / 1000.0
    }

    var parsedNumeric: Double? {
        Double(numericEntry.trimmingCharacters(in: .whitespaces))
    }

    var isValid: Bool {
        testIsTimeBased ? parsedSeconds != nil : parsedNumeric != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("On-Water").tag("On-Water")
                        Text("CKC Physical").tag("CKC Physical")
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedCategory) {
                        selectedTestType = currentTestTypeNames.first ?? ""
                        timeEntry = ""
                        numericEntry = ""
                    }
                }

                Section("Test Details") {
                    Picker("Test Type", selection: $selectedTestType) {
                        ForEach(currentTestTypeNames, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                    DatePicker("Date", selection: $testDate, in: ...Date.now, displayedComponents: .date)
                }

                if testIsTimeBased {
                    Section("Result Time") {
                        TextField("M:SS.ms", text: $timeEntry)
#if os(iOS)
                            .keyboardType(.numbersAndPunctuation)
#endif
                        if !timeEntry.isEmpty && parsedMs == nil {
                            Text("Enter a valid time (e.g. 8:52.30 or 34.12)")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                } else {
                    Section("Result (\(currentUnit))") {
                        TextField(currentUnit == "reps" ? "e.g. 12" : "e.g. 65.5", text: $numericEntry)
#if os(iOS)
                            .keyboardType(.decimalPad)
#endif
                        if !numericEntry.isEmpty && parsedNumeric == nil {
                            Text("Enter a valid number")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("Notes (Optional)") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Fitness Test")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
            .alert("Couldn't Save Fitness Test", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    private func save() {
        let resultValue: Double
        let unit: String

        if testIsTimeBased {
            guard let seconds = parsedSeconds else { return }
            resultValue = seconds
            unit = "seconds"
        } else {
            guard let numeric = parsedNumeric else { return }
            resultValue = numeric
            unit = currentUnit
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = FitnessTestResult(
            testType: selectedTestType,
            result: resultValue,
            unit: unit,
            testDate: testDate,
            notes: trimmedNotes.isEmpty ? nil : trimmedNotes,
            athlete: athlete
        )

        modelContext.insert(result)
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }
}

// MARK: - LTAD Benchmark Lookup

/// Returns the benchmark time, in seconds, for a supported test when enough athlete data exists.
func ltadBenchmarkSeconds(for athlete: Athlete, testType: String) -> Double? {
    guard let gender = athlete.gender else { return nil }

    let age = SeasonContext.athleteAge(for: athlete.dateOfBirth)

    switch gender {
    case .female:
        switch testType {
        case "2000m Time Trial":
            switch age {
            case 11...12: return 15 * 60 + 30
            case 13: return 14 * 60
            case 14: return 12 * 60 + 30
            case 15: return 11 * 60 + 45
            case 16: return 11 * 60
            case 17: return 10 * 60 + 50
            case 18: return 10 * 60 + 15
            default: return nil
            }
        case "100m Sprint":
            switch age {
            case 11...12: return 36
            case 13: return 34
            case 14: return 31.5
            case 15: return 28.5
            case 16: return 27.5
            case 17: return 26.5
            case 18: return 25.5
            default: return nil
            }
        case "1500m Run":
            if age >= 16 { return 6 * 60 }
            return nil
        default:
            return nil
        }
    case .male:
        switch testType {
        case "2000m Time Trial":
            switch age {
            case 11...12: return 12 * 60
            case 13: return 11 * 60
            case 14: return 10 * 60 + 10
            case 15: return 9 * 60 + 40
            case 16: return 9 * 60
            case 17: return 8 * 60 + 30
            case 18: return 8 * 60 + 5
            default: return nil
            }
        case "100m Sprint":
            switch age {
            case 11...12: return 30
            case 13: return 28
            case 14: return 26
            case 15: return 23
            case 16: return 21
            case 17: return 20
            case 18: return 19.5
            default: return nil
            }
        case "1500m Run":
            switch age {
            case 16: return 5 * 60
            case 17: return 4 * 60 + 50
            case 18: return 4 * 60 + 40
            default: return nil
            }
        default:
            return nil
        }
    }
}
