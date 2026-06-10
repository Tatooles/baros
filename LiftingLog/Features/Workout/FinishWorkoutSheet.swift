import SwiftData
import SwiftUI

struct FinishWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @State private var showsDiscardConfirmation = false
    @State private var actionError: WorkoutActionError?

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(AppTheme.borderStrong)
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            VStack(spacing: 4) {
                Text("Finish Workout?")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Review your session summary")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }

            HStack(spacing: 10) {
                summaryCard(title: "Duration", value: AppTheme.formatDuration(metrics.durationSeconds))
                summaryCard(title: "Sets Done", value: "\(metrics.completedSetCount)/\(metrics.totalSetCount)")
                summaryCard(title: "Volume", value: WorkoutFormatters.number(metrics.completedVolume))
            }

            Button {
                do {
                    try engine.finishWorkout(
                        session,
                        ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                        syncScheduler: syncScheduler,
                        context: modelContext
                    )
                    actionError = nil
                    dismiss()
                } catch {
                    actionError = WorkoutActionError(title: "Couldn't Save Workout", message: error.localizedDescription)
                }
            } label: {
                Text("Save Workout")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(AppTheme.accentGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("SaveWorkoutButton")

            Button("Keep Going") {
                dismiss()
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .accessibilityIdentifier("KeepGoingButton")

            Button(role: .destructive) {
                showsDiscardConfirmation = true
            } label: {
                Text("Discard Workout")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppTheme.accentBright)
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .background(AppTheme.surface)
        .presentationDetents([.height(390)])
        .presentationCornerRadius(28)
        .alert("Discard Workout?", isPresented: $showsDiscardConfirmation) {
            Button("Discard", role: .destructive) {
                do {
                    try engine.discardWorkout(session, context: modelContext)
                    actionError = nil
                    dismiss()
                } catch {
                    actionError = WorkoutActionError(title: "Couldn't Discard Workout", message: error.localizedDescription)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will hide the active workout from history.")
        }
        .alert(item: $actionError) { actionError in
            Alert(
                title: Text(actionError.title),
                message: Text(actionError.message),
                dismissButton: .cancel(Text("OK"))
            )
        }
    }

    private struct WorkoutActionError: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    private func summaryCard(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(AppTheme.textPrimary)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(AppTheme.surfaceMuted)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppTheme.border)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
