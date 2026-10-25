import SwiftUI
import UIKit

/// Keeps UIKit's reorder grip, which SwiftUI List places outside a hosted row,
/// while the cell owns its minus and Remove reveal. Sliding the whole cell
/// moves the card, grip, and Remove together with deliberate spacing, and a
/// removed row fades out without leaving a collapsing system action behind.
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
        table.register(ReorderExerciseCell.self, forCellReuseIdentifier: "Exercise")
        table.separatorStyle = .none
        table.backgroundColor = .clear
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 80
        table.contentInset.top = 8
        table.sectionHeaderTopPadding = 0
        table.accessibilityIdentifier = "ReorderExercisesList"
        table.setEditing(true, animated: false)
        let dismissTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.dismissReveal))
        dismissTap.delegate = context.coordinator
        table.addGestureRecognizer(dismissTap)
        context.coordinator.table = table
        context.coordinator.dismissTap = dismissTap
        return table
    }

    func updateUIView(_ table: UITableView, context: Context) {
        context.coordinator.parent = self
        table.overrideUserInterfaceStyle = colorScheme == .dark ? .dark : .light
        if context.coordinator.exercises != exercises {
            context.coordinator.exercises = exercises
            context.coordinator.revealedID = nil
            table.reloadData()
        }
    }

    final class Coordinator: NSObject, UITableViewDataSource, UITableViewDelegate, UIGestureRecognizerDelegate {
        var parent: ReorderExercisesList
        var exercises: [WorkoutExerciseListSnapshot.ExerciseState]
        weak var table: UITableView?
        weak var dismissTap: UITapGestureRecognizer?
        /// One row at most shows Remove.
        var revealedID: UUID?

        init(_ parent: ReorderExercisesList) {
            self.parent = parent
            exercises = parent.exercises
        }

        func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
            exercises.count
        }

        func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
            let exercise = exercises[indexPath.row]
            let cell = tableView.dequeueReusableCell(withIdentifier: "Exercise", for: indexPath) as! ReorderExerciseCell
            cell.exerciseID = exercise.id
            cell.accessibilityLabel = exercise.name
            cell.accessibilityIdentifier = "ReorderExerciseCell-\(exercise.id.uuidString)"
            cell.contentConfiguration = UIHostingConfiguration {
                ReorderExerciseRow(exercise: exercise) { [weak self] in self?.reveal(exercise.id) }
            }
            .margins(.vertical, ReorderExerciseCell.verticalInset)
            .margins(.leading, 4)
            .margins(.trailing, 8)
            cell.onPanBegan = { [weak self] in self?.collapse(except: exercise.id) }
            cell.onRevealChanged = { [weak self] revealed in
                guard let self else { return }
                if revealed {
                    revealedID = exercise.id
                } else if revealedID == exercise.id {
                    revealedID = nil
                }
            }
            cell.onRemove = { [weak self] in self?.remove(exercise.id) }
            cell.setRevealed(revealedID == exercise.id, animated: false)
            return cell
        }

        func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool { true }
        func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle { .none }
        func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool { false }

        func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            UISwipeActionsConfiguration(actions: [])
        }

        func tableView(_ tableView: UITableView, leadingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
            UISwipeActionsConfiguration(actions: [])
        }

        func tableView(
            _ tableView: UITableView,
            targetIndexPathForMoveFromRowAt source: IndexPath,
            toProposedIndexPath proposed: IndexPath
        ) -> IndexPath {
            collapse()
            return proposed
        }

        func tableView(_ tableView: UITableView, moveRowAt source: IndexPath, to destination: IndexPath) {
            let moved = exercises.remove(at: source.row)
            exercises.insert(moved, at: destination.row)
            parent.reorder(exercises.map(\.id))
        }

        func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
            collapse()
        }

        private func cell(for id: UUID) -> ReorderExerciseCell? {
            table?.visibleCells.lazy.compactMap { $0 as? ReorderExerciseCell }.first { $0.exerciseID == id }
        }

        private func reveal(_ id: UUID) {
            guard revealedID != id else { return }
            collapse()
            revealedID = id
            cell(for: id)?.setRevealed(true, animated: true)
        }

        func collapse(except id: UUID? = nil) {
            guard let revealedID, revealedID != id else { return }
            self.revealedID = nil
            cell(for: revealedID)?.setRevealed(false, animated: true)
        }

        private func remove(_ id: UUID) {
            guard let row = exercises.firstIndex(where: { $0.id == id }) else { return }
            revealedID = nil
            exercises.remove(at: row)
            cell(for: id)?.fadeOutAction()
            table?.deleteRows(
                at: [IndexPath(row: row, section: 0)],
                with: UIAccessibility.isReduceMotionEnabled ? .none : .fade
            )
            parent.remove(id)
        }

        @objc func dismissReveal() {
            collapse()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gestureRecognizer === dismissTap, let revealedID else { return false }
            // The open row's Remove takes its own tap; any other tap only collapses it.
            guard let action = cell(for: revealedID)?.removeButton, let view = touch.view else { return true }
            return !view.isDescendant(of: action)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            // Keeps a tap that collapses the open row from also pressing a minus.
            gestureRecognizer === dismissTap && revealedID != nil
        }
    }
}

/// Slides its bounds so the minus, card, grip, and Remove move as one piece.
final class ReorderExerciseCell: UITableViewCell {
    static let verticalInset: CGFloat = 6
    private static let actionSpacing: CGFloat = 12
    private static let trailingInset: CGFloat = 16

    let removeButton = UIButton(type: .system)
    var exerciseID: UUID?
    var onPanBegan: (() -> Void)?
    var onRevealChanged: ((Bool) -> Void)?
    var onRemove: (() -> Void)?
    private(set) var isRevealed = false
    private var isRemoving = false
    private var revealDistance: CGFloat = 0
    private var panStartOffset: CGFloat = 0
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    private let panDelegate = PanDelegate()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundConfiguration = .clear()
        selectionStyle = .none
        showsReorderControl = true

        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "Remove")
        configuration.baseBackgroundColor = UIColor(AppTheme.destructiveFill)
        configuration.baseForegroundColor = UIColor(AppTheme.onDestructive)
        configuration.cornerStyle = .fixed
        configuration.background.cornerRadius = ReorderExerciseRow.cornerRadius
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 14, bottom: 0, trailing: 14)
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFontMetrics(forTextStyle: .subheadline)
                .scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
            return attributes
        }
        removeButton.configuration = configuration
        removeButton.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .primaryActionTriggered)
        removeButton.isHidden = true
        removeButton.alpha = 0
        addSubview(removeButton)

        panDelegate.cell = self
        pan.delegate = panDelegate
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        isRemoving = false
        setRevealed(false, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = max(bounds.height - 2 * Self.verticalInset, 0)
        let width = max(removeButton.sizeThatFits(CGSize(width: .greatestFiniteMagnitude, height: height)).width, height)
        // Remove sits a fixed gap past the grip and ends at the trailing inset once revealed.
        removeButton.frame = CGRect(x: gripMaxX + Self.actionSpacing, y: Self.verticalInset, width: width, height: height)
        revealDistance = max(removeButton.frame.maxX - (bounds.width - Self.trailingInset), 0)
        if isRevealed, pan.state != .changed { setOffset(revealDistance) }
    }

    /// Trailing edge of the visible grip glyph, which UIKit insets within its control.
    private var gripMaxX: CGFloat {
        guard let control = reorderControl else { return contentView.frame.maxX + 28 }
        let glyph = control.subviews.first { $0 is UIImageView && !$0.isHidden }
        return glyph.map { control.convert($0.frame, to: self).maxX } ?? control.frame.midX + 10
    }

    private var reorderControl: UIView? {
        subviews.first {
            $0 !== contentView && $0 !== removeButton && !$0.isHidden && $0.bounds.width > 0
                && $0.frame.minX >= contentView.frame.maxX - 1
        }
    }

    private func setOffset(_ offset: CGFloat) {
        bounds.origin.x = offset
        removeButton.alpha = isRemoving || revealDistance <= 0 ? 0 : min(max(offset / revealDistance, 0), 1)
    }

    /// The action leaves first so it never lingers beside the row sliding up.
    func fadeOutAction() {
        isRemoving = true
        UIView.animate(withDuration: 0.12) { self.removeButton.alpha = 0 }
    }

    func setRevealed(_ revealed: Bool, animated: Bool) {
        isRevealed = revealed
        removeButton.isHidden = false
        removeButton.isAccessibilityElement = revealed
        let finish = { [weak self] in
            guard let self, isRevealed == revealed else { return }
            removeButton.isHidden = !revealed
        }
        let target = revealed ? revealDistance : 0
        if !animated || window == nil {
            setOffset(target)
            finish()
        } else if UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) {
                self.setOffset(target)
            } completion: { _ in finish() }
        } else {
            UIView.animate(springDuration: 0.35, bounce: 0, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.setOffset(target)
            } completion: { _ in finish() }
        }
        if revealed, animated {
            UIAccessibility.post(notification: .layoutChanged, argument: removeButton)
        }
    }

    override func accessibilityPerformEscape() -> Bool {
        guard isRevealed else { return false }
        setRevealed(false, animated: true)
        onRevealChanged?(false)
        return true
    }

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        switch pan.state {
        case .began:
            onPanBegan?()
            panStartOffset = bounds.origin.x
            removeButton.isHidden = false
        case .changed:
            var offset = max(panStartOffset - pan.translation(in: self).x, 0)
            // Resist past the action; a long swipe never removes on its own.
            if offset > revealDistance { offset = revealDistance + (offset - revealDistance) * 0.2 }
            setOffset(offset)
        case .ended, .cancelled, .failed:
            let velocity = pan.velocity(in: self).x
            let revealed = velocity < -300 || (velocity < 300 && bounds.origin.x > revealDistance / 2)
            setRevealed(revealed, animated: true)
            onRevealChanged?(revealed)
        default:
            break
        }
    }

    /// UITableViewCell declares, but does not implement, these delegate methods.
    private final class PanDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var cell: ReorderExerciseCell?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: cell)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // UIKit's grip keeps its own drag.
            guard let control = cell?.reorderControl, let view = touch.view else { return true }
            return !view.isDescendant(of: control)
        }
    }
}

/// Its content never switches layout when the row reveals Remove.
struct ReorderExerciseRow: View {
    static let cornerRadius: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize = 13
    @ScaledMetric(relativeTo: .body) private var minusSize = 22
    let exercise: WorkoutExerciseListSnapshot.ExerciseState
    let reveal: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: reveal) {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: minusSize))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, AppTheme.destructive)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(exercise.name)")
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            // The progress shares the detail line so names keep the card's full width.
            if dynamicTypeSize.isAccessibilitySize {
                if let metadata = exercise.metadata { detail(metadata) }
                progress
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let metadata = exercise.metadata { detail(metadata).lineLimit(1) }
                    Spacer(minLength: 0)
                    progress
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .background(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).fill(AppTheme.groupedSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous).stroke(AppTheme.subtleBorder)
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

    private var progress: some View {
        detail(exercise.progressText)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }
}
