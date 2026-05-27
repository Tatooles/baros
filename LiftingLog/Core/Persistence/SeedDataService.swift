import Foundation
import SwiftData

enum SeedDataService {
    static let exerciseSeedKey = "exerciseSeed"
    static let exerciseSeedVersion = 1

    static func seedIfNeeded(context: ModelContext) throws {
        try ensureSettings(context: context)
        try ensureExercises(context: context)
        try ensureSeedMetadata(context: context)
        try context.save()
    }

    private static func ensureSettings(context: ModelContext) throws {
        let settings = try context.fetch(FetchDescriptor<UserSettings>())
        if UserSettings.visibleSettingsRecords(from: settings).isEmpty {
            context.insert(UserSettings())
        }
    }

    private static func ensureExercises(context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<Exercise>())
        let existingSeedIdentifiers = Set(existing.compactMap(\.seedIdentifier))

        for seed in exerciseSeeds where !existingSeedIdentifiers.contains(seed.seedIdentifier) {
            context.insert(
                Exercise(
                    seedIdentifier: seed.seedIdentifier,
                    name: seed.name,
                    category: seed.category,
                    equipment: seed.equipment,
                    primaryMuscle: seed.primaryMuscle,
                    notes: seed.notes,
                    isSeeded: true
                )
            )
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
        ExerciseSeed("back-squat", "Back Squat", .strength, .barbell, "Quads"),
        ExerciseSeed("front-squat", "Front Squat", .strength, .barbell, "Quads"),
        ExerciseSeed("romanian-deadlift", "Romanian Deadlift", .strength, .barbell, "Hamstrings"),
        ExerciseSeed("conventional-deadlift", "Conventional Deadlift", .strength, .barbell, "Posterior Chain"),
        ExerciseSeed("leg-press", "Leg Press", .strength, .machine, "Quads"),
        ExerciseSeed("leg-extension", "Leg Extension", .strength, .machine, "Quads"),
        ExerciseSeed("leg-curl", "Leg Curl", .strength, .machine, "Hamstrings"),
        ExerciseSeed("bench-press", "Bench Press", .strength, .barbell, "Chest"),
        ExerciseSeed("incline-dumbbell-press", "Incline Dumbbell Press", .strength, .dumbbell, "Chest"),
        ExerciseSeed("overhead-press", "Overhead Press", .strength, .barbell, "Shoulders"),
        ExerciseSeed("pull-up", "Pull-Up", .strength, .bodyweight, "Back"),
        ExerciseSeed("lat-pulldown", "Lat Pulldown", .strength, .cable, "Back"),
        ExerciseSeed("barbell-row", "Barbell Row", .strength, .barbell, "Back"),
        ExerciseSeed("seated-cable-row", "Seated Cable Row", .strength, .cable, "Back"),
        ExerciseSeed("dumbbell-row", "Dumbbell Row", .strength, .dumbbell, "Back"),
        ExerciseSeed("face-pull", "Face Pull", .strength, .cable, "Rear Delts"),
        ExerciseSeed("biceps-curl", "Biceps Curl", .strength, .dumbbell, "Biceps"),
        ExerciseSeed("triceps-pushdown", "Triceps Pushdown", .strength, .cable, "Triceps"),
        ExerciseSeed("calf-raise", "Calf Raise", .strength, .machine, "Calves"),
        ExerciseSeed("plank", "Plank", .strength, .bodyweight, "Core")
    ]
}

struct ExerciseSeed {
    var seedIdentifier: String
    var name: String
    var category: ExerciseCategory
    var equipment: ExerciseEquipment
    var primaryMuscle: String
    var notes: String

    init(
        _ seedIdentifier: String,
        _ name: String,
        _ category: ExerciseCategory,
        _ equipment: ExerciseEquipment,
        _ primaryMuscle: String,
        notes: String = ""
    ) {
        self.seedIdentifier = seedIdentifier
        self.name = name
        self.category = category
        self.equipment = equipment
        self.primaryMuscle = primaryMuscle
        self.notes = notes
    }
}
