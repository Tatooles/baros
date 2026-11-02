import Foundation

/// The template editor's unsaved name and exercises.
struct WorkoutTemplateDraft: Equatable {
    var name: String
    var entries: [WorkoutTemplateEntry]

    init(template: WorkoutTemplate?) {
        name = template?.name ?? ""
        entries = template?.entries ?? []
    }

    init(name: String, entries: [WorkoutTemplateEntry]) {
        self.name = name
        self.entries = entries
    }

    var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool {
        !trimmedName.isEmpty && !entries.isEmpty
    }

    var exerciseIDs: Set<UUID> {
        Set(entries.compactMap(\.exerciseID))
    }

    mutating func reorder(_ orderedIDs: [UUID]) {
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        entries = orderedIDs.compactMap { byID[$0] }
    }

    mutating func remove(_ ids: Set<UUID>) {
        entries.removeAll { ids.contains($0.id) }
    }

    mutating func append(_ exercises: [Exercise]) {
        entries += exercises.map { WorkoutTemplateEntry(exercise: $0) }
    }

    /// Entries with their snapshots refreshed from the library, so a renamed
    /// exercise saves under its current name.
    func refreshedEntries(exercisesByID: [UUID: Exercise]) -> [WorkoutTemplateEntry] {
        entries.map { entry in
            guard let exercise = entry.exerciseID.flatMap({ exercisesByID[$0] }) else { return entry }
            var refreshed = WorkoutTemplateEntry(exercise: exercise, supersetGroupID: entry.supersetGroupID)
            refreshed.id = entry.id
            return refreshed
        }
    }
}

/// One template exercise as the list rows show it. The library exercise wins
/// over the entry's snapshot while it exists.
struct TemplateExerciseItem: ReorderListExercise {
    let id: UUID
    let name: String
    let metadata: String?
    let supersetGroupID: UUID?
    var trailingDetail: String? { nil }
    var isNew: Bool { false }
    var accessibilityValue: String { metadata ?? "" }

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

    static func items(
        for entries: [WorkoutTemplateEntry],
        exercisesByID: [UUID: Exercise]
    ) -> [TemplateExerciseItem] {
        entries.map { entry in
            TemplateExerciseItem(entry: entry, exercise: entry.exerciseID.flatMap { exercisesByID[$0] })
        }
    }
}

extension Array where Element == Exercise {
    /// The owner's exercises by id, for resolving template entries.
    func visibleByID(to ownerTokenIdentifier: String?) -> [UUID: Exercise] {
        Dictionary(
            filter { !$0.isDeleted && $0.isVisible(to: ownerTokenIdentifier) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

extension Array where Element == WorkoutTemplate {
    /// The owner's templates by name, numbers in natural order.
    func visible(to ownerTokenIdentifier: String?) -> [WorkoutTemplate] {
        filter { !$0.isDeleted && $0.isVisible(to: ownerTokenIdentifier) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// History's Save as Template: a new template named after the workout, to
/// rename before saving.
struct NewTemplateFromWorkout: Identifiable {
    let id = UUID()
    let draft: WorkoutTemplateDraft

    init(session: WorkoutSession) {
        draft = WorkoutTemplateDraft(name: session.title, entries: WorkoutTemplateEntry.entries(copying: session))
    }
}
