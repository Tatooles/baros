import SwiftUI
import UIKit

/// Keep the editing controls, grip, and trailing action in one native cell.
/// SwiftUI List owns its grip outside the hosted row, so a custom row reveal
/// cannot translate that grip along with the exercise.
struct ReorderExercisesList: UIViewRepresentable {
    @Environment(\.colorScheme) private var colorScheme
    let exercises: [WorkoutExerciseListSnapshot.ExerciseState]
    let reorder: ([UUID]) -> Void
    let remove: (UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.register(UITableViewCell.self, forCellReuseIdentifier: "Exercise")
        table.separatorStyle = .none
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 80
        table.contentInset.top = 8
        table.sectionHeaderTopPadding = 0
        table.accessibilityIdentifier = "ReorderExercisesList"
        table.setEditing(true, animated: false)
        return table
    }

    func updateUIView(_ table: UITableView, context: Context) {
        context.coordinator.parent = self
        table.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if context.coordinator.exercises != exercises {
            context.coordinator.exercises = exercises
            table.reloadData()
        }
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: ReorderExercisesList
        var exercises: [WorkoutExerciseListSnapshot.ExerciseState]

        init(_ parent: ReorderExercisesList) {
            self.parent = parent
            exercises = parent.exercises
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            exercises.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let exercise = exercises[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "Exercise", for: indexPath)
            cell.backgroundConfiguration = .clear()
            cell.selectionStyle = .none
            cell.showsReorderControl = true
            cell.accessibilityLabel = exercise.name
            cell.accessibilityIdentifier = "ReorderExerciseCell-\(exercise.id.uuidString)"
            cell.contentConfiguration = UIHostingConfiguration {
                ReorderExerciseRow(exercise: exercise)
                    .padding(.vertical, 6)
            }.margins(.all, 0)
            return cell
        }

        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }
        func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool { true }
        func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .delete }

        func tableView(_ tableView: UITableView, titleForDeleteConfirmationButtonForRowAt indexPath: IndexPath) -> String? {
            String(localized: "Remove")
        }

        func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
            guard editingStyle == .delete else { return }
            let removed = exercises.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: UIAccessibility.isReduceMotionEnabled ? .none : .automatic)
            parent.remove(removed.id)
        }

        func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
            let moved = exercises.remove(at: source.row)
            exercises.insert(moved, at: destination.row)
            parent.reorder(exercises.map(\.id))
        }

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            let exerciseID = exercises[indexPath.row].id
            let action = UIContextualAction(style: .destructive, title: String(localized: "Remove")) { [weak self] _, _, completion in
                guard let self, let row = self.exercises.firstIndex(where: { $0.id == exerciseID }) else {
                    completion(false)
                    return
                }
                self.tableView(tableView, commit: .delete, forRowAt: IndexPath(row: row, section: 0))
                completion(true)
            }
            action.backgroundColor = UIColor(AppTheme.destructiveFill)
            let configuration = UISwipeActionsConfiguration(actions: [action])
            configuration.performsFirstActionWithFullSwipe = false
            return configuration
        }
    }
}

/// Its content never switches layout when the native row reveals Remove.
struct ReorderExerciseRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize = 13
    let exercise: WorkoutExerciseListSnapshot.ExerciseState

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise.name)
                    .font(.system(size: titleSize, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                if let metadata = exercise.metadata {
                    Text(metadata)
                        .font(.system(size: detailSize, weight: .medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                }
                if dynamicTypeSize.isAccessibilitySize { progress }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !dynamicTypeSize.isAccessibilitySize { progress }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(AppTheme.groupedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(AppTheme.subtleBorder)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercise.name)
        .accessibilityValue(exercise.accessibilityValue)
        .accessibilityIdentifier("ReorderExerciseRow-\(exercise.id.uuidString)")
    }

    private var progress: some View {
        Text(exercise.progressText)
            .font(.system(size: detailSize, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }
}
