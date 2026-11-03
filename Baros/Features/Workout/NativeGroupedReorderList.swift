import SwiftUI
import UIKit

/// UIKit's table reorder path keeps a tall block's insertion target stable.
/// SwiftUI List's collection-view path oscillates across a tall neighboring row.
struct NativeGroupedReorderList<Item: ReorderListExercise, Header: View>: UIViewRepresentable {
    let blocks: [SupersetGrouping.Block<Item>]
    let reorder: ([UUID]) -> Void
    let remove: (Set<UUID>) -> Void
    let add: () -> Void
    let header: Header

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITableView {
        let table = UITableView(frame: .zero, style: .plain)
        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 80
        table.contentInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        table.contentInsetAdjustmentBehavior = .never
        table.allowsSelectionDuringEditing = true
        table.register(UITableViewCell.self, forCellReuseIdentifier: "ExerciseBlock")
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.setEditing(true, animated: false)
        table.accessibilityIdentifier = "ReorderExercisesList"
        return table
    }

    func updateUIView(_ table: UITableView, context: Context) {
        let changed = context.coordinator.signature != signature
        context.coordinator.parent = self
        if changed {
            context.coordinator.signature = signature
            table.reloadData()
        }
    }

    fileprivate struct Presentation: Equatable {
        let id: UUID
        let name: String
        let metadata: String?
        let group: UUID?
        let detail: String?
        let isNew: Bool
    }

    private var signature: [Presentation] {
        blocks.flatMap { $0.members.map { Presentation(id: $0.id, name: $0.name,
            metadata: $0.metadata, group: $0.supersetGroupID, detail: $0.trailingDetail, isNew: $0.isNew) } }
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate {
        var parent: NativeGroupedReorderList
        fileprivate var signature: [Presentation]
        private var firstBlockRow: Int { Header.self == EmptyView.self ? 0 : 1 }
        init(_ parent: NativeGroupedReorderList) {
            self.parent = parent
            signature = parent.signature
        }
        private func block(at row: Int) -> SupersetGrouping.Block<Item>? {
            let index = row - firstBlockRow
            return parent.blocks.indices.contains(index) ? parent.blocks[index] : nil
        }
        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            firstBlockRow + parent.blocks.count + 1
        }
        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let cell = tableView.dequeueReusableCell(withIdentifier: "ExerciseBlock", for: indexPath)
            cell.backgroundConfiguration = .clear()
            cell.selectionStyle = .none
            cell.showsReorderControl = block(at: indexPath.row) != nil
            if let block = block(at: indexPath.row) {
                let remove = parent.remove
                cell.contentConfiguration = UIHostingConfiguration {
                    if block.isSuperset {
                        ReorderSupersetRow(exercises: block.members, remove: { remove([$0]) })
                    } else {
                        ReorderExerciseRow(exercise: block.members[0])
                    }
                }
                .margins(.vertical, 6)
                .margins(.leading, 4)
                .margins(.trailing, 8)
            } else if indexPath.row < firstBlockRow {
                cell.contentConfiguration = UIHostingConfiguration { parent.header }.margins(.all, 0)
            } else {
                let add = parent.add
                cell.contentConfiguration = UIHostingConfiguration {
                    Button(action: add) {
                        Label("Add Exercises", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(AppTheme.brandAccentForeground)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(AppTheme.brandAccentMuted, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("EditWorkoutAddExercisesButton")
                }.margins(.horizontal, 20).margins(.top, 8).margins(.bottom, 12)
            }
            return cell
        }
        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
            block(at: indexPath.row) != nil
        }
        func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            block(at: indexPath.row) != nil
        }
        func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
            block(at: indexPath.row)?.isSuperset == false ? .delete : .none
        }
        func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
            block(at: indexPath.row)?.isSuperset == false
        }
        func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
            guard editingStyle == .delete, let block = block(at: indexPath.row) else { return }
            parent.remove(Set(block.members.map(\.id)))
        }
        func tableView(_ tableView: UITableView, targetIndexPathForMoveFromRowAt source: IndexPath, toProposedIndexPath proposed: IndexPath) -> IndexPath {
            IndexPath(row: min(max(proposed.row, firstBlockRow), firstBlockRow + parent.blocks.count - 1), section: 0)
        }
        func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
            var blocks = parent.blocks
            let moved = blocks.remove(at: source.row - firstBlockRow)
            blocks.insert(moved, at: destination.row - firstBlockRow)
            signature = blocks.flatMap { $0.members.map { Presentation(id: $0.id, name: $0.name,
                metadata: $0.metadata, group: $0.supersetGroupID, detail: $0.trailingDetail, isNew: $0.isNew) } }
            parent.reorder(blocks.flatMap { $0.members.map(\.id) })
        }
    }
}

