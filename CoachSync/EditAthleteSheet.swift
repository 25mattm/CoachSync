/// Edits the persisted fields for an existing athlete.
import SwiftUI
import SwiftData

/// Modal form for updating athlete profile details.
struct EditAthleteSheet: View {
    @Bindable var athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var dateOfBirth: Date
    @State private var gender: Gender?
    @State private var guardianName: String
    @State private var guardianPhone: String
    @State private var guardianEmail: String
    @State private var developmentStage: DevelopmentStage
    @State private var isActive: Bool
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    /// Seeds local form state from the bound athlete so edits can be cancelled safely.
    init(athlete: Athlete) {
        self.athlete = athlete
        _firstName = State(initialValue: athlete.firstName)
        _lastName = State(initialValue: athlete.lastName)
        _dateOfBirth = State(initialValue: athlete.dateOfBirth)
        _gender = State(initialValue: athlete.gender)
        _guardianName = State(initialValue: athlete.guardianName ?? "")
        _guardianPhone = State(initialValue: athlete.guardianPhone ?? "")
        _guardianEmail = State(initialValue: athlete.guardianEmail ?? "")
        _developmentStage = State(initialValue: athlete.developmentStage)
        _isActive = State(initialValue: athlete.isActive)
    }

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
                    TextField("Last Name", text: $lastName)
                    DatePicker("Date of Birth",
                               selection: $dateOfBirth,
                               in: ...Date.now,
                               displayedComponents: .date)
                    Picker("Gender", selection: $gender) {
                        Text("Not Set").tag(nil as Gender?)
                        ForEach(Gender.allCases, id: \.self) { value in
                            Text(value.rawValue).tag(value as Gender?)
                        }
                    }
                    Picker("Development Stage", selection: $developmentStage) {
                        ForEach(DevelopmentStage.allCases, id: \.self) { stage in
                            Text(stage.rawValue).tag(stage)
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
                            .foregroundStyle(Color.readableRed)
                    }
                }

                Section("Danger Zone") {
                    Toggle("Athlete is active", isOn: $isActive)
                    Text("Inactive athletes are hidden from all rosters, but all historical data is preserved.")
                        .font(.caption)
                        .foregroundStyle(Color.readableSecondary)
                }
            }
            .navigationTitle("Edit Athlete")
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
            .alert("Couldn't Save Athlete", isPresented: $showingSaveError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(saveErrorMessage)
            }
        }
    }

    /// Copies the edited values back to the model and saves them.
    private func save() {
        athlete.firstName = firstName.trimmingCharacters(in: .whitespaces)
        athlete.lastName = lastName.trimmingCharacters(in: .whitespaces)
        athlete.dateOfBirth = dateOfBirth
        athlete.gender = gender
        // Optional contact fields are normalized to `nil` so empty strings do not get persisted.
        athlete.guardianName = guardianName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : guardianName.trimmingCharacters(in: .whitespacesAndNewlines)
        athlete.guardianPhone = guardianPhone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : guardianPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        athlete.guardianEmail = trimmedEmail.isEmpty ? nil : trimmedEmail
        athlete.developmentStage = developmentStage
        athlete.isActive = isActive
        
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }
}
