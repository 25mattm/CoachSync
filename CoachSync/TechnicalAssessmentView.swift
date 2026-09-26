/// Shows development stage information and past technical assessments for an athlete.
import SwiftUI
import SwiftData

/// Technical assessment history screen for an athlete.
struct TechnicalAssessmentView: View {
    @Bindable var athlete: Athlete
    @Environment(\.modelContext) private var modelContext

    @State private var showingNewAssessment = false
    @State private var showingSaveError = false
    @State private var saveErrorMessage = ""

    private var sortedAssessments: [TechnicalAssessment] {
        (athlete.technicalAssessments ?? []).sorted { lhs, rhs in
            if lhs.date == rhs.date {
                return lhs.createdAt > rhs.createdAt
            }
            return lhs.date > rhs.date
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionHeader(title: "Current Stage")

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        DevelopmentStagePill(stage: athlete.developmentStage)
                        Spacer()
                    }

                    Picker("Development Stage", selection: $athlete.developmentStage) {
                        ForEach(DevelopmentStage.allCases, id: \.self) { stage in
                            Text(stage.rawValue).tag(stage)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: athlete.developmentStage) { _, _ in
                        do {
                            try SyncStore.save(modelContext)
                        } catch {
                            saveErrorMessage = error.localizedDescription
                            showingSaveError = true
                        }
                    }
                }
                .padding(14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                HStack {
                    SectionHeader(title: "Past Assessments")
                    Spacer()
                    Button("New Assessment") {
                        showingNewAssessment = true
                    }
                    .font(.subheadline)
                }

                if sortedAssessments.isEmpty {
                    EmptyCard(message: "No technical assessments recorded yet", systemImage: "list.bullet.clipboard")
                } else {
                    VStack(spacing: 10) {
                        ForEach(sortedAssessments) { assessment in
                            AssessmentHistoryCard(assessment: assessment)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("Technical")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .sheet(isPresented: $showingNewAssessment) {
            NewAssessmentView(athlete: athlete)
#if os(macOS)
                .frame(minWidth: 720, minHeight: 760)
#endif
        }
        .alert("Couldn't Save Stage", isPresented: $showingSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
        }
    }
}

/// Summary card for one recorded technical assessment.
struct AssessmentHistoryCard: View {
    let assessment: TechnicalAssessment

    private var averageText: String {
        if assessment.ratings?.isEmpty != false {
            return "No ratings"
        }
        return String(format: "%.2f", assessment.averageScore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(assessment.date.formatted(.dateTime.month(.abbreviated).day().year()))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                DevelopmentStagePill(stage: assessment.stage)
            }

            HStack {
                Label("Avg \(averageText)", systemImage: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(assessment.ratings?.count ?? 0) factors")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let notes = assessment.overallNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Visual label for a development stage.
struct DevelopmentStagePill: View {
    let stage: DevelopmentStage

    var body: some View {
        Text(stage.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(stage.color.opacity(0.15))
            .foregroundStyle(stage.color)
            .clipShape(Capsule())
    }
}

/// UI helpers for presenting development stages consistently.
extension DevelopmentStage {
    var color: Color {
        switch self {
        case .initiation:
            return .blue
        case .acquisition:
            return .green
        case .consolidation:
            return .orange
        case .refinement:
            return .red
        }
    }
}
