import SwiftUI
import UIKit

/// What one exercise row in `ReorderExercisesList` shows.
protocol ReorderListExercise: Identifiable where ID == UUID {
    var name: String { get }
    var metadata: String? { get }
    var supersetGroupID: UUID? { get }
    /// Shown at the end of the detail line, such as set progress.
    var trailingDetail: String? { get }
    var isNew: Bool { get }
    var accessibilityValue: String { get }
}

/// System edit-mode lists own the minus, Delete, and reorder
/// grip along with their motion and accessibility. A superset is one row, so
/// it moves as a block; its members keep their own remove buttons.
struct ReorderExercisesList<Item: ReorderListExercise, Header: View>: View {
    let exercises: [Item]
    let reorder: ([UUID]) -> Void
    let remove: (Set<UUID>) -> Void
    var add: () -> Void = {}
    /// Rows above the exercises that don't move or delete.
    @ViewBuilder var header: Header

    var body: some View {
        let blocks = SupersetGrouping.blocks(exercises, groupID: \.supersetGroupID)
        Group {
            if blocks.contains(where: \.isSuperset) {
                NativeGroupedReorderList(blocks: blocks, reorder: reorder, remove: remove, add: add, header: header)
            } else {
                ungroupedList(blocks)
            }
        }
        #if DEBUG
        .overlay(alignment: .bottomLeading) {
            if ProcessInfo.processInfo.arguments.contains("--uitest-in-memory-store"),
               ProcessInfo.processInfo.arguments.contains("--uitest-reorder-stability-probe") {
                ReorderStabilityProbe().frame(width: 180, height: 12)
            }
        }
        #endif
    }

    private func ungroupedList(_ blocks: [SupersetGrouping.Block<Item>]) -> some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(true)
                .deleteDisabled(true)
            ForEach(blocks) { block in
                Group {
                    if block.isSuperset {
                        ReorderSupersetRow(exercises: block.members, remove: { remove([$0]) })
                    } else {
                        ReorderExerciseRow(exercise: block.members[0])
                            // Lifts only the card while dragging, not the whole row rectangle.
                            .contentShape(
                                .dragPreview,
                                RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
                            )
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 8))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .deleteDisabled(block.isSuperset)
            }
            .onMove { source, destination in
                var reordered = blocks
                reordered.move(fromOffsets: source, toOffset: destination)
                reorder(reordered.flatMap { $0.members.map(\.id) })
            }
            .onDelete { offsets in
                remove(Set(offsets.flatMap { blocks[$0].members.map(\.id) }))
            }
            Button(action: add) {
                Label("Add Exercises", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(AppTheme.brandAccentMuted, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("EditWorkoutAddExercisesButton")
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .moveDisabled(true)
            .deleteDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .environment(\.editMode, .constant(.active))
        .accessibilityIdentifier("ReorderExercisesList")
    }
}

extension ReorderExercisesList where Header == EmptyView {
    init(
        exercises: [Item],
        reorder: @escaping ([UUID]) -> Void,
        remove: @escaping (Set<UUID>) -> Void,
        add: @escaping () -> Void = {}
    ) {
        self.init(exercises: exercises, reorder: reorder, remove: remove, add: add) { EmptyView() }
    }
}

extension WorkoutExerciseListSnapshot.ExerciseState: ReorderListExercise {
    var trailingDetail: String? { progressText }
}

struct ReorderExerciseRow: View {
    static let cornerRadius: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize = 13
    let exercise: any ReorderListExercise

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            // The progress shares the detail line so names keep the card's full width.
            if dynamicTypeSize.isAccessibilitySize {
                if let metadata = exercise.metadata { detail(metadata) }
                trailing
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let metadata = exercise.metadata { detail(metadata).lineLimit(1) }
                    Spacer(minLength: 0)
                    trailing
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).fill(exercise.isNew ? AppTheme.brandAccentMuted : AppTheme.groupedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).stroke(exercise.isNew ? AppTheme.brandAccentForeground : AppTheme.subtleBorder)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(exercise.name)
        .accessibilityValue(exercise.accessibilityValue)
        .accessibilityIdentifier("ReorderExerciseRow-\(exercise.id.uuidString)")
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: detailSize, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
    }

    @ViewBuilder
    private var trailing: some View {
        if let text = exercise.trailingDetail {
            detail(exercise.isNew ? "New · \(text)" : text)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
        }
    }
}

/// A superset's members beside the rail. The system has no delete control for
/// part of a row, so each member gets its own minus button, sized so the cards
/// line up with single exercises.
struct ReorderSupersetRow<Item: ReorderListExercise>: View {
    /// Scales like the system minus, so members stay in line with single exercises.
    @ScaledMetric(relativeTo: .title2) private var removeColumnWidth = 28
    let exercises: [Item]
    let remove: (UUID) -> Void

    var body: some View {
        SupersetRail(count: exercises.count, spacing: 12, reachesIntoMargin: false, balancesLabel: true) {
            ForEach(exercises) { exercise in
                HStack(spacing: 2) {
                    Button {
                        remove(exercise.id)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .frame(width: removeColumnWidth)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(exercise.name)")
                    .accessibilityIdentifier("ReorderRemoveSupersetMember-\(exercise.id.uuidString)")

                    ReorderExerciseRow(exercise: exercise)
                }
            }
        }
        .contentShape(.dragPreview, Rectangle())
    }
}

#if DEBUG
/// Test-only sampling of native cell model frames, without animating or resizing the list.
/// A stationary hover must not repeatedly swap a neighboring block between two slots.
private struct ReorderStabilityProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.accessibilityIdentifier = "ReorderStabilityProbe"
        label.text = "Reorder probe"
        label.font = .systemFont(ofSize: 8)
        label.textColor = .clear
        let coordinator = context.coordinator
        coordinator.timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak label, weak coordinator] _ in
            MainActor.assumeIsolated {
                @MainActor func findCollection(_ view: UIView) -> UIScrollView? {
                    if let collection = view as? UICollectionView, view.accessibilityIdentifier == "ReorderExercisesList" { return collection }
                    if let table = view as? UITableView, view.accessibilityIdentifier == "ReorderExercisesList" { return table }
                    return view.subviews.lazy.compactMap { findCollection($0) }.first
                }
                guard let coordinator, let window = label?.window, let list = findCollection(window) else { return }
                let cells: [UIView] = (list as? UICollectionView)?.visibleCells ?? (list as? UITableView)?.visibleCells ?? []
                let order = cells.sorted { $0.frame.midY < $1.frame.midY }.map(ObjectIdentifier.init)
                let common = Set(order).intersection(coordinator.lastOrder)
                if common.count > 1, order.filter(common.contains) != coordinator.lastOrder.filter(common.contains) {
                    coordinator.moves += 1
                }
                coordinator.lastOrder = order
                label?.accessibilityValue = String(coordinator.moves)
            }
        }
        return label
    }
    func updateUIView(_ view: UILabel, context: Context) {}
    static func dismantleUIView(_ view: UILabel, coordinator: Coordinator) { coordinator.timer?.invalidate() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    @MainActor final class Coordinator {
        var timer: Timer?
        var lastOrder: [ObjectIdentifier] = []
        var moves = 0
    }
}
#endif
