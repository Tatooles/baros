import Foundation

public struct ExerciseHistorySetEntry: Identifiable {
    let loggedExercise: LoggedExercise
    public let set: LoggedSet

    public var id: UUID { self.set.id }
    public var displaySetNumber: Int { self.set.orderIndex + 1 }
}

public struct ExerciseHistoryLoggedExerciseEntry: Identifiable {
    let loggedExercise: LoggedExercise
    public var setEntries: [ExerciseHistorySetEntry]

    public var id: UUID { loggedExercise.id }
    public var exerciseNotes: String { loggedExercise.notes }
    public var displayIdentity: ExerciseHistoryDisplayIdentity {
        ExerciseHistoryDisplayIdentity(loggedExercise: loggedExercise)
    }

    public func showsIdentity(comparedTo headingIdentity: ExerciseHistoryDisplayIdentity) -> Bool {
        displayIdentity != headingIdentity
    }
}

public struct ExerciseHistoryDisplayIdentity: Equatable {
    public let name: String
    public let metadataDisplayText: String?

    public init(name: String, metadataDisplayText: String?) {
        self.name = name
        self.metadataDisplayText = metadataDisplayText
    }

    public init(loggedExercise: LoggedExercise) {
        self.init(
            name: loggedExercise.exerciseSnapshotName,
            metadataDisplayText: loggedExercise.metadataDisplayText
        )
    }
}

public struct ExerciseHistorySessionGroup: Identifiable {
    public let session: WorkoutSession
    public let setEntries: [ExerciseHistorySetEntry]
    public let loggedExerciseEntries: [ExerciseHistoryLoggedExerciseEntry]

    init(session: WorkoutSession, setEntries: [ExerciseHistorySetEntry]) {
        self.session = session
        self.setEntries = setEntries
        self.loggedExerciseEntries = Self.groupByLoggedExercise(setEntries)
    }

    public var id: UUID { session.id }
    public var title: String { session.title }
    public var startedAt: Date { session.startedAt }
    public var completedSetCount: Int { setEntries.count }
    var exerciseNotes: String? {
        let notes = setEntries
            .map(\.loggedExercise)
            .first?
            .notes
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return notes.isEmpty ? nil : notes
    }

    public static func makeGroups(
        from sessions: [WorkoutSession],
        matching summary: ExerciseHistorySummary,
        ownerTokenIdentifier: String? = nil
    ) -> [ExerciseHistorySessionGroup] {
        WorkoutSession.visibleCompletedSessions(from: sessions, ownerTokenIdentifier: ownerTokenIdentifier)
            .compactMap { session in
                let entries = session.sortedLoggedExercises.flatMap { loggedExercise in
                    guard summary.matches(loggedExercise) else { return [ExerciseHistorySetEntry]() }

                    return loggedExercise.sortedSets
                        .filter(\.isCompleted)
                        .map { ExerciseHistorySetEntry(loggedExercise: loggedExercise, set: $0) }
                }

                guard !entries.isEmpty else { return nil }
                return ExerciseHistorySessionGroup(session: session, setEntries: entries)
            }
            .sorted { lhs, rhs in
                if lhs.startedAt == rhs.startedAt {
                    return lhs.title < rhs.title
                }
                return lhs.startedAt > rhs.startedAt
            }
    }

    static func recentGroups(
        from sessions: [WorkoutSession],
        matching summary: ExerciseHistorySummary,
        ownerTokenIdentifier: String? = nil,
        limit: Int = 3
    ) -> [ExerciseHistorySessionGroup] {
        Array(makeGroups(
            from: sessions,
            matching: summary,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).prefix(limit))
    }

    private static func groupByLoggedExercise(
        _ setEntries: [ExerciseHistorySetEntry]
    ) -> [ExerciseHistoryLoggedExerciseEntry] {
        var groupedEntries: [ExerciseHistoryLoggedExerciseEntry] = []
        var groupedIndexByLoggedExerciseID: [UUID: Int] = [:]

        for setEntry in setEntries {
            let loggedExerciseID = setEntry.loggedExercise.id

            if let groupedIndex = groupedIndexByLoggedExerciseID[loggedExerciseID] {
                groupedEntries[groupedIndex].setEntries.append(setEntry)
            } else {
                groupedIndexByLoggedExerciseID[loggedExerciseID] = groupedEntries.count
                groupedEntries.append(
                    ExerciseHistoryLoggedExerciseEntry(
                        loggedExercise: setEntry.loggedExercise,
                        setEntries: [setEntry]
                    )
                )
            }
        }

        return groupedEntries
    }
}
