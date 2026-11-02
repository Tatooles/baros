import SwiftData
import SwiftUI

/// The owner's templates by name. Tapping one hands it to `open`; the
/// editor opens for new templates and from each row's Edit action.
struct TemplatesListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @Query private var allTemplates: [WorkoutTemplate]
    @Query private var exercises: [Exercise]
    /// Nil opens the editor on tap, for managing templates from Settings.
    var open: ((WorkoutTemplate) -> Void)?
    @State private var editor: TemplateEditorPresentation?
    @State private var pendingDelete: WorkoutTemplate?
    @State private var showsDeleteError = false

    private var templates: [WorkoutTemplate] {
        allTemplates.visible(to: currentOwnerCoordinator.localDataOwnerTokenIdentifier)
    }

    var body: some View {
        Group {
            if templates.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The empty state has its own button.
            if !templates.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editor = .new
                    } label: {
                        Label("New Template", systemImage: "plus")
                    }
                    .accessibilityIdentifier("NewTemplateButton")
                }
            }
        }
        .sheet(item: $editor) { presentation in
            TemplateEditorSheet(template: presentation.template)
        }
        .alert(
            "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            presenting: pendingDelete
        ) { template in
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { delete(template) }
        } message: { _ in
            Text("Workouts you started from it stay in your history.")
        }
        .alert("Couldn't Delete Template", isPresented: $showsDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The template wasn't deleted. Try again.")
        }
    }

    private var list: some View {
        let exercisesByID = exercises.visibleByID(to: currentOwnerCoordinator.localDataOwnerTokenIdentifier)
        return List {
            ForEach(templates) { template in
                Button {
                    if let open { open(template) } else { editor = .edit(template) }
                } label: {
                    TemplateRow(template: template, exercisesByID: exercisesByID)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 5, leading: 20, bottom: 5, trailing: 20))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                // No destructive role on the swipe button: that role removes
                // the row before the confirmation, even when it's cancelled.
                // The app-wide tint turns these blue without an explicit one.
                .swipeActions(allowsFullSwipe: false) {
                    Button("Delete") { pendingDelete = template }
                        .tint(AppTheme.destructive)
                }
                .contextMenu {
                    Button("Edit", systemImage: "pencil") { editor = .edit(template) }
                    Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = template }
                        .tint(AppTheme.destructive)
                }
                .accessibilityIdentifier("TemplateRow-\(template.name)")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 10, for: .scrollContent)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("No Templates")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("A template is a list of exercises to start a workout from.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            Button {
                editor = .new
            } label: {
                Label("New Template", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .padding(.horizontal, 22)
                    .frame(minHeight: 50)
                    .background(AppTheme.brandAccentMuted, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("EmptyNewTemplateButton")
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func delete(_ template: WorkoutTemplate) {
        do {
            try WorkoutTemplateMutationService(syncScheduler: syncScheduler).deleteTemplate(
                template,
                ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                context: modelContext
            )
        } catch {
            modelContext.rollback()
            showsDeleteError = true
        }
    }
}

enum TemplateEditorPresentation: Identifiable {
    case new
    case edit(WorkoutTemplate)

    var id: UUID? {
        if case let .edit(template) = self { template.id } else { nil }
    }

    var template: WorkoutTemplate? {
        if case let .edit(template) = self { template } else { nil }
    }
}

private struct TemplateRow: View {
    let template: WorkoutTemplate
    let exercisesByID: [UUID: Exercise]

    private var exerciseNames: String {
        TemplateExerciseItem.items(for: template.entries, exercisesByID: exercisesByID)
            .map(\.name)
            .joined(separator: ", ")
    }

    var body: some View {
        SurfaceCard {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(template.entries.count == 1 ? "1 exercise" : "\(template.entries.count) exercises")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text(exerciseNames)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppTheme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
