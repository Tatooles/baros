import SwiftUI

struct WorkoutHeaderView: View {
    let elapsedSeconds: Int
    let completedSets: Int
    let totalSets: Int
    let canReorderExercises: Bool
    let onFinish: () -> Void
    let onReorderExercises: () -> Void

    private var progressValue: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSets) / Double(totalSets)
    }

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(AppTheme.accentBright)
                        .frame(width: 7, height: 7)
                    Text(AppTheme.formatDuration(elapsedSeconds))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.textPrimary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .glassEffect(.regular)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Elapsed time \(AppTheme.formatDuration(elapsedSeconds))")

                HStack(spacing: 10) {
                    ProgressView(value: progressValue)
                        .progressViewStyle(.linear)
                        .tint(AppTheme.accentBright)
                    Text("\(completedSets)/\(totalSets)")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(AppTheme.textSecondary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44)
                .glassEffect(.regular)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(completedSets) of \(totalSets) sets completed")

                Menu {
                    Button {
                        onFinish()
                    } label: {
                        Label("Finish Workout", systemImage: "checkmark.circle")
                    }

                    Button {
                        onReorderExercises()
                    } label: {
                        Label("Reorder Exercises", systemImage: "arrow.up.arrow.down")
                    }
                    .disabled(!canReorderExercises)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .frame(width: 44, height: 44)
                        .contentShape(Circle())
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Workout options")
                .accessibilityIdentifier("WorkoutOptionsButton")
            }
        }
        .padding(.horizontal, AppTheme.shellPadding)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }
}
