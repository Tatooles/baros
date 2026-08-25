import SwiftUI

struct HomePastWorkoutReviewView: View {
    let session: WorkoutSession
    let startWorkout: () -> Void

    private var presentation: HomePastWorkoutReviewPresentation {
        HomePastWorkoutReviewPresentation(session: session)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                header

                Text("Exercises")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 28)
                    .padding(.bottom, 6)
                    .accessibilityIdentifier("PastWorkoutReviewExercisesHeading")

                if presentation.exercises.isEmpty {
                    Text("No exercises to copy")
                        .font(.body)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                        .accessibilityIdentifier("PastWorkoutReviewEmptyState")
                } else {
                    ForEach(Array(presentation.exercises.enumerated()), id: \.element.id) { index, exercise in
                        HomePastWorkoutReviewExerciseRow(
                            exercise: exercise,
                            accessibilityIdentifier: "PastWorkoutReviewExercise-\(index)"
                        )

                        if index < presentation.exercises.count - 1 {
                            Divider()
                                .overlay(AppTheme.subtleBorder)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            startWorkoutFooter
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("Review Workout")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(session.title)
                .font(.title.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("StartFromPastWorkoutSheetTitle")

            Text("Based on \(WorkoutFormatters.compactDate(presentation.completedAt))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
                .accessibilityIdentifier("PastWorkoutReviewProvenance")

            Text(presentation.structureSummary)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("PastWorkoutReviewStructureSummary")
        }
        .accessibilityElement(children: .contain)
    }

    private var startWorkoutFooter: some View {
        Button(action: startWorkout) {
            Label("Start Workout", systemImage: "play.fill")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.glassProminent)
        .tint(AppTheme.brandAccentFill)
        .accessibilityIdentifier("StartFromPastWorkoutConfirmButton")
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(AppTheme.canvasBackground.ignoresSafeArea(edges: .bottom))
    }
}

private struct HomePastWorkoutReviewExerciseRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let exercise: HomePastWorkoutReviewPresentation.Exercise
    let accessibilityIdentifier: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    exerciseIdentity
                    copiedSetCount
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    exerciseIdentity
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    copiedSetCount
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private var exerciseIdentity: some View {
        VStack(alignment: .leading, spacing: 3) {
            exerciseName

            if let equipment = exercise.equipment {
                Text(equipment)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private var exerciseName: some View {
        if exposesLayoutRegionsForUITesting {
            exerciseNameText
                .accessibilityIdentifier("\(accessibilityIdentifier)-Identity")
        } else {
            exerciseNameText
        }
    }

    private var exerciseNameText: some View {
        Text(exercise.name)
            .font(.headline)
            .foregroundStyle(AppTheme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var copiedSetCount: some View {
        if exposesLayoutRegionsForUITesting {
            copiedSetCountText
                .accessibilityIdentifier("\(accessibilityIdentifier)-SetCount")
        } else {
            copiedSetCountText
        }
    }

    private var copiedSetCountText: some View {
        Text(exercise.copiedSetDescription)
            .font(.body)
            .foregroundStyle(AppTheme.textSecondary)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }

    private var accessibilityDescription: String {
        [exercise.name, exercise.equipment, exercise.copiedSetDescription]
            .compactMap { $0 }
            .joined(separator: ", ")
    }

    private var exposesLayoutRegionsForUITesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitest-accessibility-dynamic-type")
    }
}
