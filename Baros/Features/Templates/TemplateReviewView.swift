import SwiftData
import SwiftUI

/// Shows a template's exercises before starting from it, like the past
/// workout review without set counts.
struct TemplateReviewView: View {
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Query private var exercises: [Exercise]
    let template: WorkoutTemplate
    let startWorkout: () -> Void
    @State private var editor: TemplateEditorPresentation?

    private var items: [TemplateExerciseItem] {
        TemplateExerciseItem.items(
            for: template.entries,
            exercisesByID: exercises.visibleByID(to: currentOwnerCoordinator.localDataOwnerTokenIdentifier)
        )
    }

    var body: some View {
        let items = items
        ScrollView(showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(template.name)
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("TemplateReviewTitle")
                    Text(items.count == 1 ? "1 exercise" : "\(items.count) exercises")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }

                Text("Exercises")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundStyle(AppTheme.textSecondary)
                    .padding(.top, 28)
                    .padding(.bottom, 6)

                let blocks = SupersetGrouping.blocks(items, groupID: \.supersetGroupID)
                ForEach(blocks) { block in
                    if block.isSuperset {
                        SupersetRail(count: block.members.count, spacing: 0) {
                            ForEach(block.members) { item in
                                row(item)
                                if item.id != block.members.last?.id { divider }
                            }
                        }
                        .padding(.top, 12)
                    } else {
                        row(block.members[0])
                    }

                    if block.id != blocks.last?.id { divider }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 22)
            .padding(.bottom, 20)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(action: startWorkout) {
                Label("Start Workout", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.glassProminent)
            .tint(AppTheme.brandAccentFill)
            .disabled(items.isEmpty)
            .accessibilityIdentifier("StartFromTemplateButton")
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(AppTheme.canvasBackground.ignoresSafeArea(edges: .bottom))
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("Review Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editor = .edit(template) }
                    .accessibilityIdentifier("EditTemplateButton")
            }
        }
        .sheet(item: $editor) { presentation in
            TemplateEditorSheet(template: presentation.template)
        }
    }

    private func row(_ item: TemplateExerciseItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.name)
                .font(.headline)
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let metadata = item.metadata {
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Divider()
            .overlay(AppTheme.subtleBorder)
    }
}
