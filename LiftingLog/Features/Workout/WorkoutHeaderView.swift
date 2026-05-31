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
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(AppTheme.accentBright)
                    .frame(width: 6, height: 6)
                Text(AppTheme.formatDuration(elapsedSeconds))
                    .font(.system(size: 15, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppTheme.surfaceMuted)
            .overlay(
                Capsule()
                    .stroke(AppTheme.borderStrong)
            )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Sets")
                    Spacer()
                    Text("\(completedSets)/\(totalSets)")
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)

                ProgressView(value: progressValue)
                    .tint(AppTheme.accentBright)
                    .scaleEffect(x: 1, y: 1.05, anchor: .center)
            }

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
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(AppTheme.surfaceMuted)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(AppTheme.borderStrong)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Workout options")
            .accessibilityIdentifier("WorkoutOptionsButton")
        }
        .padding(.horizontal, AppTheme.shellPadding)
        .padding(.top, 6)
        .padding(.bottom, 7)
        .background(.ultraThinMaterial.opacity(0.92))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppTheme.border)
                .frame(height: 1)
        }
    }
}
