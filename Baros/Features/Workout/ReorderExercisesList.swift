import BarosCore
import SwiftUI
import UIKit

/// The edit list, with no modes. Every exercise is a card with its own grip; a
/// superset is one outlined container whose label carries a grip for the whole
/// block. Between every two neighbors sits a link joint: tap it to join or split
/// them. Swipe a card left to remove it. Add and Undo stay pinned at the bottom.
///
/// Dragging is drawn here rather than by a system list, which can't move part of a
/// row or a group of rows. The lifted card floats over an empty slot that shows
/// where it will land, and a superset outline wraps the slot when it would join one.
/// Where the list measures its rows, inside the scrolled content.
private let reorderContentSpace = "ReorderExercisesContent"

struct ReorderExercisesList<Item: ReorderListExercise, Header: View>: View {
    private static var gap: CGFloat { 12 }
    private static var headerHeight: CGFloat { 44 }
    /// A superset's first member tucks up under its label, into its own top padding.
    private static var labelTuck: CGFloat { -10 }

    let exercises: [Item]
    /// Takes the new order and the superset ids in that order.
    let rearrange: ([UUID], [UUID?]) -> Void
    let remove: (UUID) -> Void
    let add: () -> Void
    /// Undoes the last edit; nil when there is nothing to undo.
    let undo: (() -> Void)?
    @Binding var notice: ReorderNotice?
    /// What Save will delete, shown for as long as the draft holds that loss.
    let warning: String?
    /// Above the exercises, such as a template's name.
    let header: Header

    @State private var drag: Drag?
    @State private var frames: [Part: CGRect] = [:]
    @State private var openSwipe: UUID?
    @State private var scrollHandle = ReorderScrollHandle()
    @State private var scroll = ScrollMetrics()
    @State private var removals = 0
    /// How far to scroll once a link's label has come or gone above the tapped joint.
    @State private var pendingShift: CGFloat = 0
    @State private var slotChanges = 0

    init(
        exercises: [Item],
        rearrange: @escaping ([UUID], [UUID?]) -> Void,
        remove: @escaping (UUID) -> Void,
        add: @escaping () -> Void,
        undo: (() -> Void)?,
        notice: Binding<ReorderNotice?>,
        warning: String? = nil,
        @ViewBuilder header: () -> Header
    ) {
        self.exercises = exercises
        self.rearrange = rearrange
        self.remove = remove
        self.add = add
        self.undo = undo
        _notice = notice
        self.warning = warning
        self.header = header()
    }

    // MARK: Model

    struct Row: Identifiable {
        let item: Item
        let group: UUID?
        var id: UUID { item.id }
    }

    private typealias Block = SupersetGrouping.Block<Row>

    private enum Part: Hashable {
        case header(UUID), exercise(UUID)
    }

    private enum Subject: Equatable {
        /// An exercise, by id.
        case exercise(UUID)
        /// A superset, by the id of its block.
        case block(UUID)
    }

    private struct Drag {
        let id = UUID()
        let subject: Subject
        let startRows: [Row]
        var rows: [Row]
        let startMinY: CGFloat
        let height: CGFloat
        let startScroll: CGFloat
        var translation: CGFloat = 0
        var fingerY: CGFloat
        var isSettling = false
    }

    private struct ScrollMetrics: Equatable {
        var offset: CGFloat = 0
        var contentHeight: CGFloat = 0
    }

    private enum Element: Identifiable {
        case header(Block)
        case exercise(Row, index: Int, block: Block)

        var id: Part {
            switch self {
            case let .header(block): .header(block.id)
            case let .exercise(row, _, _): .exercise(row.id)
            }
        }
    }

    private var rows: [Row] {
        drag?.rows ?? exercises.map { Row(item: $0, group: $0.supersetGroupID) }
    }

    private func elements(_ blocks: [Block]) -> [Element] {
        var elements: [Element] = []
        var index = 0
        for block in blocks {
            if block.isSuperset { elements.append(.header(block)) }
            for row in block.members {
                elements.append(.exercise(row, index: index, block: block))
                index += 1
            }
        }
        return elements
    }

    // MARK: Body

    var body: some View {
        let rows = rows
        let blocks = SupersetGrouping.blocks(rows, groupID: \.group)
        let elements = elements(blocks)
        ScrollView {
            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)
                ForEach(Array(elements.enumerated()), id: \.element.id) { position, element in
                    Group {
                        switch element {
                        case let .header(block):
                            headerRow(block)
                        case let .exercise(row, index, block):
                            exerciseRow(row, index: index, block: block, rows: rows)
                        }
                    }
                    .padding(.top, topSpacing(at: position, in: elements))
                    .padding(.horizontal, 16)
                }
            }
            .padding(.top, 8)
            .background(alignment: .topLeading) { surfaces(blocks) }
            .overlay(alignment: .topLeading) {
                joints(rows, elements: elements)
                floating(blocks)
            }
            .coordinateSpace(.named(reorderContentSpace))
            .background(ReorderScrollFinder(handle: scrollHandle))
        }
        .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
            ScrollMetrics(
                offset: geometry.contentOffset.y + geometry.contentInsets.top,
                contentHeight: geometry.contentSize.height
            )
        } action: { old, metrics in
            scroll = metrics
            // Set during this layout, before it draws, so the tapped joint never moves.
            if pendingShift != 0, metrics.contentHeight != old.contentHeight {
                scrollHandle.scroll(by: pendingShift, clampingToEnd: false)
                pendingShift = 0
            }
            if drag != nil { updateSlot() }
        }
        .onScrollPhaseChange { _, phase in
            if phase != .idle, drag == nil { openSwipe = nil }
        }
        // On the scroll view alone, so it doesn't replace the identifiers of the bar's buttons.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ReorderExercisesList")
        // A safe-area bar, as on the workout screen: the hard scroll edge gives the warning,
        // Undo and Add a solid backing, so rows scrolling beneath never run through them.
        .scrollEdgeEffectStyle(.hard, for: [.top, .bottom])
        .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
        .task(id: drag?.id) { await autoscroll() }
        .sensoryFeedback(.impact(weight: .light), trigger: removals)
        .sensoryFeedback(.selection, trigger: slotChanges)
        .sensoryFeedback(trigger: drag?.id) { old, new in
            new != nil ? .impact(weight: .medium) : old != nil ? .impact(weight: .light) : nil
        }
        #if DEBUG
        .overlay(alignment: .bottomLeading) {
            if ProcessInfo.processInfo.arguments.contains("--uitest-reorder-stability-probe") {
                Text("Reorder probe")
                    .font(.system(size: 8))
                    .opacity(0.02)
                    .accessibilityIdentifier("ReorderStabilityProbe")
                    .accessibilityValue(String(slotChanges))
            }
        }
        #endif
    }

    /// 12pt between cards and blocks; a superset's first member tucks up under its label.
    private func topSpacing(at position: Int, in elements: [Element]) -> CGFloat {
        guard position > 0 else { return 0 }
        // Into the member's own top padding, so the label reads as the block's title.
        if case .exercise = elements[position], case .header = elements[position - 1] { return Self.labelTuck }
        return Self.gap
    }

    // MARK: Rows

    private func headerRow(_ block: Block) -> some View {
        let isLifted = drag?.subject == .block(block.id)
        return HStack(spacing: 0) {
            SupersetContainerHeader(count: block.members.count)
            // In the label's accent, so it reads as the whole superset's handle.
            ReorderGrip(height: Self.headerHeight, color: AppTheme.brandAccentForeground)
                .gesture(dragGesture(.block(block.id)), including: drag?.isSettling == true ? .none : .all)
                .accessibilityHidden(true)
        }
        .padding(.trailing, 2)
        .frame(height: Self.headerHeight)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Superset of \(block.members.count) exercises")
        .accessibilityIdentifier("SupersetLabel")
        .accessibilityAction(named: "Move Superset Up") { moveBlock(block, by: -1) }
        .accessibilityAction(named: "Move Superset Down") { moveBlock(block, by: 1) }
        .opacity(isLifted ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(reorderContentSpace)) } action: { frames[.header(block.id)] = $0 }
    }

    private func exerciseRow(_ row: Row, index: Int, block: Block, rows: [Row]) -> some View {
        let isMember = block.isSuperset
        let isLifted = drag?.subject == .exercise(row.id) || drag?.subject == .block(block.id)
        return card(row, showsSurface: !isMember, interactive: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(row.item.name)
            .accessibilityValue(row.item.accessibilityValue)
            .accessibilityIdentifier("ReorderExerciseRow-\(row.id.uuidString)")
            .accessibilityAction(named: "Move Up") { moveExercise(at: index, by: -1) }
            .accessibilityAction(named: "Move Down") { moveExercise(at: index, by: 1) }
            .accessibilityAction(named: "Remove") { removeRow(row) }
            .modifier(SwipeToRemove(
                id: row.id, openID: $openSwipe, isEnabled: drag == nil, name: row.item.name,
                cornerRadius: isMember ? 14 : ReorderExerciseRow.cornerRadius,
                inset: isMember ? 6 : 0,
                remove: { removeRow(row) }
            ))
            .opacity(isLifted ? 0 : 1)
            .background {
                if drag?.subject == .exercise(row.id), !isMember { placeholder }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(reorderContentSpace)) } action: { frames[.exercise(row.id)] = $0 }
    }

    /// A card's content and grip. In a superset, the container draws the surface.
    private func card(_ row: Row, showsSurface: Bool, interactive: Bool) -> some View {
        ReorderCardContent(exercise: row.item) {
            ReorderGrip()
                .gesture(dragGesture(.exercise(row.id)), including: interactive && drag?.isSettling != true ? .all : .none)
                .accessibilityHidden(true)
        }
        .background {
            if showsSurface { ReorderCardSurface(isNew: row.item.isNew) }
        }
        // A member draws no surface of its own, so its blank space still takes swipes.
        .contentShape(Rectangle())
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
            .strokeBorder(AppTheme.subtleBorder, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
    }

    // MARK: Layers

    /// Superset containers and their hairlines, drawn behind the members.
    @ViewBuilder
    private func surfaces(_ blocks: [Block]) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(blocks.filter(\.isSuperset)) { block in
                let members = block.members.compactMap { frames[.exercise($0.id)] }
                if let first = members.first {
                    let rect = members.reduce(frames[.header(block.id)] ?? first) { $0.union($1) }
                    if drag?.subject == .block(block.id) {
                        placeholder.frame(width: rect.width, height: rect.height).offset(x: rect.minX, y: rect.minY)
                    } else {
                        SupersetContainerSurface()
                            .frame(width: rect.width, height: rect.height)
                            .offset(x: rect.minX, y: rect.minY)
                        ForEach(Array(zip(members, members.dropFirst()).enumerated()), id: \.offset) { _, pair in
                            SupersetMemberDivider()
                                .frame(width: rect.width)
                                .offset(x: rect.minX, y: (pair.0.maxY + pair.1.minY) / 2)
                        }
                    }
                }
            }
        }
    }

    /// A joint between every two neighbors, centered in the space between them.
    @ViewBuilder
    private func joints(_ rows: [Row], elements: [Element]) -> some View {
        if drag == nil {
            let groups = rows.map(\.group)
            ZStack(alignment: .topLeading) {
                ForEach(Array(rows.indices.dropLast()), id: \.self) { upper in
                    let lowerPart = elements.firstIndex { $0.id == .exercise(rows[upper].id) }.map { elements[$0 + 1].id }
                    if let top = frames[.exercise(rows[upper].id)], let lowerPart, let bottom = frames[lowerPart] {
                        joint(below: upper, rows: rows, isLinked: SupersetGrouping.areGrouped(groups, upper, upper + 1))
                            .offset(x: top.midX - 32, y: (top.maxY + bottom.minY) / 2 - 22)
                    }
                }
            }
            .transition(.opacity)
        }
    }

    private func joint(below upper: Int, rows: [Row], isLinked: Bool) -> some View {
        let names = "\(rows[upper].item.name) and \(rows[upper + 1].item.name)"
        return Button {
            toggleLink(below: upper, rows: rows)
        } label: {
            // Unlinked shows what a tap does; linked, the link it would undo.
            Image(systemName: isLinked ? "link" : "link.badge.plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isLinked ? AppTheme.onBrandAccent : ReorderGrip.color)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 26, height: 26)
                .background(isLinked ? AppTheme.brandAccentFill : AppTheme.groupedSurface, in: Circle())
                .overlay(Circle().strokeBorder(isLinked ? Color.clear : ReorderGrip.color.opacity(0.45), lineWidth: 1))
                .frame(width: 64, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLinked ? "Unlink \(names)" : "Link \(names)")
        .accessibilityAddTraits(isLinked ? .isSelected : [])
        .accessibilityIdentifier("SupersetLinkButton-\(upper)")
    }

    /// The lifted exercise or superset, following the finger.
    @ViewBuilder
    private func floating(_ blocks: [Block]) -> some View {
        if let drag {
            let slot = subjectFrame(drag.subject, blocks: blocks) ?? .zero
            let minY = drag.isSettling ? slot.minY : currentMinY(drag)
            let x = slot.minX
            let width = slot.width
            Group {
                switch drag.subject {
                case let .exercise(id):
                    if let row = drag.rows.first(where: { $0.id == id }) {
                        card(row, showsSurface: true, interactive: false)
                    }
                case let .block(id):
                    if let block = blocks.first(where: { $0.id == id }) {
                        VStack(spacing: 0) {
                            HStack(spacing: 0) {
                                SupersetContainerHeader(count: block.members.count)
                                ReorderGrip(height: Self.headerHeight, color: AppTheme.brandAccentForeground)
                            }
                            .padding(.trailing, 2)
                            .frame(height: Self.headerHeight)
                            ForEach(Array(block.members.enumerated()), id: \.element.id) { index, member in
                                if index > 0 { SupersetMemberDivider().frame(height: Self.gap) }
                                card(member, showsSurface: false, interactive: false)
                            }
                        }
                        .background(SupersetContainerSurface())
                    }
                }
            }
            .frame(width: width)
            .scaleEffect(drag.isSettling ? 1 : 1.03)
            .shadow(color: .black.opacity(drag.isSettling ? 0 : 0.22), radius: 18, y: 8)
            .offset(x: x, y: minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            ReorderNoticeToast(notice: $notice)
            if let warning {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(AppTheme.destructiveForeground)
                        .symbolEffect(.bounce, value: warning)
                    Text(warning)
                        .foregroundStyle(AppTheme.textPrimary)
                }
                    .font(.footnote.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("ReorderPendingLoss")
                    .transition(.opacity)
            }
            // As text grows, Undo drops its title. Like a system bar, the buttons stop growing
            // at accessibility2, where one row still fits; Add wraps only if a narrower screen
            // still runs short, so it never runs past the bar's edge.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { barButtons(undoTitle: true) }
                HStack(spacing: 10) { barButtons(undoTitle: false) }
                HStack(spacing: 10) { barButtons(undoTitle: false, addWraps: true) }
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(AppTheme.canvasBackground.ignoresSafeArea(edges: .bottom))
    }

    @ViewBuilder
    private func barButtons(undoTitle: Bool, addWraps: Bool = false) -> some View {
        Button {
            openSwipe = nil
            undo?()
        } label: {
            Label("Undo", systemImage: "arrow.uturn.backward")
                .labelStyle(UndoLabelStyle(showsTitle: undoTitle))
                .font(.headline)
                // Dimmed, but still plainly a button that will do something once there's an edit.
                .foregroundStyle(undo == nil ? AppTheme.textSecondary.opacity(0.55) : AppTheme.brandAccentForeground)
                .fixedSize()
                .padding(.horizontal, undoTitle ? 20 : 16)
                .frame(minWidth: undoTitle ? 108 : 56, minHeight: 50)
                .glassEffect(.regular.interactive(), in: Capsule())
                .overlay {
                    if undo == nil { Capsule().strokeBorder(Color(uiColor: .separator), lineWidth: 1) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(undo == nil)
        .accessibilityLabel("Undo")
        .accessibilityIdentifier("ReorderUndoButton")

        Button(action: add) {
            Label("Add Exercises", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(AppTheme.brandAccentForeground)
                // Keeps one line until the bar runs short; then it wraps and grows taller
                // rather than running past the bar's edge.
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: !addWraps, vertical: true)
                .padding(.horizontal, addWraps ? 16 : 0)
                .padding(.vertical, addWraps ? 10 : 0)
                .frame(maxWidth: .infinity, minHeight: 50)
                .glassEffect(.regular.tint(AppTheme.brandAccentMuted).interactive(), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("EditWorkoutAddExercisesButton")
    }

    // MARK: Editing

    private func removeRow(_ row: Row) {
        openSwipe = nil
        removals += 1
        withAnimation(.snappy(duration: 0.3)) { remove(row.id) }
    }

    private func commit(_ rows: [Row]) {
        rearrange(rows.map(\.id), rows.map(\.group))
    }

    private func apply(_ arrangement: SupersetGrouping.Arrangement, to rows: [Row]) -> [Row] {
        arrangement.order.enumerated().map { Row(item: rows[$1].item, group: arrangement.groupIDs[$0]) }
    }

    private func moveExercise(at index: Int, by step: Int) {
        let rows = rows
        guard rows.indices.contains(index + step) else { return }
        let moved = SupersetGrouping.movingExercise(rows.map(\.group), from: index, to: index + step)
        withAnimation(.snappy) { commit(apply(moved, to: rows)) }
    }

    private func moveBlock(_ block: Block, by step: Int) {
        let rows = rows
        let blocks = SupersetGrouping.blocks(rows, groupID: \.group)
        guard let source = blocks.firstIndex(where: { $0.id == block.id }), blocks.indices.contains(source + step) else { return }
        let moved = SupersetGrouping.movingBlock(rows.map(\.group), from: source, to: source + step)
        withAnimation(.snappy) { commit(apply(moved, to: rows)) }
    }

    /// Joins or splits two neighbors. A superset's label can come or go above the
    /// tapped joint; the scroll moves with it, so the joint stays under the finger.
    private func toggleLink(below upper: Int, rows: [Row]) {
        let groups = rows.map(\.group)
        let wasLinked = SupersetGrouping.areGrouped(groups, upper, upper + 1)
        let joinsAbove = SupersetGrouping.areGrouped(groups, upper, upper - 1)
        // A label adds its height, less the tuck, in place of the gap above the card.
        let labelSpace = Self.headerHeight + Self.labelTuck
        let shift: CGFloat = switch (wasLinked, joinsAbove) {
        case (false, false): labelSpace
        case (true, false): -labelSpace
        default: 0
        }
        let toggled = SupersetGrouping.togglingLink(groups, below: upper)
        // Applied once the content reports its new height, so the scroll isn't held to
        // the old content's end.
        // With a label coming or going above, the change is instant: animating it while the
        // scroll makes up for it would wobble the joint.
        if shift != 0, scroll.offset > 0 {
            pendingShift = shift
            rearrange(rows.map(\.id), toggled)
        } else {
            withAnimation(.snappy) { rearrange(rows.map(\.id), toggled) }
        }
    }

    // MARK: Dragging

    private func dragGesture(_ subject: Subject) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                if drag == nil { begin(subject, fingerY: value.startLocation.y) }
                guard drag?.subject == subject, drag?.isSettling == false else { return }
                drag?.translation = value.translation.height
                drag?.fingerY = value.location.y
                updateSlot()
            }
            .onEnded { _ in finish() }
    }

    private func begin(_ subject: Subject, fingerY: CGFloat) {
        let rows = rows
        let blocks = SupersetGrouping.blocks(rows, groupID: \.group)
        guard let frame = subjectFrame(subject, blocks: blocks) else { return }
        openSwipe = nil
        drag = Drag(
            subject: subject, startRows: rows, rows: rows, startMinY: frame.minY, height: frame.height,
            startScroll: scroll.offset, fingerY: fingerY
        )
    }

    private func currentMinY(_ drag: Drag) -> CGFloat {
        drag.startMinY + drag.translation + (scroll.offset - drag.startScroll)
    }

    private func subjectFrame(_ subject: Subject, blocks: [Block]) -> CGRect? {
        switch subject {
        case let .exercise(id):
            return frames[.exercise(id)]
        case let .block(id):
            guard let block = blocks.first(where: { $0.id == id }) else { return nil }
            return blockFrame(block)
        }
    }

    private func blockFrame(_ block: Block) -> CGRect? {
        let parts = (block.isSuperset ? [Part.header(block.id)] : []) + block.members.map { Part.exercise($0.id) }
        let rects = parts.compactMap { frames[$0] }
        guard let first = rects.first else { return nil }
        return rects.reduce(first) { $0.union($1) }
    }

    /// Moves the lifted exercise or superset to the slot under its center. Others are
    /// measured where they now sit, so a slot holds until the center clearly passes one.
    private func updateSlot() {
        guard let drag, !drag.isSettling else { return }
        let center = currentMinY(drag) + drag.height / 2
        let start = drag.startRows
        let groups = start.map(\.group)
        let arrangement: SupersetGrouping.Arrangement
        switch drag.subject {
        case let .exercise(id):
            guard let source = start.firstIndex(where: { $0.id == id }) else { return }
            let others = start.filter { $0.id != id }
            let destination = others.filter { (frames[.exercise($0.id)]?.midY ?? .infinity) < center }.count
            // At either end there's no row to pass, so clearing the last card's edge leaves.
            let pastEnd = destination == others.count && center > (others.last.flatMap { frames[.exercise($0.id)] }?.maxY ?? .infinity)
            let pastStart = destination == 0 && center < (others.first.flatMap { frames[.exercise($0.id)] }?.minY ?? -.infinity)
            arrangement = SupersetGrouping.movingExercise(
                groups, from: source, to: destination, leavesSuperset: pastEnd || pastStart
            )
        case let .block(id):
            let blocks = SupersetGrouping.blocks(start, groupID: \.group)
            guard let source = blocks.firstIndex(where: { $0.id == id }) else { return }
            let destination = blocks.filter { $0.id != id }
                .filter { (blockFrame($0)?.midY ?? .infinity) < center }.count
            arrangement = SupersetGrouping.movingBlock(groups, from: source, to: destination)
        }
        let moved = apply(arrangement, to: start)
        guard moved.map(\.id) != drag.rows.map(\.id) || moved.map(\.group) != drag.rows.map(\.group) else { return }
        slotChanges += 1
        withAnimation(.snappy(duration: 0.25)) { self.drag?.rows = moved }
    }

    private func finish() {
        guard let drag, !drag.isSettling else { return }
        let start = drag.startRows
        let changed = drag.rows.map(\.id) != start.map(\.id)
            || !SupersetGrouping.sameSupersets(drag.rows.map(\.group), start.map(\.group))
        if changed { commit(drag.rows) }
        withAnimation(.snappy(duration: 0.22)) { self.drag?.isSettling = true }
        let id = drag.id
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            if self.drag?.id == id { self.drag = nil }
        }
    }

    /// Scrolls while the finger rests near the top or bottom edge, faster the closer it is.
    private func autoscroll() async {
        while !Task.isCancelled, let drag, !drag.isSettling {
            try? await Task.sleep(for: .milliseconds(16))
            guard let visible = scrollHandle.visibleFrame else { continue }
            let zone: CGFloat = 80
            var delta: CGFloat = 0
            if drag.fingerY < visible.minY + zone {
                delta = -min(1, (visible.minY + zone - drag.fingerY) / zone) * 14
            } else if drag.fingerY > visible.maxY - zone {
                delta = min(1, (drag.fingerY - (visible.maxY - zone)) / zone) * 14
            }
            if delta != 0 { scrollHandle.scroll(by: delta) }
        }
    }
}

extension ReorderExercisesList where Header == EmptyView {
    init(
        exercises: [Item],
        rearrange: @escaping ([UUID], [UUID?]) -> Void,
        remove: @escaping (UUID) -> Void,
        add: @escaping () -> Void,
        undo: (() -> Void)?,
        notice: Binding<ReorderNotice?>,
        warning: String? = nil
    ) {
        self.init(
            exercises: exercises, rearrange: rearrange, remove: remove, add: add, undo: undo, notice: notice,
            warning: warning
        ) { EmptyView() }
    }
}

/// The scroll view around the list. SwiftUI's scroll position can't move it in the
/// middle of a layout, which is when a link's label changes the content above.
@MainActor final class ReorderScrollHandle {
    weak var scrollView: UIScrollView?

    /// What the list shows between its bars, in window coordinates.
    var visibleFrame: CGRect? {
        guard let scrollView else { return nil }
        return scrollView.convert(scrollView.bounds, to: nil).inset(by: scrollView.adjustedContentInset)
    }

    /// Keeps to the content's ends. Making up for content that just grew skips the far
    /// end, since the scroll view hasn't been told the new size yet.
    func scroll(by delta: CGFloat, clampingToEnd: Bool = true) {
        guard let scrollView else { return }
        let insets = scrollView.adjustedContentInset
        let lowest = -insets.top
        let highest = max(lowest, scrollView.contentSize.height + insets.bottom - scrollView.bounds.height)
        let target = max(scrollView.contentOffset.y + delta, lowest)
        scrollView.contentOffset.y = clampingToEnd ? min(target, highest) : target
    }
}

/// Finds the scroll view its content sits in, for `ReorderScrollHandle`.
private struct ReorderScrollFinder: UIViewRepresentable {
    let handle: ReorderScrollHandle

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        guard handle.scrollView == nil else { return }
        DispatchQueue.main.async { [weak view] in
            var ancestor = view?.superview
            while let current = ancestor, !(current is UIScrollView) { ancestor = current.superview }
            handle.scrollView = ancestor as? UIScrollView
        }
    }
}

/// A card's text and grip. While Remove is swiped open, the text narrows to the space
/// beside it, wrapping as it needs to, and the grip fades as Remove reaches it.
private struct ReorderCardContent<Grip: View>: View {
    @Environment(\.swipeRemoveReveal) private var reveal
    let exercise: any ReorderListExercise
    @ViewBuilder let grip: Grip

    var body: some View {
        HStack(spacing: 0) {
            ReorderExerciseRow(exercise: exercise)
            grip.opacity(1 - min(1, reveal / 40))
        }
        .padding(.trailing, 2)
        // Room for Remove with a gap, less the grip's space it takes over.
        .padding(.trailing, max(0, reveal - 40))
    }
}

/// Undo's title, or its icon alone when the bar runs short of room.
private struct UndoLabelStyle: LabelStyle {
    let showsTitle: Bool

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon
            if showsTitle { configuration.title }
        }
    }
}
