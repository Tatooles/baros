import SwiftUI
import UIKit

/// Keeps UIKit's reorder grip, which SwiftUI List places outside a hosted row,
/// while the cell owns its minus and trash reveal. Sliding the whole cell
/// moves the card, grip, and trash together with deliberate spacing, and a
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
        /// One row at most shows its trash.
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
            cell.removeButton.accessibilityLabel = String(localized: "Remove \(exercise.name)")
            cell.onRemove = { [weak self] in self?.remove(exercise.id, fullSwipe: false) }
            cell.onFullSwipe = { [weak self] in self?.remove(exercise.id, fullSwipe: true) }
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

        /// Only stages the removal; the sheet's Done saves it.
        private func remove(_ id: UUID, fullSwipe: Bool) {
            guard let row = exercises.firstIndex(where: { $0.id == id }) else { return }
            revealedID = nil
            exercises.remove(at: row)
            if fullSwipe { cell(for: id)?.slideOut() } else { cell(for: id)?.fadeOutAction() }
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
            // The open row's trash takes its own tap; any other tap only collapses it.
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

/// Slides its bounds so the minus, card, grip, and trash move as one piece.
/// Dragging on past the revealed trash stretches it toward the row, and a
/// release past the full-swipe threshold removes the exercise from the draft.
final class ReorderExerciseCell: UITableViewCell {
    static let verticalInset: CGFloat = 6
    private static let actionSpacing: CGFloat = 12
    private static let trailingInset: CGFloat = 16
    /// Dragging past this fraction of the row width arms the full swipe, like `SwipeToDeleteRow`.
    private static let fullSwipeFraction: CGFloat = 0.5

    let removeButton = UIButton(type: .system)
    private let glyph = UIImageView()
    var exerciseID: UUID?
    var onPanBegan: (() -> Void)?
    var onRevealChanged: ((Bool) -> Void)?
    var onRemove: (() -> Void)?
    var onFullSwipe: (() -> Void)?
    private(set) var isRevealed = false
    private var isRemoving = false
    private var isArmed = false
    private var diameter: CGFloat = 50
    private var actionX: CGFloat = 0
    private var revealDistance: CGFloat = 0
    private var panStartOffset: CGFloat = 0
    /// Lets a newer reveal, drag, or reuse retire an older animation's completion.
    private var motionGeneration = 0
    private lazy var pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
    private let panDelegate = PanDelegate()
    private lazy var armFeedback = UIImpactFeedbackGenerator(style: .medium, view: self)

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundConfiguration = .clear()
        selectionStyle = .none
        showsReorderControl = true

        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = UIColor(AppTheme.destructive)
        configuration.cornerStyle = .capsule
        removeButton.configuration = configuration
        removeButton.accessibilityIdentifier = "ReorderRemoveAction"
        removeButton.addAction(UIAction { [weak self] _ in self?.onRemove?() }, for: .primaryActionTriggered)
        removeButton.isHidden = true
        removeButton.alpha = 0
        addSubview(removeButton)

        glyph.image = UIImage(systemName: "trash")
        glyph.preferredSymbolConfiguration = UIImage.SymbolConfiguration(
            font: UIFontMetrics(forTextStyle: .body)
                .scaledFont(for: .systemFont(ofSize: 20, weight: .semibold), maximumPointSize: 28)
        )
        glyph.tintColor = UIColor(AppTheme.onDestructive)
        glyph.contentMode = .center
        glyph.isUserInteractionEnabled = false
        removeButton.addSubview(glyph)

        panDelegate.cell = self
        pan.delegate = panDelegate
        addGestureRecognizer(pan)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func prepareForReuse() {
        super.prepareForReuse()
        isRemoving = false
        isArmed = false
        stopMotion()
        setRevealed(false, animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let height = max(bounds.height - 2 * Self.verticalInset, 0)
        // Grows with text size, but stops before it shoves accessibility-size cards off screen.
        diameter = min(UIFontMetrics(forTextStyle: .body).scaledValue(for: 50), 66, height)
        // The trash sits a fixed gap past the grip and ends at the trailing inset once revealed.
        actionX = gripMaxX + Self.actionSpacing
        revealDistance = max(actionX + diameter - (bounds.width - Self.trailingInset), 0)
        guard !isRemoving else { return }
        setOffset(pan.state == .began || pan.state == .changed ? bounds.origin.x : isRevealed ? revealDistance : 0)
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

    private var fullSwipeOffset: CGFloat {
        max(bounds.width * Self.fullSwipeFraction, revealDistance + 44)
    }

    /// Past the reveal the trash stretches into a capsule whose trailing end stays put.
    private func setOffset(_ offset: CGFloat) {
        bounds.origin.x = offset
        let stretch = max(offset - revealDistance, 0)
        removeButton.frame = CGRect(
            x: actionX, y: (bounds.height - diameter) / 2, width: diameter + stretch, height: diameter
        )
        layoutGlyph()
        guard !isRemoving else { return }
        removeButton.alpha = revealDistance <= 0 ? 0 : min(max(offset / revealDistance, 0), 1)
    }

    /// An armed glyph leads the capsule so it travels with the row.
    private func layoutGlyph() {
        let size = removeButton.bounds.size
        glyph.bounds.size = CGSize(width: diameter, height: diameter)
        glyph.center = CGPoint(x: isArmed ? diameter / 2 : size.width - diameter / 2, y: size.height / 2)
    }

    private func setArmed(_ armed: Bool) {
        guard armed != isArmed else { return }
        isArmed = armed
        if armed { armFeedback.impactOccurred() }
        if UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: glyph, duration: 0.15, options: .transitionCrossDissolve) { self.layoutGlyph() }
        } else {
            UIView.animate(springDuration: 0.3, bounce: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.layoutGlyph()
            }
        }
    }

    /// The action leaves first so it never lingers beside the row sliding up.
    func fadeOutAction() {
        isRemoving = true
        UIView.animate(withDuration: 0.12) { self.removeButton.alpha = 0 }
    }

    /// Carries the row off to the leading edge while its action fades.
    func slideOut() {
        isRemoving = true
        UIView.animate(withDuration: 0.12) { self.removeButton.alpha = 0 }
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        UIView.animate(springDuration: 0.3, bounce: 0) { self.setOffset(self.bounds.width) }
    }

    func setRevealed(_ revealed: Bool, animated: Bool) {
        isRevealed = revealed
        motionGeneration += 1
        let generation = motionGeneration
        removeButton.isHidden = false
        removeButton.isAccessibilityElement = revealed
        let finish = { [weak self] in
            guard let self, motionGeneration == generation else { return }
            removeButton.isHidden = !revealed
        }
        let target = revealed ? revealDistance : 0
        if !animated || window == nil {
            isArmed = false
            setOffset(target)
            finish()
        } else if UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: self, duration: 0.2, options: .transitionCrossDissolve) {
                self.isArmed = false
                self.setOffset(target)
            } completion: { _ in finish() }
        } else {
            UIView.animate(springDuration: 0.35, bounce: 0, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
                self.isArmed = false
                self.setOffset(target)
            } completion: { _ in finish() }
        }
        if revealed, animated {
            UIAccessibility.post(notification: .layoutChanged, argument: removeButton)
        }
    }

    /// Holds the row where it shows on screen and drops any settle, arm, or fade
    /// still running, so a drag or a reused row never inherits one.
    private func stopMotion() {
        motionGeneration += 1
        let onScreen = layer.presentation()?.bounds.origin.x ?? bounds.origin.x
        for key in layer.animationKeys() ?? [] {
            let animation = layer.animation(forKey: key)
            if animation is CATransition || (animation as? CAPropertyAnimation)?.keyPath == "bounds.origin" {
                layer.removeAnimation(forKey: key)
            }
        }
        removeButton.layer.removeAllAnimations()
        glyph.layer.removeAllAnimations()
        setOffset(onScreen)
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
            stopMotion()
            panStartOffset = bounds.origin.x
            removeButton.isHidden = false
            armFeedback.prepare()
        case .changed:
            let offset = min(max(panStartOffset - pan.translation(in: self).x, 0), bounds.width)
            setOffset(offset)
            setArmed(offset > fullSwipeOffset)
        case .ended:
            // Distance arms the full swipe; a flick back toward the row cancels it.
            let velocity = pan.velocity(in: self).x
            if isArmed, velocity < 300 {
                onFullSwipe?()
            } else {
                settle(revealed: velocity < -300 || (velocity < 300 && bounds.origin.x > revealDistance / 2))
            }
        case .cancelled, .failed:
            settle(revealed: bounds.origin.x > revealDistance / 2)
        default:
            break
        }
    }

    private func settle(revealed: Bool) {
        setRevealed(revealed, animated: true)
        onRevealChanged?(revealed)
    }

    /// UITableViewCell declares, but does not implement, these delegate methods.
    private final class PanDelegate: NSObject, UIGestureRecognizerDelegate {
        weak var cell: ReorderExerciseCell?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let cell, !cell.isRemoving else { return false }
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

/// Its content never switches layout when the row reveals its trash.
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
