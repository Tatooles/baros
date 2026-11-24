import Foundation

public struct WorkoutTemplateDraft: Equatable {
    public var name: String
    public var entries: [WorkoutTemplateEntry]

    public init(template: WorkoutTemplate?) {
        name = template?.name ?? ""
        entries = template?.entries ?? []
    }

    init(name: String, entries: [WorkoutTemplateEntry]) {
        self.name = name
        self.entries = entries
    }

    public var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var canSave: Bool {
        !trimmedName.isEmpty && !entries.isEmpty
    }

    public var exerciseIDs: Set<UUID> {
        Set(entries.compactMap(\.exerciseID))
    }

    public mutating func reorder(_ orderedIDs: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        entries = orderedIDs.compactMap { byID[$0] }
    }

    public mutating func remove(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
    }

    public mutating func append(_ exercises: [Exercise], asSuperset: Bool = false) {
        let group = SupersetGrouping.groupForAdding(exercises.count, asSuperset: asSuperset)
        entries += exercises.map { WorkoutTemplateEntry(exercise: $0, supersetGroupID: group) }
    }

    public mutating func regroup(_ groupIDs: [UUID?]) {
        for (index, group) in zip(entries.indices, groupIDs) { entries[index].supersetGroupID = group }
    }

    public func refreshedEntries(exercisesByID: [UUID: Exercise]) -> [WorkoutTemplateEntry] {
        entries.map { entry in
            guard let exercise = entry.exerciseID.flatMap({ exercisesByID[$0] }) else { return entry }
            var refreshed = WorkoutTemplateEntry(exercise: exercise, supersetGroupID: entry.supersetGroupID)
            refreshed.id = entry.id
            return refreshed
        }
    }
}

public struct TemplateExerciseItem: ReorderListExercise {
    public let id: UUID
    public let name: String
    public let metadata: String?
    public let supersetGroupID: UUID?
    public var trailingDetail: String? { nil }
    public var isNew: Bool { false }
    public var accessibilityValue: String { metadata ?? "" }

    init(entry: WorkoutTemplateEntry, exercise: Exercise?) {
        id = entry.id
        supersetGroupID = entry.supersetGroupID
        if let exercise {
            name = exercise.name
            metadata = exercise.metadataDisplayText
        } else {
            name = entry.exerciseSnapshotName
            let equipment = ExerciseEquipment(rawValue: entry.exerciseSnapshotEquipmentRaw) ?? .other
            let muscle = ExerciseMuscleGroup(rawValue: entry.exerciseSnapshotPrimaryMuscleGroupRaw) ?? .other
            metadata = "\(equipment.displayName) • \(muscle.displayName)"
        }
    }

    public static func items(
        for entries: [WorkoutTemplateEntry],
        exercisesByID: [UUID: Exercise]
    ) -> [TemplateExerciseItem] {
        entries.map { entry in
            TemplateExerciseItem(entry: entry, exercise: entry.exerciseID.flatMap { exercisesByID[$0] })
        }
    }
}

extension Array where Element == Exercise {
    public func visibleByID(to ownerTokenIdentifier: String?) -> [UUID: Exercise] {
        Dictionary(
            filter { !$0.isDeleted && $0.isVisible(to: ownerTokenIdentifier) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

extension Array where Element == WorkoutTemplate {
    public func visible(to ownerTokenIdentifier: String?) -> [WorkoutTemplate] {
        filter { !$0.isDeleted && $0.isVisible(to: ownerTokenIdentifier) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

public struct NewTemplateFromWorkout: Identifiable {
    public let id = UUID()
    public let draft: WorkoutTemplateDraft

    public init(session: WorkoutSession) {
        draft = WorkoutTemplateDraft(name: session.title, entries: WorkoutTemplateEntry.entries(copying: session))
    }
}

public enum FinishTemplateOffer: Equatable {
    case none
    case saveAsNew
    case updateOrSaveAsNew(WorkoutTemplate)

    public init(session: WorkoutSession, templates: [WorkoutTemplate], ownerTokenIdentifier: String?) {
        guard session.visibleExerciseCount > 0 else {
            self = .none
            return
        }
        guard session.source == .template,
              let sourceTemplateID = session.sourceTemplateID,
              let template = templates.first(where: {
                  $0.id == sourceTemplateID && !$0.isDeleted && $0.isVisible(to: ownerTokenIdentifier)
              })
        else {
            self = .saveAsNew
            return
        }
        let workoutEntries = WorkoutTemplateEntry.entries(copying: session)
        self = WorkoutTemplateEntry.haveSameExercises(template.entries, workoutEntries)
            ? .none
            : .updateOrSaveAsNew(template)
    }
}

extension WorkoutTemplateEntry {
    static func haveSameExercises(_ lhs: [Self], _ rhs: [Self]) -> Bool {
        guard lhs.count == rhs.count else { return false }
        let lhsGroups = lhs.map(\.supersetGroupID)
        let rhsGroups = rhs.map(\.supersetGroupID)
        return lhs.indices.allSatisfy { index in
            lhs[index].isSameExercise(as: rhs[index])
                && SupersetGrouping.areGrouped(lhsGroups, index, index - 1)
                    == SupersetGrouping.areGrouped(rhsGroups, index, index - 1)
        }
    }

    private func isSameExercise(as other: Self) -> Bool {
        if let exerciseID, let otherID = other.exerciseID {
            return exerciseID == otherID
        }
        return exerciseSnapshotName.caseInsensitiveCompare(other.exerciseSnapshotName) == .orderedSame
    }
}
