import SwiftData
import SwiftUI

struct WorkoutHistoryDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(SyncScheduler.self) private var syncScheduler
    let session: WorkoutSession
    @State private var deleteErrorMessage: String?
    @State private var showsDeleteConfirmation = false
    @State private var editPresentation: CompletedWorkoutEditPresentation?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    private var allowsHistoryMutation: Bool {
        session.allowsHistoryMutation(ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !allowsHistoryMutation {
                    readOnlyNoticeBanner
                }

                WorkoutSummaryView(session: session, weightUnit: weightUnit)

                if allowsHistoryMutation {
                    Button(role: .destructive) {
                        showsDeleteConfirmation = true
                    } label: {
                        Text("Delete Workout")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(AppTheme.destructiveForeground)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(AppTheme.destructiveForeground)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if allowsHistoryMutation {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        editPresentation = CompletedWorkoutEditPresentation(session: session)
                    }
                    .accessibilityIdentifier("EditWorkoutButton")
                }
            }
        }
        .sheet(item: $editPresentation) { presentation in
            CompletedWorkoutEditView(
                session: session,
                draft: presentation.draft,
                weightUnit: weightUnit
            )
        }
        .alert("Delete Workout?", isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                deleteWorkout()
            }
        } message: {
            Text("This removes it from your history. This can't be undone.")
        }
        .alert(
            "Couldn't Delete Workout",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        deleteErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteErrorMessage ?? "Try deleting again.")
        }
    }

    private func deleteWorkout() {
        do {
            try WorkoutHistoryMutationService().deleteWorkoutHistory(
                session,
                ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                context: modelContext
            )
            syncScheduler.requestSync()
            deleteErrorMessage = nil
            dismiss()
        } catch {
            modelContext.rollback()
            deleteErrorMessage = error.localizedDescription
        }
    }

    private var readOnlyNoticeBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(AppTheme.brandAccentForeground)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text("Read-only workout")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("Sign in to the matching account to edit or delete this synced workout.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppTheme.brandAccentForeground.opacity(0.4))
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("WorkoutHistoryReadOnlyNotice")
    }
}

private struct CompletedWorkoutEditPresentation: Identifiable {
    let id: UUID
    let draft: CompletedWorkoutEditDraft

    init(session: WorkoutSession) {
        id = session.id
        draft = CompletedWorkoutEditDraft(session: session)
    }
}
