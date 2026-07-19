enum SyncEntityKind: String, CaseIterable, Equatable, Codable, Hashable {
    case userSettings = "userSettings"
    case exercise = "exercises"
    case workoutSession = "workoutSessions"
    case loggedExercise = "loggedExercises"
    case loggedSet = "loggedSets"
    case workoutTemplate = "workoutTemplates"
    case healthDataLink = "healthDataLinks"
    case seedMetadata = "seedMetadata"

    static let v1Synced: [SyncEntityKind] = [
        .userSettings,
        .exercise,
        .workoutSession,
        .loggedExercise,
        .loggedSet,
    ]

    static let v1Excluded: [SyncEntityKind] = [
        .workoutTemplate,
        .healthDataLink,
        .seedMetadata,
    ]

    var isV1Synced: Bool {
        Self.v1Synced.contains(self)
    }
}
