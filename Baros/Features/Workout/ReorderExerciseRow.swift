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
/// it moves as a block; its members keep their own minus and Delete.
struct ReorderExercisesList<Item: ReorderListExercise, Header: View>: View {
    let exercises: [Item]
    let reorder: ([UUID]) -> Void
    let remove: (Set<UUID>) -> Void
    let add: () -> Void
    /// Takes the exercises' new superset ids, in the order of `exercises`.
    let regroup: ([UUID?]) -> Void
    /// Rows above the exercises that don't move or delete.
    let header: Header
    @State private var isLinking = false
    /// Carries card positions and the scroll offset between the regular list and link mode.
    @State private var memory = ReorderListMemory()
    @State private var memberReveal = ReorderMemberReveal()

    init(
        exercises: [Item],
        reorder: @escaping ([UUID]) -> Void,
        remove: @escaping (Set<UUID>) -> Void,
        add: @escaping () -> Void = {},
        regroup: @escaping ([UUID?]) -> Void,
        @ViewBuilder header: () -> Header
    ) {
        self.exercises = exercises
        self.reorder = reorder
        self.remove = remove
        self.add = add
        self.regroup = regroup
        self.header = header()
    }

    var body: some View {
        let blocks = SupersetGrouping.blocks(exercises, groupID: \.supersetGroupID)
        // The two lists crossfade because the system animates its edit controls
        // on its own clock, so changing them in place visibly jumps.
        ZStack {
            if isLinking {
                ReorderLinkList(
                    exercises: exercises,
                    regroup: regroup,
                    finish: {
                        memory.offsetToRestore = memory.offset
                        withAnimation(Self.modeAnimation) { isLinking = false }
                    },
                    header: header,
                    memory: memory
                )
                .transition(.opacity)
            } else {
                Group {
                    if blocks.contains(where: \.isSuperset) {
                        NativeGroupedReorderList(
                            blocks: blocks, reorder: reorder, remove: remove, add: add,
                            link: linkAction, memory: memory, memberReveal: memberReveal, header: header
                        )
                    } else {
                        ungroupedList(blocks)
                    }
                }
                .transition(.opacity)
            }
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { memory.listFrame = $0 }
        .onChange(of: canLink) { _, canLink in
            // A workout reloaded by sync can drop below two exercises.
            if !canLink { isLinking = false }
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

    private static var modeAnimation: Animation { .easeInOut(duration: 0.2) }

    private var canLink: Bool { exercises.count >= 2 }

    private var linkAction: (() -> Void)? {
        guard canLink else { return nil }
        return { withAnimation(Self.modeAnimation) { isLinking = true } }
    }

    private func ungroupedList(_ blocks: [SupersetGrouping.Block<Item>]) -> some View {
        ungroupedRows(blocks)
            .rememberingScrollOffset(in: memory)
    }

    private func ungroupedRows(_ blocks: [SupersetGrouping.Block<Item>]) -> some View {
        List {
            header
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .moveDisabled(true)
                .deleteDisabled(true)
            ForEach(blocks) { block in
                Group {
                    if block.isSuperset {
                        ReorderSupersetRow(exercises: block.members, memory: memory, reveal: memberReveal, remove: { remove([$0]) })
                    } else {
                        ReorderExerciseRow(exercise: block.members[0], memory: memory)
                            // Lifts only the card while dragging, not the whole row rectangle.
                            .contentShape(
                                .dragPreview,
                                RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
                            )
                    }
                }
                // Lines the cards up with the superset list's, so they stay put when it swaps in.
                .listRowInsets(EdgeInsets(top: 6, leading: 7.5, bottom: 6, trailing: 14))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .deleteDisabled(block.isSuperset)
                .background {
                    if block.id == blocks.first?.id { ReorderScrollRestorer(memory: memory) }
                }
            }
            .onMove { source, destination in
                var reordered = blocks
                reordered.move(fromOffsets: source, toOffset: destination)
                reorder(reordered.flatMap { $0.members.map(\.id) })
            }
            .onDelete { offsets in
                remove(Set(offsets.flatMap { blocks[$0].members.map(\.id) }))
            }
            ReorderListActions(add: add, link: linkAction)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .moveDisabled(true)
            .deleteDisabled(true)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.vertical, 8, for: .scrollContent)
        .environment(\.editMode, .constant(.active))
        .accessibilityIdentifier("ReorderExercisesList")
    }
}

extension ReorderExercisesList where Header == EmptyView {
    init(
        exercises: [Item],
        reorder: @escaping ([UUID]) -> Void,
        remove: @escaping (Set<UUID>) -> Void,
        add: @escaping () -> Void = {},
        regroup: @escaping ([UUID?]) -> Void
    ) {
        self.init(exercises: exercises, reorder: reorder, remove: remove, add: add, regroup: regroup) { EmptyView() }
    }
}

/// What link mode needs from the regular list to keep every card where it was. A
/// reference, so scrolling and layout don't redraw the list.
final class ReorderListMemory {
    var listFrame: CGRect = .zero
    /// Measured, since the system decides how much room its edit controls take.
    var cardFrames: [UUID: CGRect] = [:]
    /// How far down the exercises are scrolled.
    var offset: CGFloat = 0
    /// Set on leaving link mode, for the regular list that takes its place.
    /// Held apart because a new list reports its own starting offset right away.
    var offsetToRestore: CGFloat?
}

/// SwiftUI's List ignores `scrollPosition`, so this reaches the scroll view around
/// its row. The row is recreated as it scrolls back into view, hence the one-shot flag.
private struct ReorderScrollRestorer: UIViewRepresentable {
    let memory: ReorderListMemory

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        guard let offset = memory.offsetToRestore else { return view }
        memory.offsetToRestore = nil
        DispatchQueue.main.async { [weak view] in
            var ancestor = view?.superview
            while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
            guard let scrollView = ancestor as? UIScrollView else { return }
            scrollView.contentOffset.y = offset - scrollView.adjustedContentInset.top
        }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}

extension View {
    func rememberingScrollOffset(in memory: ReorderListMemory) -> some View {
        onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y + $0.contentInsets.top } action: { _, offset in
            memory.offset = offset
        }
    }
}

/// The list's last row. Link Exercises needs two exercises to link.
struct ReorderListActions: View {
    let add: () -> Void
    let link: (() -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { buttons }
            VStack(spacing: 10) { buttons }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        action("Add Exercises", systemImage: "plus", identifier: "EditWorkoutAddExercisesButton", perform: add)
        if let link {
            action("Link Exercises", systemImage: "link", identifier: "EditWorkoutLinkExercisesButton", perform: link)
        }
    }

    private func action(
        _ title: String, systemImage: String, identifier: String, perform: @escaping () -> Void
    ) -> some View {
        Button(action: perform) {
            // Fixed width: the row stacks the buttons rather than truncating a title.
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title).lineLimit(1)
            }
            .font(.headline)
            .foregroundStyle(AppTheme.brandAccentForeground)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(AppTheme.brandAccentMuted, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
    var memory: ReorderListMemory?
    /// Truncates each line of text to the height it had at rest instead of wrapping,
    /// so the card keeps its height while a Delete narrows it.
    var keepsRestingLines = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name)
                .font(.system(size: titleSize, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .modifier(RestingHeight(isKept: keepsRestingLines))
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
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            memory?.cardFrames[exercise.id] = frame
        }
    }

    private func detail(_ text: String) -> some View {
        Text(text)
            .font(.system(size: detailSize, weight: .medium))
            .foregroundStyle(AppTheme.textSecondary)
            .modifier(RestingHeight(isKept: keepsRestingLines))
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

/// Holds text at the height it measured while not kept, so a narrower frame
/// truncates it instead of adding lines.
private struct RestingHeight: ViewModifier {
    let isKept: Bool
    @State private var height: CGFloat?

    func body(content: Content) -> some View {
        content
            .frame(height: isKept ? height : nil, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                if !isKept { height = measured }
            }
    }
}

/// The superset member whose Delete is showing, shared by every row in the list
/// so a touch on any other row can close it.
@MainActor @Observable final class ReorderMemberReveal {
    var id: UUID?
}

/// A superset's members beside the rail. The system has no delete control for
/// part of a row, so each member gets its own minus button, sized so the cards
/// line up with single exercises. Like the system minus, it turns and reveals a
/// Delete beside the card; the next tap anywhere else closes it.
struct ReorderSupersetRow<Item: ReorderListExercise>: View {
    /// Scales like the system minus, so members stay in line with single exercises.
    @ScaledMetric(relativeTo: .title2) private var removeColumnWidth = 28
    /// Capped so large text sizes leave the card room for its name.
    @ScaledMetric(relativeTo: .body) private var deleteWidth = 64
    let exercises: [Item]
    let memory: ReorderListMemory
    let reveal: ReorderMemberReveal
    let remove: (UUID) -> Void

    var body: some View {
        let revealedHere = exercises.contains { $0.id == reveal.id }
        SupersetRail(count: exercises.count, spacing: 12, reachesIntoMargin: false, balancesLabel: true) {
            ForEach(exercises) { exercise in
                let isRevealed = reveal.id == exercise.id
                HStack(spacing: 5.5) {
                    Button {
                        reveal.id = isRevealed ? nil : exercise.id
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .red)
                            .rotationEffect(.degrees(isRevealed ? -90 : 0))
                            .frame(width: removeColumnWidth)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Remove \(exercise.name)")
                    .accessibilityIdentifier("ReorderRemoveSupersetMember-\(exercise.id.uuidString)")

                    ReorderExerciseRow(exercise: exercise, memory: memory, keepsRestingLines: isRevealed)

                    if isRevealed {
                        Button {
                            reveal.id = nil
                            remove(exercise.id)
                        } label: {
                            Image(systemName: "trash.fill")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: min(deleteWidth, 80))
                                .frame(maxHeight: .infinity)
                                .background(.red, in: RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)
                        .padding(.leading, 6)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .accessibilityLabel("Delete \(exercise.name)")
                        .accessibilityIdentifier("ReorderConfirmRemoveSupersetMember-\(exercise.id.uuidString)")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(.dragPreview, Rectangle())
        .contentShape(.interaction, Rectangle())
        // Buttons keep their taps; a tap anywhere else in the row closes its Delete.
        .gesture(TapGesture().onEnded { reveal.id = nil }, including: revealedHere ? .all : .subviews)
        .animation(.snappy(duration: 0.3), value: reveal.id)
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
