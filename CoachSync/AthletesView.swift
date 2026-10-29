/// Displays the athlete roster, grouped by age category, with creation and deletion actions.

import SwiftUI
import SwiftData

/// How the roster list is grouped and ordered.
private enum AthleteSortOrder: String, CaseIterable {
    case age  = "Age"
    case name = "Name"
    case sex  = "Sex"
}

/// Shows active athletes with search and age-category grouping.
struct AthletesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Athlete> { $0.isActive },
           sort: \Athlete.lastName) private var athletes: [Athlete]

    @State private var showingAddAthlete = false
    @State private var searchText = ""
    @State private var sortOrder: AthleteSortOrder = .age
    @State private var deletionBlockedAthlete: Athlete?

    private var filteredAthletes: [Athlete] {
        if searchText.isEmpty { return athletes }
        return athletes.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }

    /// Groups the filtered roster for display: by age category (in `SeasonContext`
    /// display order), as a single "All Athletes" group when sorting by name, or
    /// split by sex. Empty groups are dropped.
    private var groupedAthletes: [(category: String, athletes: [Athlete])] {
        switch sortOrder {
        case .age:
            let order = SeasonContext.ageCategoryDisplayOrder
            let grouped = Dictionary(grouping: filteredAthletes) { $0.ageCategory }
            return order.compactMap { cat in
                guard let group = grouped[cat], !group.isEmpty else { return nil }
                return (category: cat, athletes: group)
            }
        case .name:
            return filteredAthletes.isEmpty ? [] : [("All Athletes", filteredAthletes)]
        case .sex:
            let male    = filteredAthletes.filter { $0.gender == .male }
            let female  = filteredAthletes.filter { $0.gender == .female }
            let unknown = filteredAthletes.filter { $0.gender == nil }
            return [("Male", male), ("Female", female), ("Unspecified", unknown)]
                .filter { !$0.1.isEmpty }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if athletes.isEmpty {
                    EmptyCard(message: "No athletes yet — tap + to add your first",
                              systemImage: "person.badge.plus")
                        .padding()
                } else {
                    List {
                        ForEach(groupedAthletes, id: \.category) { group in
                            Section {
                                ForEach(group.athletes) { athlete in
                                    NavigationLink(
                                        destination: AthleteProfileView(athlete: athlete)
                                    ) {
                                        AthleteRow(athlete: athlete)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        athleteSwipeActions(for: athlete)
                                    }
                                    .contextMenu {
                                        athleteSwipeActions(for: athlete)
                                    }
                                }
                            } header: {
                                CategoryHeader(category: group.category,
                                               count: group.athletes.count)
                            }
                        }
                    }
                    #if os(iOS)
                    .listStyle(.insetGrouped)
                    #else
                    .listStyle(.inset)
                    #endif
                    .accessibilityIdentifier("athletes.list")
                }
            }
            .navigationTitle("Athletes")
            .searchable(text: $searchText, prompt: "Search athletes")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(AthleteSortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrder = order
                            } label: {
                                if sortOrder == order {
                                    Label(order.rawValue, systemImage: "checkmark")
                                } else {
                                    Text(order.rawValue)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort athletes")
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingAddAthlete = true
                    } label: {
                        Image(systemName: "plus").fontWeight(.semibold)
                    }
                    .accessibilityLabel("Add athlete")
                    .accessibilityIdentifier("athletes.addButton")
                }
            }
            .sheet(isPresented: $showingAddAthlete) {
                AddAthleteSheet()
#if os(macOS)
                .frame(minWidth: 480, minHeight: 560)
#endif
            }
            .alert(item: $deletionBlockedAthlete) { athlete in
                Alert(
                    title: Text("Cannot Delete \(athlete.fullName)"),
                    message: Text("This athlete has practice history. Mark them as inactive to remove them from future sessions and rosters."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    /// Row delete affordance that honors the practice-history guard: athletes with
    /// recorded history get a non-destructive "Can't Delete" button (which explains
    /// deactivation) instead of a real delete. Shared by `.swipeActions` and
    /// `.contextMenu` so the actions are reachable on both iOS and macOS.
    @ViewBuilder
    private func athleteSwipeActions(for athlete: Athlete) -> some View {
        if athlete.hasPracticeHistory {
            Button {
                deletionBlockedAthlete = athlete
            } label: {
                Label("Can't Delete", systemImage: "exclamationmark.circle")
            }
            .tint(.gray)
        } else {
            Button(role: .destructive) {
                modelContext.deleteAthleteCascade(athlete)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

// MARK: - Athlete Row

/// Compact athlete summary used in lists and team rosters.
struct AthleteRow: View {
    let athlete: Athlete
    /// Grows with Dynamic Type — a fixed 44pt circle truncated the scaled initials to "…".
    @ScaledMetric(relativeTo: .subheadline) private var avatarSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Color.ageCategory(athlete.ageCategory).opacity(0.15))
                .frame(width: avatarSize, height: avatarSize)
                .overlay(
                    Text(athlete.firstName.prefix(1) + athlete.lastName.prefix(1))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(Color.ageCategory(athlete.ageCategory))
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(athlete.fullName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    CategoryPill(category: athlete.ageCategory)

                    if let gender = athlete.gender {
                        Text(gender == .male ? "M" : "F")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(gender == .male ? "Male" : "Female")
                    }

                    let activeTeams = (athlete.memberships ?? []).filter { $0.leftDate == nil }
                    if !activeTeams.isEmpty {
                        Text("\(activeTeams.count) team\(activeTeams.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Category Header

/// Section header for an age-category group.
struct CategoryHeader: View {
    let category: String
    let count: Int

    var body: some View {
        HStack {
            Text(category)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count) athlete\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Add Athlete Sheet

/// Collects the minimum information required to create a new athlete record.
struct AddAthleteSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var dateOfBirth = SeasonContext.defaultNewAthleteDateOfBirth()
    @State private var gender: Gender? = nil
    @State private var guardianName = ""
    @State private var guardianPhone = ""
    @State private var guardianEmail = ""
    @State private var showSaveError = false
    @State private var saveErrorMessage = ""

    private var previewCategory: String {
        SeasonContext.ageCategory(for: dateOfBirth)
    }

    private var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        emailIsValid
    }

    private var trimmedEmail: String { guardianEmail.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Blank is fine; anything else must pass the backend's email check or the athlete never syncs.
    private var emailIsValid: Bool { trimmedEmail.isEmpty || trimmedEmail.isPlausibleEmail }

    var body: some View {
        NavigationStack {
            Form {
                Section("Athlete Info") {
                    TextField("First Name", text: $firstName)
                        .accessibilityIdentifier("athlete.firstNameField")
                    TextField("Last Name", text: $lastName)
                        .accessibilityIdentifier("athlete.lastNameField")
                    DatePicker("Date of Birth",
                               selection: $dateOfBirth,
                               in: ...Date.now,
                               displayedComponents: .date)
                    Picker("Gender", selection: $gender) {
                        Text("Not Set").tag(nil as Gender?)
                        ForEach(Gender.allCases, id: \.self) { g in
                            Text(g.rawValue).tag(g as Gender?)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Age Category")
                        Spacer()
                        CategoryPill(category: previewCategory)
                    }
                } footer: {
                    Text("Auto-calculated from date of birth. Updates each season.")
                }

                Section {
                    TextField("Guardian Name", text: $guardianName)
                    #if os(iOS)
                    TextField("Phone", text: $guardianPhone)
                        .keyboardType(.phonePad)
                    TextField("Email", text: $guardianEmail)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    #else
                    TextField("Phone", text: $guardianPhone)
                    TextField("Email", text: $guardianEmail)
                        .autocorrectionDisabled()
                    #endif
                } header: {
                    Text("Guardian (Optional)")
                } footer: {
                    if !emailIsValid {
                        Text("Enter a valid email address, or leave it blank.")
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Athlete")
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
                        .accessibilityIdentifier("athlete.saveButton")
                }
            }
            .alert("Save Error", isPresented: $showSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    /// Inserts a new athlete into SwiftData and dismisses on success.
    private func save() {
        let athlete = Athlete(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: lastName.trimmingCharacters(in: .whitespaces),
            dateOfBirth: dateOfBirth,
            gender: gender,
            guardianName: guardianName.isEmpty ? nil : guardianName,
            guardianPhone: guardianPhone.isEmpty ? nil : guardianPhone,
            guardianEmail: trimmedEmail.isEmpty ? nil : trimmedEmail
        )
        modelContext.insert(athlete)
        // Commit through the sync chokepoint, not a bare autosave: this enqueues the outbox entry so
        // the athlete pushes to the backend. Without it the record persists locally but never syncs,
        // and the pull's snapshot-diff then deletes it as "absent from the server."
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            // Discard the unsaved insert so tapping Save again doesn't add a duplicate athlete.
            modelContext.rollback()
            saveErrorMessage = error.localizedDescription
            showSaveError = true
        }
    }
}
