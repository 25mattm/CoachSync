/// Creates a new technical assessment and its per-factor ratings.
import SwiftUI
import SwiftData

/// Form for recording a technical assessment for an athlete.
struct NewAssessmentView: View {
    let athlete: Athlete

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var assessmentDate = Date()
    @State private var stage: DevelopmentStage
    @State private var overallNotes = ""
    @State private var scoreByFactorID: [String: Int] = [:]
    @State private var commentByFactorID: [String: String] = [:]
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    init(athlete: Athlete) {
        self.athlete = athlete
        _stage = State(initialValue: athlete.developmentStage)
    }

    private var groups: [AssessmentFactorGroup] {
        TechnicalAssessmentCatalog.groups(for: stage)
    }

    private var canSave: Bool {
        groups.allSatisfy { group in
            group.factors.allSatisfy { factor in
                scoreByFactorID[factor.id] != nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionHeader(title: "Assessment Details")
                    VStack(alignment: .leading, spacing: 12) {
                        DatePicker("Date", selection: $assessmentDate, in: ...Date.now, displayedComponents: .date)
                        Picker("Stage", selection: $stage) {
                            ForEach(DevelopmentStage.allCases, id: \.self) { value in
                                Text(value.rawValue).tag(value)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                    SectionHeader(title: "Factor Ratings")

                    ForEach(groups) { group in
                        AssessmentCategoryCard(
                            group: group,
                            scoreByFactorID: $scoreByFactorID,
                            commentByFactorID: $commentByFactorID
                        )
                    }

                    SectionHeader(title: "Overall Notes")
                    TextField("Optional notes", text: $overallNotes, axis: .vertical)
                        .lineLimit(4...8)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
            .navigationTitle("New Assessment")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveAssessment()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .onAppear {
            seedMissingScores()
        }
        .onChange(of: stage) { _, _ in
            seedMissingScores()
        }
        .alert("Couldn't Save Assessment", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }

    /// Seeds default scores so newly visible factors always have editable values.
    private func seedMissingScores() {
        for group in groups {
            for factor in group.factors {
                if scoreByFactorID[factor.id] == nil {
                    scoreByFactorID[factor.id] = 3
                }
                if commentByFactorID[factor.id] == nil {
                    commentByFactorID[factor.id] = ""
                }
            }
        }
    }

    /// Persists the assessment and its child ratings in one save operation.
    private func saveAssessment() {
        let notes = overallNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        let assessment = TechnicalAssessment(
            date: assessmentDate,
            stage: stage,
            athlete: athlete,
            overallNotes: notes.isEmpty ? nil : notes
        )

        modelContext.insert(assessment)

        for group in groups {
            for factor in group.factors {
                guard let score = scoreByFactorID[factor.id] else { continue }
                let commentText = commentByFactorID[factor.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let rating = TechnicalRating(
                    category: group.title,
                    factor: factor.name,
                    score: score,
                    comment: commentText.isEmpty ? nil : commentText,
                    assessment: assessment
                )
                modelContext.insert(rating)
            }
        }

        athlete.developmentStage = stage
        do {
            try SyncStore.save(modelContext)
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
            showingSaveError = true
        }
    }
}

/// Groups related assessment factors and tracks the current average score.
struct AssessmentCategoryCard: View {
    let group: AssessmentFactorGroup
    @Binding var scoreByFactorID: [String: Int]
    @Binding var commentByFactorID: [String: String]

    private var averageScore: Double {
        let scores = group.factors.compactMap { scoreByFactorID[$0.id] }
        guard !scores.isEmpty else { return 0 }
        let total = scores.reduce(0, +)
        return Double(total) / Double(scores.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(group.title)
                    .font(.headline)
                Spacer()
                Text(String(format: "Avg %.2f", averageScore))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(group.factors) { factor in
                VStack(alignment: .leading, spacing: 8) {
                    Text(factor.name)
                        .font(.subheadline)

                    QuickScorePicker(score: Binding(
                        get: { scoreByFactorID[factor.id] ?? 3 },
                        set: { scoreByFactorID[factor.id] = $0 }
                    ))

                    TextField("Optional comment", text: Binding(
                        get: { commentByFactorID[factor.id] ?? "" },
                        set: { commentByFactorID[factor.id] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Compact 1-5 score picker used for each assessment factor.
struct QuickScorePicker: View {
    @Binding var score: Int

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    score = value
                } label: {
                    Text("\(value)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(value == score ? Color.accentColor.opacity(0.22) : Color.gray.opacity(0.14))
                        .foregroundStyle(value == score ? Color.accentColor : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A titled group of technical assessment factors.
struct AssessmentFactorGroup: Identifiable {
    let title: String
    let factors: [AssessmentFactor]

    var id: String { title }
}

/// One scorable factor within a technical assessment group.
struct AssessmentFactor: Identifiable {
    let category: String
    let name: String

    var id: String { "\(category)|\(name)" }
}

/// Supplies the stage-specific technical assessment checklist.
enum TechnicalAssessmentCatalog {
    static func groups(for stage: DevelopmentStage) -> [AssessmentFactorGroup] {
        var baseGroups: [AssessmentFactorGroup] = [
            makeGroup(
                title: "Balance Set-Up",
                factors: technicalBalanceFactors(for: stage)
            ),
            makeGroup(
                title: "Catch",
                factors: technicalCatchFactors(for: stage)
            ),
            makeGroup(
                title: "Draw",
                factors: technicalDrawFactors(for: stage)
            ),
            makeGroup(
                title: "Exit",
                factors: technicalExitFactors(for: stage)
            ),
            makeGroup(
                title: "Boat Control",
                factors: boatControlFactors(for: stage)
            )
        ]

        if stage == .consolidation || stage == .refinement {
            baseGroups.append(
                makeGroup(
                    title: "Tactical 200m/500m",
                    factors: [
                        "Reaction Time",
                        "Start Acceleration",
                        "Top Speed",
                        "Speed Reserve"
                    ]
                )
            )
            baseGroups.append(
                makeGroup(
                    title: "Tactical 1000m",
                    factors: [
                        "First 250m",
                        "Travelling pace",
                        "Effective Stroke",
                        "Effective pacing",
                        "Decision Making",
                        "Focus"
                    ]
                )
            )
        }

        return baseGroups
    }

    private static func makeGroup(title: String, factors: [String]) -> AssessmentFactorGroup {
        AssessmentFactorGroup(
            title: title,
            factors: factors.map { AssessmentFactor(category: title, name: $0) }
        )
    }

    private static func technicalBalanceFactors(for stage: DevelopmentStage) -> [String] {
        switch stage {
        case .initiation:
            return [
                "Position and posture in boat",
                "Level boat bow-stern and left-right",
                "Hand position on paddle is 1/3 1/3 1/3"
            ]
        case .acquisition:
            return [
                "Knees together",
                "Chin over hips",
                "Level boat left/right",
                "Balance boat while rotating hips and moving legs"
            ]
        case .consolidation:
            return [
                "Seated forward on seat",
                "Rotation occurs in seat",
                "Forward lean from hips chest up and flat",
                "Hold posture through stroke",
                "Boat is level or leans to paddling side"
            ]
        case .refinement:
            return [
                "Forward lean 10 to 15 degrees chin in front of hips",
                "Weight stays on paddling side using pressure through footboard",
                "Dynamic rhythmical weight transfer from stroke to stroke",
                "Maintain control through each phase of stroke"
            ]
        }
    }

    private static func technicalCatchFactors(for stage: DevelopmentStage) -> [String] {
        switch stage {
        case .initiation:
            return [
                "Basic rotation of body",
                "Clean quiet catch sink the blade",
                "Can twist paddle to catch square on both sides"
            ]
        case .acquisition:
            return [
                "Iron bar top arm elbow to paddling side shoulder",
                "Top hand at or above shoulder level",
                "Reach achieved via rotation of hips and torso",
                "Bottom arm is extended",
                "Maintain blade angle and rotation at catch"
            ]
        case .consolidation:
            return [
                "Maintain iron bar from top shoulder across chest",
                "Hold top hand angle at 90 degrees",
                "Initiate catch with both hands",
                "Bury blade fully at catch keep hands dry",
                "Blade is locked before any rotation is initiated",
                "Hold paddling side hip forward until catch"
            ]
        case .refinement:
            return [
                "Paddle angle is 60 to 65 degrees at catch",
                "Blade catch is timed with beginning of leg drive",
                "Paddle fixes and finds resistance without changing arm position",
                "Complete weight transfer to blade",
                "Pressure on footboard at catch"
            ]
        }
    }

    private static func technicalDrawFactors(for stage: DevelopmentStage) -> [String] {
        switch stage {
        case .initiation:
            return [
                "Bottom arm extended",
                "Proper posture maintained",
                "Basic leg movement observed"
            ]
        case .acquisition:
            return [
                "No adduction in shoulder angle",
                "Top hand maintains height through draw",
                "Tall posture maintained throughout stroke",
                "Shaft parallel to chest throughout stroke"
            ]
        case .consolidation:
            return [
                "Legs and torso coordinated",
                "Shaft parallel to chest while top hand height stays constant",
                "Pressure connects through heels on footboard",
                "Boat moves past locked paddle in water"
            ]
        case .refinement:
            return [
                "Pressure maintained through hip torso paddle connection",
                "Constant pressure on paddle shaft through both hands",
                "Hip movement linked and connected to entire stroke",
                "Torso and leg drive completely synchronized with top arm"
            ]
        }
    }

    private static func technicalExitFactors(for stage: DevelopmentStage) -> [String] {
        switch stage {
        case .initiation:
            return [
                "Bottom hand exits before or at hip",
                "Exit should not slow the boat down"
            ]
        case .acquisition:
            return [
                "Tall posture is maintained",
                "Bottom hand exits at or before the hip"
            ]
        case .consolidation:
            return [
                "Lift the hand not the elbow",
                "Maintain neutral wrist",
                "Elbow stays below the paddle shaft"
            ]
        case .refinement:
            return [
                "Pressure on paddle seat footboard maintained through exit",
                "Elbows stay in front of lateral line of body",
                "Rotation and forward motion through recovery",
                "Lead with top arm through recovery"
            ]
        }
    }

    private static func boatControlFactors(for stage: DevelopmentStage) -> [String] {
        switch stage {
        case .initiation:
            return [
                "Use of kayak steering mechanism",
                "Basic forward, back, draw, and check stroke",
                "Can launch and dock boat",
                "Able to raft up",
                "Able to complete basic obstacle course"
            ]
        case .acquisition:
            return [
                "Steering efficiently without interrupting the stroke",
                "Group paddling – handling wash",
                "Line up at a start line",
                "Control the boat steering during a race"
            ]
        case .consolidation:
            return [
                "Basic wash riding (2-3-4 Diamond)",
                "Ability to manage boat position on start line",
                "Group workout turns",
                "Long distance racing turns with boat lean"
            ]
        case .refinement:
            return [
                "Control of boat under all conditions",
                "Can wash-ride in complex conditions with many changes",
                "Can hold starts with pressure on blade",
                "Can shoot the boat"
            ]
        }
    }
}
