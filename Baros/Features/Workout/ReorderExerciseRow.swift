import SwiftUI

/// A stock edit-mode List, so the system owns the minus, Delete, and reorder
/// grip along with their motion and accessibility.
struct ReorderExercisesList: View {
    let exercises: [WorkoutExerciseListSnapshot.ExerciseState]
    let reorder: ([UUID]) -> Void
    let remove: (Set<UUID>) -> Void
    var add: () -> Void = {}

    var body: some View {
        List {
            ForEach(exercises) { exercise in
                ReorderExerciseRow(exercise: exercise)
                    // Lifts only the card while dragging, not the whole row rectangle.
                    .contentShape(
                        .dragPreview,
                        RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous)
                    )
                    .listRowInsets(EdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            .onMove { source, destination in
                var ids = exercises.map(\.id)
                ids.move(fromOffsets: source, toOffset: destination)
                reorder(ids)
            }
            .onDelete { offsets in
                remove(Set(offsets.map { exercises[$0].id }))
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

struct ReorderExerciseRow: View {
    static let cornerRadius: CGFloat = 20
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var titleSize = 16
    @ScaledMetric(relativeTo: .subheadline) private var detailSize = 13
    let exercise: WorkoutExerciseListSnapshot.ExerciseState

    var body: some View {
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

    private var progress: some View {
        detail(exercise.isNew ? "New · \(exercise.progressText)" : exercise.progressText)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }
}

// MARK: - PROTOTYPE: creating supersets in Edit Workout (#340). Throwaway, never merge.
// Grouping lives in memory only; nothing here touches the model or sync. Launch with
// `--uitest-seed-long-name-active-workout` to get a single, a pair and a trio.

@MainActor @Observable
final class EditSheetSupersetPrototype {
    static let shared = EditSheetSupersetPrototype()

    enum Variant: String, CaseIterable {
        case select = "C"
        case linkMode = "D"

        var name: String {
            switch self {
            case .select: "Select"
            case .linkMode: "Link mode"
            }
        }
    }

    private static let variantKey = "EditSheetSupersetPrototype.variant"

    var variant: Variant {
        didSet { UserDefaults.standard.set(variant.rawValue, forKey: Self.variantKey) }
    }
    /// The workout's grouping after Done.
    var committed: [UUID: UUID] = [:]
    private var didSeed = false

    private init() {
        variant = UserDefaults.standard.string(forKey: Self.variantKey)
            .flatMap(Variant.init(rawValue:)) ?? .select
    }

    func cycle(_ step: Int) {
        let all = Variant.allCases
        let index = all.firstIndex(of: variant) ?? 0
        variant = all[(index + step + all.count) % all.count]
    }

    func seedIfNeeded(_ ids: [UUID]) {
        guard !didSeed, ids.count >= 6,
              ProcessInfo.processInfo.arguments.contains("--uitest-seed-long-name-active-workout") else { return }
        // Exercise 1 alone, 2–3 as a pair, 4–6 as a giant set.
        didSeed = true
        let pair = UUID(), trio = UUID()
        committed[ids[1]] = pair
        committed[ids[2]] = pair
        for id in ids[3...5] { committed[id] = trio }
    }

    struct Block: Identifiable {
        let id: UUID
        let members: [(index: Int, exercise: LoggedExercise)]
    }

    func blocks(for exercises: [LoggedExercise]) -> [Block] {
        var blocks: [Block] = []
        var index = 0
        while index < exercises.count {
            var end = index
            if let group = committed[exercises[index].id] {
                while end + 1 < exercises.count, committed[exercises[end + 1].id] == group { end += 1 }
            }
            blocks.append(Block(id: exercises[index].id, members: (index...end).map { ($0, exercises[$0]) }))
            index = end + 1
        }
        return blocks
    }
}

/// Grouping edits on the draft's ordered ids.
struct SupersetPrototypeGrouping: Equatable {
    var order: [UUID]
    var groups: [UUID: UUID]

    enum Position { case none, first, middle, last }

    func position(of id: UUID) -> Position {
        guard let index = order.firstIndex(of: id), let group = groups[id] else { return .none }
        let above = index > 0 && groups[order[index - 1]] == group
        let below = index + 1 < order.count && groups[order[index + 1]] == group
        switch (above, below) {
        case (false, true): return .first
        case (true, true): return .middle
        case (true, false): return .last
        case (false, false): return .none
        }
    }

    func memberCount(of id: UUID) -> Int {
        guard let group = groups[id] else { return 1 }
        return order.filter { groups[$0] == group }.count
    }

    func sameGroup(_ a: UUID, _ b: UUID) -> Bool {
        guard let group = groups[a] else { return false }
        return groups[b] == group
    }

    func neighbor(of id: UUID, _ offset: Int) -> UUID? {
        guard let index = order.firstIndex(of: id), order.indices.contains(index + offset) else { return nil }
        return order[index + offset]
    }

    func canJoinPrevious(_ id: UUID) -> Bool { neighbor(of: id, -1).map { !sameGroup(id, $0) } ?? false }
    func canStartWithNext(_ id: UUID) -> Bool { neighbor(of: id, 1).map { !sameGroup(id, $0) } ?? false }
    func isGrouped(_ id: UUID) -> Bool { groups[id] != nil }

    mutating func link(_ a: UUID, _ b: UUID) {
        let group = groups[a] ?? groups[b] ?? UUID()
        if let absorbed = groups[b], absorbed != group {
            for (id, existing) in groups where existing == absorbed { groups[id] = group }
        }
        groups[a] = group
        groups[b] = group
        normalize()
    }

    /// Splits the group between this exercise and the one above it.
    mutating func unlinkAbove(_ id: UUID) {
        guard let index = order.firstIndex(of: id), let group = groups[id] else { return }
        let fresh = UUID()
        var i = index
        while i < order.count, groups[order[i]] == group {
            groups[order[i]] = fresh
            i += 1
        }
        normalize()
    }

    mutating func remove(_ id: UUID) {
        groups[id] = nil
        normalize()
    }

    /// Pulls the selection together where the first one sits, as one new group.
    mutating func group(_ selection: Set<UUID>) {
        let selected = order.filter(selection.contains)
        guard selected.count >= 2, let first = order.firstIndex(of: selected[0]) else { return }
        var rest = order.filter { !selection.contains($0) }
        let insertAt = order[..<first].filter { !selection.contains($0) }.count
        rest.insert(contentsOf: selected, at: insertAt)
        order = rest
        let fresh = UUID()
        for id in selected { groups[id] = fresh }
        normalize()
    }

    mutating func ungroup(_ selection: Set<UUID>) {
        for id in selection { groups[id] = nil }
        normalize()
    }

    /// Moves a grouped row's whole superset, and never drops a row inside another group.
    mutating func move(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        let moved = order[from]
        let block: [UUID] = groups[moved].map { group in order.filter { groups[$0] == group } } ?? [moved]
        var target = destination
        // Inside another group: land after it.
        while target > 0, target < order.count,
              let group = groups[order[target]], groups[order[target - 1]] == group,
              !block.contains(order[target]) {
            target += 1
        }
        let before = order[..<min(target, order.count)].filter(block.contains).count
        var rest = order.filter { !block.contains($0) }
        rest.insert(contentsOf: block, at: max(0, min(rest.count, target - before)))
        order = rest
        normalize()
    }

    mutating func removeExercises(_ ids: Set<UUID>) {
        order.removeAll(where: ids.contains)
        for id in ids { groups[id] = nil }
        normalize()
    }

    mutating func groupTrailing(_ count: Int) {
        guard count >= 2 else { return }
        let fresh = UUID()
        for id in order.suffix(count) { groups[id] = fresh }
        normalize()
    }

    /// Splits a group broken into separate runs and drops runs of one.
    mutating func normalize() {
        groups = groups.filter { order.contains($0.key) }
        var seen: Set<UUID> = []
        var index = 0
        while index < order.count {
            guard let group = groups[order[index]] else { index += 1; continue }
            var end = index
            while end + 1 < order.count, groups[order[end + 1]] == group { end += 1 }
            if end == index {
                groups[order[index]] = nil
            } else if seen.contains(group) {
                let fresh = UUID()
                for i in index...end { groups[order[i]] = fresh }
            } else {
                seen.insert(group)
            }
            index = end + 1
        }
    }
}

struct EditSheetSupersetSwitcher: View {
    var body: some View {
        let prototype = EditSheetSupersetPrototype.shared
        HStack(spacing: 14) {
            Button { withAnimation(.snappy) { prototype.cycle(-1) } } label: {
                Image(systemName: "chevron.left")
            }
            Text("\(prototype.variant.rawValue) · \(prototype.variant.name)")
                .monospacedDigit()
            Button { withAnimation(.snappy) { prototype.cycle(1) } } label: {
                Image(systemName: "chevron.right")
            }
        }
        .font(.footnote.weight(.bold))
        .foregroundStyle(.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.yellow, in: Capsule())
        .buttonStyle(.plain)
        .accessibilityIdentifier("EditSheetSupersetSwitcher")
    }
}

struct SupersetPrototypeRailLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
            Text("SUPERSET")
                .tracking(1.2)
            Text("· \(count)")
                .foregroundStyle(AppTheme.brandAccentForeground.opacity(0.7))
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(AppTheme.brandAccentForeground)
    }
}

/// One Edit Workout row: the existing card plus the rail, and link chips while linking.
struct SupersetPrototypeSheetRow: View {
    let exercise: WorkoutExerciseListSnapshot.ExerciseState
    let index: Int
    let showsJoints: Bool
    @Binding var grouping: SupersetPrototypeGrouping

    private static let railWidth: CGFloat = 4
    private static let railGap: CGFloat = 6

    var body: some View {
        let position = grouping.position(of: exercise.id)
        let joinsAbove = position == .middle || position == .last
        let joinsBelow = position == .first || position == .middle
        VStack(alignment: .leading, spacing: 0) {
            piece(rail: joinsAbove) { Color.clear.frame(height: 6) }
            if showsJoints, index > 0 {
                piece(rail: joinsAbove) { joint(linked: joinsAbove) }
            }
            if position == .first {
                piece(rail: false) {
                    SupersetPrototypeRailLabel(count: grouping.memberCount(of: exercise.id))
                        .padding(.leading, 2)
                        .padding(.bottom, 6)
                }
            }
            railed(visible: position != .none, topCap: position == .first, bottomCap: position == .last) { card }
            piece(rail: joinsBelow) { Color.clear.frame(height: 6) }
        }
    }

    private var card: some View { ReorderExerciseRow(exercise: exercise) }

    private func joinPrevious(_ id: UUID) {
        guard let previous = grouping.neighbor(of: id, -1) else { return }
        grouping.link(previous, id)
    }

    private func joint(linked: Bool) -> some View {
        Button {
            withAnimation(.snappy) {
                if linked { grouping.unlinkAbove(exercise.id) } else { joinPrevious(exercise.id) }
            }
        } label: {
            Image(systemName: linked ? "link" : "link.badge.plus")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(linked ? AppTheme.brandAccentForeground : AppTheme.textTertiary)
                .frame(width: 48, height: 26)
                .background(linked ? AppTheme.brandAccentMuted : AppTheme.groupedSurface, in: Capsule())
                .overlay(Capsule().stroke(linked ? AppTheme.brandAccentForeground.opacity(0.5) : AppTheme.subtleBorder))
                .frame(maxWidth: .infinity, minHeight: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(linked ? "Unlink from previous exercise" : "Superset with previous exercise")
    }

    private func piece<Content: View>(rail: Bool, @ViewBuilder content: () -> Content) -> some View {
        railed(visible: rail, topCap: false, bottomCap: false) {
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A background takes the content's exact height, so the rail pieces meet.
    private func railed<Content: View>(
        visible: Bool, topCap: Bool, bottomCap: Bool, @ViewBuilder content: () -> Content
    ) -> some View {
        let radius = Self.railWidth / 2
        return content()
            .padding(.leading, Self.railWidth + Self.railGap)
            .background(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: topCap ? radius : 0,
                    bottomLeadingRadius: bottomCap ? radius : 0,
                    bottomTrailingRadius: bottomCap ? radius : 0,
                    topTrailingRadius: topCap ? radius : 0
                )
                .fill(visible ? AppTheme.brandAccentForeground : .clear)
                .frame(width: Self.railWidth)
            }
    }
}

/// The Edit Workout list with the prototype's grouping controls.
struct SupersetPrototypeReorderList: View {
    let exercises: [WorkoutExerciseListSnapshot.ExerciseState]
    @Binding var grouping: SupersetPrototypeGrouping
    var add: () -> Void = {}
    @State private var isSelecting = false
    @State private var isLinking = false
    @State private var selection: Set<UUID> = []

    var body: some View {
        let variant = EditSheetSupersetPrototype.shared.variant
        List(selection: isSelecting ? $selection : nil) {
            ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                SupersetPrototypeSheetRow(exercise: exercise, index: index, showsJoints: isLinking, grouping: $grouping)
                    .contentShape(.dragPreview, RoundedRectangle(cornerRadius: ReorderExerciseRow.cornerRadius, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 8))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .deleteDisabled(isSelecting || isLinking)
                    .tag(exercise.id)
            }
            .onMove { source, destination in
                withAnimation(.snappy) { grouping.move(from: source, to: destination) }
            }
            .onDelete { offsets in
                grouping.removeExercises(Set(offsets.map { exercises[$0].id }))
            }
            if !isSelecting && !isLinking {
                footer(variant: variant)
                    .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 12, trailing: 20))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .moveDisabled(true)
                    .deleteDisabled(true)
                    .selectionDisabled()
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.top, 8, for: .scrollContent)
        .environment(\.editMode, .constant(.active))
        .safeAreaBar(edge: .bottom, spacing: 0) {
            if isSelecting { selectionBar }
            if isLinking { linkBar }
        }
        .onChange(of: variant) { _, _ in
            isSelecting = false
            isLinking = false
            selection = []
        }
        .accessibilityIdentifier("ReorderExercisesList")
    }

    private func footer(variant: EditSheetSupersetPrototype.Variant) -> some View {
        HStack(spacing: 10) {
            Button(action: add) {
                Label("Add Exercises", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(AppTheme.brandAccentMuted, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("EditWorkoutAddExercisesButton")
            if exercises.count >= 2 {
                Button {
                    withAnimation(.snappy) {
                        if variant == .select { isSelecting = true } else { isLinking = true }
                    }
                } label: {
                    Label("Superset", systemImage: "link")
                        .font(.headline)
                        .foregroundStyle(AppTheme.brandAccentForeground)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(AppTheme.brandAccentMuted, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var linkBar: some View {
        VStack(spacing: 10) {
            Text("Tap a link to join or split exercises")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            Button {
                withAnimation(.snappy) { isLinking = false }
            } label: {
                Text("Done Linking")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(AppTheme.brandAccentFill)
            .font(.headline)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var selectionBar: some View {
        let canUngroup = selection.contains { grouping.isGrouped($0) }
        return VStack(spacing: 10) {
            Text(selection.count < 2 ? "Select exercises to superset" : "\(selection.count) selected")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            HStack(spacing: 10) {
                Button("Cancel") {
                    withAnimation(.snappy) { isSelecting = false; selection = [] }
                }
                .buttonStyle(.glass)
                if canUngroup {
                    Button("Ungroup") {
                        withAnimation(.snappy) {
                            grouping.ungroup(selection)
                            isSelecting = false
                            selection = []
                        }
                    }
                    .buttonStyle(.glass)
                }
                Button {
                    withAnimation(.snappy) {
                        grouping.group(selection)
                        isSelecting = false
                        selection = []
                    }
                } label: {
                    Text("Superset")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .tint(AppTheme.brandAccentFill)
                .disabled(selection.count < 2)
            }
            .font(.headline)
            .controlSize(.large)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// The approved side rail (#101 look B) around a group in the workout.
struct SupersetPrototypeSessionBlock<Content: View>: View {
    let count: Int
    @ViewBuilder let content: Content

    var body: some View {
        if count < 2 {
            content
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SupersetPrototypeRailLabel(count: count)
                    .padding(.leading, 12)
                HStack(spacing: 6) {
                    Capsule()
                        .fill(AppTheme.brandAccentForeground)
                        .frame(width: 4)
                    VStack(spacing: 14) { content }
                }
            }
            .padding(.leading, -10)
        }
    }
}
