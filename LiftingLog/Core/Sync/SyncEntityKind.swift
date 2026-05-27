enum SyncEntityKind: Equatable {
    case userSettings
    case exercise
    case workoutSession
    case loggedExercise
    case loggedSet
    case workoutTemplate
    case healthDataLink
    case seedMetadata

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
}
