import Foundation
import SwiftData

enum SeedDataService {
    static let exerciseSeedKey = "exerciseSeed"
    static let exerciseSeedVersion = 1

    enum OwnerlessScope {
        case visibleOnly
        case allExisting
    }

    static func seedIfNeeded(
        context: ModelContext,
        ownerTokenIdentifier: String? = nil,
        ownerlessScope: OwnerlessScope = .visibleOnly,
        claimOwnerlessVisibleDefaults: Bool = false
    ) throws {
        if let ownerTokenIdentifier, claimOwnerlessVisibleDefaults {
            try claimOwnerlessVisibleRecords(context: context, ownerTokenIdentifier: ownerTokenIdentifier)
        }
        try ensureSettings(context: context, ownerTokenIdentifier: ownerTokenIdentifier, ownerlessScope: ownerlessScope)
        try ensureExercises(context: context, ownerTokenIdentifier: ownerTokenIdentifier, ownerlessScope: ownerlessScope)
        try migrateLegacyPrimaryMuscleGroups(context: context)
        try ensureSeedMetadata(context: context)
        try context.save()
    }

    private static func claimOwnerlessVisibleRecords(
        context: ModelContext,
        ownerTokenIdentifier: String
    ) throws {
        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        for setting in UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: nil) {
            setting.syncOwnerTokenIdentifier = ownerTokenIdentifier
        }

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        for exercise in Exercise.visibleActiveExercises(from: exercises, ownerTokenIdentifier: nil) {
            exercise.syncOwnerTokenIdentifier = ownerTokenIdentifier
        }
    }

    private static func ensureSettings(
        context: ModelContext,
        ownerTokenIdentifier: String?,
        ownerlessScope: OwnerlessScope
    ) throws {
        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        let visibleSettings: [UserSettings]
        if let ownerTokenIdentifier {
            visibleSettings = UserSettings.visibleSettingsRecords(from: settings)
                .filter { $0.syncOwnerTokenIdentifier == nil || $0.syncOwnerTokenIdentifier == ownerTokenIdentifier }
        } else {
            switch ownerlessScope {
            case .visibleOnly:
                visibleSettings = UserSettings.visibleSettingsRecords(from: settings, ownerTokenIdentifier: nil)
            case .allExisting:
                visibleSettings = UserSettings.visibleSettingsRecords(from: settings)
            }
        }
        if visibleSettings.isEmpty {
            context.insert(UserSettings(syncOwnerTokenIdentifier: ownerTokenIdentifier))
        }
    }

    private static func ensureExercises(
        context: ModelContext,
        ownerTokenIdentifier: String?,
        ownerlessScope: OwnerlessScope
    ) throws {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let ownerVisibleExisting: [Exercise]
        if let ownerTokenIdentifier {
            ownerVisibleExisting = existing.filter {
                $0.syncOwnerTokenIdentifier == nil || $0.syncOwnerTokenIdentifier == ownerTokenIdentifier
            }
        } else {
            switch ownerlessScope {
            case .visibleOnly:
                ownerVisibleExisting = existing.filter { $0.isVisible(to: nil) }
            case .allExisting:
                ownerVisibleExisting = existing
            }
        }
        let existingSeedIdentifiers = Set(ownerVisibleExisting.compactMap(\.seedIdentifier))

        for seed in exerciseSeeds where !existingSeedIdentifiers.contains(seed.seedIdentifier) {
            context.insert(
                Exercise(
                    seedIdentifier: seed.seedIdentifier,
                    name: seed.name,
                    category: seed.category,
                    equipment: seed.equipment,
                    primaryMuscleGroup: seed.primaryMuscleGroup,
                    notes: seed.notes,
                    isSeeded: true,
                    syncOwnerTokenIdentifier: ownerTokenIdentifier
                )
            )
        }
    }

    private static func migrateLegacyPrimaryMuscleGroups(context: ModelContext) throws {
        let exercises = try context.fetch(FetchDescriptor<Exercise>())

        for exercise in exercises where exercise.primaryMuscleGroupRaw == ExerciseMuscleGroup.other.rawValue {
            let migrated = ExerciseMuscleGroup.legacyGroup(for: exercise.primaryMuscleRaw)
            if migrated != .other {
                exercise.primaryMuscleGroupRaw = migrated.rawValue
                exercise.primaryMuscleRaw = migrated.displayName
                exercise.touch()
            }
        }
    }

    private static func ensureSeedMetadata(context: ModelContext) throws {
        let metadata = try context.fetch(FetchDescriptor<SeedMetadata>())
        if let existing = metadata.first(where: { $0.key == exerciseSeedKey }) {
            existing.version = max(existing.version, exerciseSeedVersion)
            existing.appliedAt = .now
        } else {
            context.insert(SeedMetadata(key: exerciseSeedKey, version: exerciseSeedVersion))
        }
    }

    static let exerciseSeeds: [ExerciseSeed] = [
        ExerciseSeed("back-squat", "Back Squat", .strength, .barbell, .quads),
        ExerciseSeed("front-squat", "Front Squat", .strength, .barbell, .quads),
        ExerciseSeed("romanian-deadlift", "Romanian Deadlift", .strength, .barbell, .hamstrings),
        ExerciseSeed("conventional-deadlift", "Conventional Deadlift", .strength, .barbell, .glutes),
        ExerciseSeed("leg-press", "Leg Press", .strength, .machine, .quads),
        ExerciseSeed("leg-extension", "Leg Extension", .strength, .machine, .quads),
        ExerciseSeed("leg-curl", "Leg Curl", .strength, .machine, .hamstrings),
        ExerciseSeed("bench-press", "Bench Press", .strength, .barbell, .chest),
        ExerciseSeed("incline-dumbbell-press", "Incline Dumbbell Press", .strength, .dumbbell, .chest),
        ExerciseSeed("overhead-press", "Overhead Press", .strength, .barbell, .shoulders),
        ExerciseSeed("pull-up", "Pull-Up", .strength, .bodyweight, .lats),
        ExerciseSeed("lat-pulldown", "Lat Pulldown", .strength, .cable, .lats),
        ExerciseSeed("barbell-row", "Barbell Row", .strength, .barbell, .upperBack),
        ExerciseSeed("seated-cable-row", "Seated Cable Row", .strength, .cable, .upperBack),
        ExerciseSeed("dumbbell-row", "Dumbbell Row", .strength, .dumbbell, .upperBack),
        ExerciseSeed("face-pull", "Face Pull", .strength, .cable, .shoulders),
        ExerciseSeed("biceps-curl", "Biceps Curl", .strength, .dumbbell, .biceps),
        ExerciseSeed("triceps-pushdown", "Triceps Pushdown", .strength, .cable, .triceps),
        ExerciseSeed("calf-raise", "Calf Raise", .strength, .machine, .calves),
        ExerciseSeed("plank", "Plank", .strength, .bodyweight, .core)
    ]
}

struct ExerciseSeed {
    var seedIdentifier: String
    var name: String
    var category: ExerciseCategory
    var equipment: ExerciseEquipment
    var primaryMuscleGroup: ExerciseMuscleGroup
    var notes: String

    init(
        _ seedIdentifier: String,
        _ name: String,
        _ category: ExerciseCategory,
        _ equipment: ExerciseEquipment,
        _ primaryMuscleGroup: ExerciseMuscleGroup,
        notes: String = ""
    ) {
        self.seedIdentifier = seedIdentifier
        self.name = name
        self.category = category
        self.equipment = equipment
        self.primaryMuscleGroup = primaryMuscleGroup
        self.notes = notes
    }
}
