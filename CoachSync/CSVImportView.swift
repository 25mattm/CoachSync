/// Imports athletes from CSV and guides the user through preview and persistence phases.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Multi-step CSV import flow for athlete creation.
struct CSVImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var showingFilePicker = false
    @State private var importedAthletes: [CSVAthlete] = []
    @State private var importErrors: [String] = []
    @State private var phase: ImportPhase = .ready
    @State private var duplicateCount = 0
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    /// UI phases for the import flow.
    enum ImportPhase {
        case ready
        case preview
        case importing
        case done
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .ready:
                    ReadyPhaseView(onPickFile: { showingFilePicker = true })

                case .preview:
                    PreviewPhaseView(
                        athletes: importedAthletes,
                        errors: importErrors,
                        duplicateCount: duplicateCount,
                        onImport: { performImport() },
                        onCancel: { resetToReady() }
                    )

                case .importing:
                    VStack(spacing: 20) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Importing athletes...")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .done:
                    DonePhaseView(
                        count: importedAthletes.count,
                        errors: importErrors,
                        onDismiss: { dismiss() }
                    )
                }
            }
            .navigationTitle("Import Athletes")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText, .plainText, .data],
                allowsMultipleSelection: false
            ) { result in
                DispatchQueue.main.async {
                    handleFileImport(result)
                }
            }
            .alert("Save Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    // MARK: - File Handling

    /// Handles the file picker result and forwards the selected file to parsing.
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importErrors = ["Failed to open file: \(error.localizedDescription)"]
            phase = .preview
        case .success(let urls):
            guard let url = urls.first else {
                importErrors = ["No file selected."]
                phase = .preview
                return
            }
            parseCSV(url: url)
        }
    }

    /// Reads a CSV file with security-scoped access and prepares preview data.
    private func parseCSV(url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        let content: String
        do {
            content = CSVParser.decode(try Data(contentsOf: url))
        } catch {
            importErrors = ["Could not read file. Make sure it is saved as a plain CSV: \(error.localizedDescription)"]
            phase = .preview
            return
        }
        guard !content.isEmpty else {
            importErrors = ["File is empty."]
            phase = .preview
            return
        }
        let result = CSVParser.parse(content)
        importedAthletes = result.athletes
        importErrors = result.errors
        duplicateCount = countDuplicates(result.athletes)
        phase = .preview
    }

    /// Counts rows that would be skipped because a matching full name already exists.
    private func countDuplicates(_ athletes: [CSVAthlete]) -> Int {
        let descriptor = FetchDescriptor<Athlete>()
        let existing: [Athlete]
        do {
            existing = try modelContext.fetch(descriptor)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
            existing = []
        }
        let existingNames = Set(existing.map {
            "\($0.firstName.lowercased()) \($0.lastName.lowercased())"
        })
        // Count duplicates against the store AND earlier rows in the same file,
        // mirroring exactly what performImport will skip.
        var seen = existingNames
        var duplicates = 0
        for athlete in athletes {
            let key = "\(athlete.firstName.lowercased()) \(athlete.lastName.lowercased())"
            if !seen.insert(key).inserted { duplicates += 1 }
        }
        return duplicates
    }

    /// Inserts non-duplicate athletes and commits the import to SwiftData.
    private func performImport() {
        phase = .importing

        let descriptor = FetchDescriptor<Athlete>()
        let existing: [Athlete]
        do {
            existing = try modelContext.fetch(descriptor)
        } catch {
            saveErrorMessage = error.localizedDescription
            showSaveError = true
            existing = []
        }
        var existingNames = Set(existing.map {
            "\($0.firstName.lowercased()) \($0.lastName.lowercased())"
        })

        var imported = 0
        for csvAthlete in importedAthletes {
            let key = "\(csvAthlete.firstName.lowercased()) \(csvAthlete.lastName.lowercased())"
            // Inserting the key as we go also skips duplicate rows within the
            // same file, not just rows matching already-stored athletes.
            guard existingNames.insert(key).inserted else { continue }

            let athlete = Athlete(
                firstName: csvAthlete.firstName,
                lastName: csvAthlete.lastName,
                dateOfBirth: csvAthlete.dateOfBirth,
                gender: csvAthlete.gender,
                guardianName: csvAthlete.guardianName,
                guardianPhone: csvAthlete.guardianPhone,
                guardianEmail: csvAthlete.guardianEmail
            )
            modelContext.insert(athlete)
            imported += 1
        }

        do {
            try SyncStore.save(modelContext)
            importedAthletes = Array(importedAthletes.prefix(imported))
            phase = .done
        } catch {
            // Discard the inserted-but-unsaved athletes so a failed import
            // isn't silently committed by a later save elsewhere in the app.
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveError = true
            phase = .preview
        }
    }

    private func resetToReady() {
        importedAthletes = []
        importErrors = []
        duplicateCount = 0
        phase = .ready
    }
}

// MARK: - Ready Phase (Fixed Layout)

/// Introductory state that explains the expected CSV layout.
struct ReadyPhaseView: View {
    let onPickFile: () -> Void
    /// Text on an accent-filled button: the dark-mode accent is a pale pink, where white text
    /// falls to ~2.3:1 contrast, so it switches to black there (~9:1).
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.below.ecg")
                        .font(.system(.largeTitle))
                        .imageScale(.large)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 20)

                    Text("Import from CSV")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text("Your CSV file must have these columns in order:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                // Reference Card
                VStack(alignment: .leading, spacing: 0) {
                    FormatRow(column: "FirstName", required: true, example: "Alex")
                    Divider()
                    FormatRow(column: "LastName", required: true, example: "Smith")
                    Divider()
                    FormatRow(column: "DateOfBirth", required: true, example: "09/15/2002")
                    Divider()
                    FormatRow(column: "GuardianName", required: false, example: "John Neal")
                    Divider()
                    FormatRow(column: "GuardianPhone", required: false, example: "555-555-1234")
                    Divider()
                    FormatRow(column: "GuardianEmail", required: false, example: "john@email.com")
                    Divider()
                    FormatRow(column: "Gender", required: false, example: "Male / Female")
                }
                .padding(.vertical, 8)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 16)

                // Footer note
                Text("Date format: MM/DD/YYYY. First row is the header.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)

                // Action Button
                Button(action: onPickFile) {
                    Label("Choose CSV File", systemImage: "folder")
                        .font(.headline)
                        .foregroundStyle(colorScheme == .dark ? .black : .white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
#if os(iOS)
        .background(Color(.systemGroupedBackground))
#else
        .background(Color.gray.opacity(0.05))
#endif
    }
}

/// Displays one expected CSV column and a sample value.
struct FormatRow: View {
    let column: String
    let required: Bool
    let example: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(column)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("e.g. \(example)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 12)

            if required {
                Text("Required")
                    .font(.caption2)
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            } else {
                Text("Optional")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Preview Phase

/// Preview state that surfaces parse errors before import.
struct PreviewPhaseView: View {
    let athletes: [CSVAthlete]
    let errors: [String]
    let duplicateCount: Int
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("\(athletes.count)")
                            .font(.title2).fontWeight(.bold).foregroundStyle(.green)
                        Text("Ready").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 4) {
                        Text("\(duplicateCount)")
                            .font(.title2).fontWeight(.bold).foregroundStyle(.orange)
                        Text("Duplicates").font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 4) {
                        Text("\(errors.count)")
                            .font(.title2).fontWeight(.bold).foregroundStyle(.red)
                        Text("Errors").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } footer: {
                Text("Duplicates (same first + last name) will be skipped automatically.")
            }

            if !errors.isEmpty {
                Section("Parse Errors") {
                    ForEach(errors, id: \.self) { error in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                                .padding(.top, 2)
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            if !athletes.isEmpty {
                Section("Athletes to Import") {
                    ForEach(athletes) { athlete in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(athlete.fullName)
                                    .font(.subheadline).fontWeight(.medium)
                                Spacer()
                                CategoryPill(category: athlete.ageCategory)
                            }
                            Text(athlete.dateOfBirth.formatted(.dateTime.month(.abbreviated).day().year()))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let guardian = athlete.guardianName {
                                Text(guardian)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Button(action: onImport) {
                    Label("Import \(athletes.count) Athletes", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(athletes.isEmpty ? Color.gray : Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(athletes.isEmpty)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

                Button(action: onCancel) {
                    Text("Choose Different File")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }
}

// MARK: - Done Phase

/// Completion state displayed after a successful import.
struct DonePhaseView: View {
    let count: Int
    let errors: [String]
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(.largeTitle))
                .imageScale(.large)
                .foregroundStyle(.green)

            VStack(spacing: 8) {
                Text("Import Complete")
                    .font(.title2).fontWeight(.bold)
                Text("\(count) athlete\(count == 1 ? "" : "s") added successfully.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !errors.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Skipped rows:")
                        .font(.caption).fontWeight(.semibold)
                    ForEach(errors, id: \.self) { error in
                        Text("• \(error)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(Color.gray.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }

            Button(action: onDismiss) {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal)

            Spacer()
        }
    }
}

// MARK: - CSV Parser

/// Parsed athlete rows and any row-level validation issues.
struct CSVParseResult {
    var athletes: [CSVAthlete] = []
    var errors: [String] = []
}

/// Lightweight CSV parser tailored to the supported athlete import format.
struct CSVParser {
    /// Decodes a CSV file's bytes. UTF-8 first; UTF-16 only when a byte-order mark says so; then the
    /// encodings Excel's plain "CSV (Comma delimited)" export actually uses — Windows-1252, then
    /// MacRoman, which maps every byte and so always succeeds. Without these, a roster saved from
    /// Excel with an accented name ("Léger") fails UTF-8 and would be misread as UTF-16.
    static func decode(_ data: Data) -> String {
        if let text = String(data: data, encoding: .utf8) { return text }
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }
        return String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .macOSRoman)
            ?? ""
    }

    /// Parses CSV text into preview models, skipping invalid rows and collecting errors.
    static func parse(_ content: String) -> CSVParseResult {
        var result = CSVParseResult()

        // Blank records are skipped, but each keeps its 1-based position in the file so error
        // messages name the row the coach sees in their spreadsheet.
        let lines = splitRecords(content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n"))
            .enumerated()
            .map { (rowNumber: $0.offset + 1, text: $0.element) }
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }

        guard lines.count > 1 else {
            result.errors.append("File is empty or has only a header row.")
            return result
        }

        for (rowNumber, line) in lines.dropFirst() {
            let fields = parseCSVLine(line)

            guard fields.count >= 3 else {
                result.errors.append("Row \(rowNumber): Not enough columns (need at least 3).")
                continue
            }

            let firstName = fields[0].trimmingCharacters(in: .whitespaces)
            let lastName  = fields[1].trimmingCharacters(in: .whitespaces)
            let dobString = fields[2].trimmingCharacters(in: .whitespaces)

            guard !firstName.isEmpty else {
                result.errors.append("Row \(rowNumber): First name is empty.")
                continue
            }
            guard !lastName.isEmpty else {
                result.errors.append("Row \(rowNumber): Last name is empty.")
                continue
            }
            guard let dob = parseDOB(dobString) else {
                result.errors.append("Row \(rowNumber): Invalid date '\(dobString)' — use MM/DD/YYYY.")
                continue
            }
            guard dob <= Date.now else {
                result.errors.append("Row \(rowNumber): Date of birth '\(dobString)' is in the future.")
                continue
            }
            // "MM/dd/yyyy" happily reads a two-digit year ("3/14/16", Excel's short-date export) as
            // the year 0016, which passes the future check and makes the athlete a ~2000-year-old
            // "Senior". Require a real four-digit year instead.
            guard SeasonContext.year(of: dob) >= 1900 else {
                result.errors.append("Row \(rowNumber): Date '\(dobString)' needs a 4-digit year — use MM/DD/YYYY.")
                continue
            }

            let guardianName  = fields.count > 3 ? fields[3].trimmingCharacters(in: .whitespaces) : nil
            let guardianPhone = fields.count > 4 ? fields[4].trimmingCharacters(in: .whitespaces) : nil
            var guardianEmail = fields.count > 5 ? fields[5].trimmingCharacters(in: .whitespacesAndNewlines) : nil
            let genderString  = fields.count > 6 ? fields[6].trimmingCharacters(in: .whitespaces) : nil
            let gender: Gender? = genderString.flatMap { parseGender($0) }
            // Import the athlete but drop an address the backend would reject — otherwise the athlete
            // (and everything later recorded for them) could never sync.
            if let email = guardianEmail, !email.isEmpty, !email.isPlausibleEmail {
                result.errors.append("Row \(rowNumber): Guardian email '\(email)' isn't valid — imported without it.")
                guardianEmail = nil
            }

            result.athletes.append(CSVAthlete(
                firstName: firstName,
                lastName: lastName,
                dateOfBirth: dob,
                guardianName: guardianName.flatMap { $0.isEmpty ? nil : $0 },
                guardianPhone: guardianPhone.flatMap { $0.isEmpty ? nil : $0 },
                guardianEmail: guardianEmail.flatMap { $0.isEmpty ? nil : $0 },
                gender: gender
            ))
        }

        return result
    }

    /// Splits CSV text into records on newlines that are outside quotes, so a quoted field containing
    /// a line break (a multi-line note or address from a spreadsheet) stays one record.
    private static func splitRecords(_ text: String) -> [String] {
        var records: [String] = []
        var current = ""
        var inQuotes = false
        for char in text {
            if char == "\"" {
                inQuotes.toggle()   // an escaped "" toggles twice, leaving the state unchanged
            }
            if char == "\n" && !inQuotes {
                records.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        records.append(current)
        return records
    }

    /// Splits a CSV line, preserving commas inside quoted fields and treating a
    /// doubled quote (`""`) inside a quoted field as one literal quote (RFC 4180).
    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        let chars = Array(line)
        var index = 0
        while index < chars.count {
            let char = chars[index]
            if char == "\"" {
                if inQuotes, index + 1 < chars.count, chars[index + 1] == "\"" {
                    current.append("\"")   // escaped quote — consume both
                    index += 1
                } else {
                    inQuotes.toggle()
                }
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index += 1
        }
        fields.append(current)
        return fields
    }

    /// Cached `DateFormatter` for DOB parsing. Built once per process rather
    /// than per row — `DateFormatter()` is heavy and CSV imports may hit it
    /// hundreds of times in a single call.
    private static let dobFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/dd/yyyy"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func parseDOB(_ string: String) -> Date? {
        dobFormatter.date(from: string)
    }

    private static func parseGender(_ string: String) -> Gender? {
        let lower = string.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "m", "male", "boy": return .male
        case "f", "female", "girl": return .female
        default: return nil
        }
    }
}

// MARK: - CSV Athlete (preview model)

/// Preview-only athlete model used before committing imported rows.
struct CSVAthlete: Identifiable {
    let id = UUID()
    let firstName: String
    let lastName: String
    let dateOfBirth: Date
    let guardianName: String?
    let guardianPhone: String?
    let guardianEmail: String?
    let gender: Gender?

    var fullName: String { "\(firstName) \(lastName)" }

    var ageCategory: String {
        SeasonContext.ageCategory(for: dateOfBirth)
    }
}
