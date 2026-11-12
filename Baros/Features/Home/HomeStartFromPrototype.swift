// PROTOTYPE (#313) — throwaway. Three variants of the Home Start-from pills for people who never
// name their workouts, switchable from a floating DEBUG-only bar on Home.
// Launch with `--prototype-seed-unnamed-workouts` (plus an in-memory store) for five unnamed workouts.
#if DEBUG
import SwiftData
import SwiftUI

enum StartFromPrototypeVariant: String, CaseIterable {
    case a = "A", b = "B", c = "C"

    static let storageKey = "prototype.startFromVariant"

    var name: String {
        switch self {
        case .a: "Two-line · muscle groups"
        case .b: "One-line · body regions"
        case .c: "Tiles · exercise names"
        }
    }
}

// MARK: - Labels

enum StartFromPrototypeLabel {
    static func isUnnamed(_ title: String) -> Bool {
        normalized(title) == normalized(WorkoutSession.defaultTitle)
    }

    /// Top two muscle groups by exercise count, ties broken by order in the workout.
    static func muscleGroups(_ session: WorkoutSession) -> String {
        if !isUnnamed(session.title) { return session.title }
        let groups = session.sortedLoggedExercises.compactMap { exercise -> String? in
            guard let raw = exercise.resolvedSnapshotPrimaryMuscleGroupRaw,
                  let group = ExerciseMuscleGroup(rawValue: raw), group != .other else { return nil }
            return group.displayName
        }
        return topTwo(groups) ?? fallback(session)
    }

    /// Same rule, rolled up to broad regions so a pull day reads "Back · Arms", not "Upper Back · Lats".
    static func regions(_ session: WorkoutSession) -> String {
        if !isUnnamed(session.title) { return session.title }
        let regions = session.sortedLoggedExercises.compactMap { exercise -> String? in
            guard let raw = exercise.resolvedSnapshotPrimaryMuscleGroupRaw,
                  let group = ExerciseMuscleGroup(rawValue: raw) else { return nil }
            return region(group)
        }
        return topTwo(regions) ?? fallback(session)
    }

    static func exerciseNames(_ session: WorkoutSession) -> String {
        let names = session.sortedLoggedExercises.map(\.exerciseSnapshotName)
        guard let first = names.first else { return session.title }
        return names.count > 1 ? "\(first) +\(names.count - 1)" : first
    }

    static func lastDone(_ session: WorkoutSession, now: Date = .now, calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: session.startedAt),
                                           to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return "Today"
        case 1: return "Yesterday"
        case 2...6: return "\(days) days ago"
        default: return session.startedAt.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private static func topTwo(_ items: [String]) -> String? {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for item in items {
            if counts[item] == nil { order.append(item) }
            counts[item, default: 0] += 1
        }
        let ranked = order.enumerated()
            .sorted { lhs, rhs in
                let (l, r) = (counts[lhs.element]!, counts[rhs.element]!)
                return l != r ? l > r : lhs.offset < rhs.offset
            }
            .map(\.element)
        guard !ranked.isEmpty else { return nil }
        return ranked.prefix(2).joined(separator: " · ")
    }

    private static func fallback(_ session: WorkoutSession) -> String {
        session.sortedLoggedExercises.first?.exerciseSnapshotName ?? session.title
    }

    private static func region(_ group: ExerciseMuscleGroup) -> String? {
        switch group {
        case .chest: "Chest"
        case .lats, .upperBack, .traps, .lowerBack: "Back"
        case .shoulders, .neck: "Shoulders"
        case .biceps, .triceps, .forearms: "Arms"
        case .quads, .hamstrings, .glutes, .calves, .abductors, .adductors, .lowerBody: "Legs"
        case .core: "Core"
        case .fullBody: "Full Body"
        case .upperBody: "Upper Body"
        case .cardio: "Cardio"
        case .other: nil
        }
    }

    private static func normalized(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
    }
}

// MARK: - Variants

struct StartFromPrototypePills: View {
    let variant: StartFromPrototypeVariant
    let workouts: [HomeQuickStartWorkout]
    let bleedsToScreenEdges: Bool
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start from")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(workouts.enumerated()), id: \.offset) { index, workout in
                        Button { select(index) } label: { label(workout.session) }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("HomeQuickStartButton-\(index)")
                    }
                }
            }
            .contentMargins(.horizontal, bleedsToScreenEdges ? HomeLayout.horizontalPadding : 0, for: .scrollContent)
            .padding(.horizontal, bleedsToScreenEdges ? -HomeLayout.horizontalPadding : 0)
        }
    }

    @ViewBuilder
    private func label(_ session: WorkoutSession) -> some View {
        switch variant {
        case .a:
            VStack(alignment: .leading, spacing: 1) {
                Text(StartFromPrototypeLabel.muscleGroups(session))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text(StartFromPrototypeLabel.lastDone(session))
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .lineLimit(1)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(AppTheme.groupedSurface, in: Capsule())
            .overlay { Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 0.6) }
        case .b:
            Text(StartFromPrototypeLabel.regions(session))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                .background(AppTheme.groupedSurface, in: Capsule())
                .overlay { Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 0.6) }
        case .c:
            VStack(alignment: .leading, spacing: 4) {
                Text(StartFromPrototypeLabel.exerciseNames(session))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text("\(session.visibleExerciseCount) exercises · \(StartFromPrototypeLabel.lastDone(session))")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 150, alignment: .leading)
            .padding(12)
            .background(AppTheme.groupedSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(AppTheme.subtleBorder, lineWidth: 0.6)
            }
        }
    }
}

// MARK: - Switcher

struct StartFromPrototypeSwitcher: View {
    @AppStorage(StartFromPrototypeVariant.storageKey) private var variantRaw = StartFromPrototypeVariant.a.rawValue

    var body: some View {
        let all = StartFromPrototypeVariant.allCases
        let current = StartFromPrototypeVariant(rawValue: variantRaw) ?? .a
        let index = all.firstIndex(of: current) ?? 0
        HStack(spacing: 14) {
            Button { variantRaw = all[(index + all.count - 1) % all.count].rawValue } label: {
                Image(systemName: "chevron.left")
            }
            Text("\(current.rawValue) — \(current.name)")
                .font(.footnote.weight(.semibold).monospaced())
            Button { variantRaw = all[(index + 1) % all.count].rawValue } label: {
                Image(systemName: "chevron.right")
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.black.opacity(0.85), in: Capsule())
        .shadow(radius: 6)
        .accessibilityIdentifier("StartFromPrototypeSwitcher")
    }
}

// MARK: - Seed

enum StartFromPrototypeSeed {
    static let argument = "--prototype-seed-unnamed-workouts"

    /// Five distinct workouts, none of them renamed — the reported case.
    static func seed(ownerTokenIdentifier: String?, context: ModelContext, now: Date = .now) throws {
        let library = Exercise.visibleActiveExercises(
            from: try context.fetch(FetchDescriptor<Exercise>()),
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        let plans: [(daysAgo: Int, seeds: [String])] = [
            (1, ["bench-press", "incline-dumbbell-press", "overhead-press", "triceps-pushdown"]),
            (3, ["conventional-deadlift", "barbell-row", "lat-pulldown", "biceps-curl"]),
            (4, ["back-squat", "romanian-deadlift", "leg-press", "calf-raise"]),
            (6, ["bench-press", "barbell-row", "overhead-press", "biceps-curl", "triceps-pushdown"]),
            (9, ["custom:Sled Push", "custom:Farmer's Carry"]),
        ]
        for (index, plan) in plans.enumerated() {
            guard let day = Calendar.current.date(byAdding: .day, value: -plan.daysAgo, to: now) else { continue }
            let startedAt = Calendar.current.date(bySettingHour: 7, minute: 30, second: 0, of: day) ?? day
            let endedAt = startedAt.addingTimeInterval(55 * 60)
            let logged = plan.seeds.enumerated().map { order, seed -> LoggedExercise in
                let exercise = library.first { $0.seedIdentifier == seed }
                let sets = (0..<3).map {
                    LoggedSet(orderIndex: $0, weight: 135, reps: 8, isCompleted: true, completedAt: endedAt,
                              createdAt: startedAt, updatedAt: endedAt)
                }
                return LoggedExercise(
                    orderIndex: order,
                    exercise: exercise,
                    exerciseSnapshotName: exercise?.name ?? String(seed.dropFirst("custom:".count)),
                    exerciseSnapshotEquipmentRaw: exercise?.equipmentRaw ?? ExerciseEquipment.other.rawValue,
                    exerciseSnapshotPrimaryMuscleGroupRaw: exercise?.primaryMuscleGroupRaw
                        ?? ExerciseMuscleGroup.other.rawValue,
                    createdAt: startedAt, updatedAt: endedAt, sets: sets
                )
            }
            context.insert(WorkoutSession(
                title: WorkoutSession.defaultTitle, startedAt: startedAt, endedAt: endedAt,
                durationSeconds: 55 * 60, status: .completed, source: .blank,
                createdAt: startedAt, updatedAt: endedAt,
                syncOwnerTokenIdentifier: ownerTokenIdentifier,
                loggedExercises: logged
            ))
            _ = index
        }
        try context.save()
    }
}
#endif
