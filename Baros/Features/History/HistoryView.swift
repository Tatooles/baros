import Observation
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(SyncScheduler.self) private var syncScheduler
    @Bindable var navigationState: AppNavigationState
    @State private var exerciseHistoryState = ExerciseHistoryViewState()
    @State private var searchState = HistorySearchState()
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(
        filter: #Predicate<WorkoutSession> { session in
            session.statusRaw == "completed"
        },
        sort: \WorkoutSession.startedAt,
        order: .reverse
    ) private var sessions: [WorkoutSession]

    private var completedSessions: [WorkoutSession] {
        WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        )
    }

    var body: some View {
        let ownerTokenIdentifier = syncScheduler.currentOwnerTokenIdentifier
        // Remote child records do not always touch their parent session. Reading
        // the sync completion date makes the state boundary re-check its semantic
        // key after a pull without treating every no-op sync as a history change.
        let exerciseHistorySnapshot = exerciseHistoryState.snapshot(
            sessions: sessions,
            exercises: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier,
            syncCompletion: syncScheduler.lastSyncedAt
        )
        let completedSessions = completedSessions
        let workoutSearchIndex = WorkoutHistorySearchIndex(sessions: completedSessions)

        HistorySearchContent(
            navigationState: navigationState,
            searchState: searchState,
            completedSessions: completedSessions,
            workoutSearchIndex: workoutSearchIndex,
            exerciseHistorySnapshot: exerciseHistorySnapshot
        )
        .navigationDestination(for: HistoryRoute.self) { route in
            switch route {
            case .workout(let sessionID):
                WorkoutHistoryDestinationView(sessionID: sessionID)
            case .exercise(let exerciseRoute):
                if let summary = exerciseHistorySnapshot.resolvedHistory.summary(for: exerciseRoute) {
                    ExerciseHistoryDetailView(summary: summary)
                } else {
                    EmptyStateView(
                        title: "No Exercise History",
                        message: "Completed sets for this exercise will appear here."
                    )
                    .background(AppTheme.canvasBackground.ignoresSafeArea())
                }
            }
        }
    }
}

@MainActor
@Observable
private final class HistorySearchState {
    var text = ""
}

private struct HistorySearchContent: View {
    @Bindable var navigationState: AppNavigationState
    @Bindable var searchState: HistorySearchState
    let completedSessions: [WorkoutSession]
    let workoutSearchIndex: WorkoutHistorySearchIndex
    let exerciseHistorySnapshot: ExerciseHistoryViewSnapshot

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Picker("History Mode", selection: $navigationState.historyMode) {
                    ForEach(HistoryMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("HistoryModePicker")

                switch navigationState.historyMode {
                case .workouts:
                    workoutContent
                case .exercises:
                    exerciseContent
                }

                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains(
                    "--uitest-open-unavailable-workout-history"
                ) {
                    Button("Open unavailable workout") {
                        navigationState.openWorkoutHistory(
                            UUID(uuidString: "00000000-0000-4000-8000-000000012699")!
                        )
                    }
                    .accessibilityIdentifier("UITestOpenUnavailableWorkoutButton")
                }
                #endif
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .navigationTitle("History")
        .searchable(text: $searchState.text, prompt: "Search history")
    }

    @ViewBuilder
    private var workoutContent: some View {
        let filteredCompletedSessions = workoutSearchIndex.sessions(
            from: completedSessions,
            matching: searchState.text
        )
        if completedSessions.isEmpty {
            EmptyHistoryStateView(
                recoveryTitle: "Looking for your workouts?",
                emptyTitle: "No Workouts Yet",
                emptyMessage: "Finished workouts will appear here."
            )
        } else if HistorySearch.hasQuery(searchState.text), filteredCompletedSessions.isEmpty {
            EmptyStateView(
                title: "No Matching Workouts",
                message: "Try a workout title or exercise name."
            )
        } else {
            LazyVStack(spacing: 10) {
                ForEach(Array(filteredCompletedSessions.enumerated()), id: \.element.id) { index, session in
                    NavigationLink(value: HistoryRoute.workout(session.id)) {
                        WorkoutHistoryRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("WorkoutHistoryButton-\(index)")
                }
            }
        }
    }

    @ViewBuilder
    private var exerciseContent: some View {
        let summaries = exerciseHistorySnapshot.resolvedHistory.summaries
        let filteredSummaries = HistorySearch.exercises(in: summaries, matching: searchState.text)
        if summaries.isEmpty {
            EmptyHistoryStateView(
                recoveryTitle: "Looking for your exercise history?",
                emptyTitle: "No Exercise History",
                emptyMessage: "Completed sets will build exercise history.",
                hasVisibleCompletedWorkouts: !completedSessions.isEmpty
            )
        } else if HistorySearch.hasQuery(searchState.text), filteredSummaries.isEmpty {
            EmptyStateView(
                title: "No Matching Exercises",
                message: "Try an exercise name, equipment, or muscle group."
            )
        } else {
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(filteredSummaries.enumerated()), id: \.element.id) { index, summary in
                        NavigationLink(value: HistoryRoute.exercise(ExerciseHistoryRoute(summary: summary))) {
                            ExerciseHistoryRow(
                                summary: summary,
                                showsDivider: index < filteredSummaries.count - 1
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("ExerciseHistoryButton-\(index)")
                    }
                }
            }
        }
    }
}

@MainActor
final class ExerciseHistoryViewState {
    private let resolveHistory: ExerciseHistoryViewSnapshot.ResolveHistory
    private var invalidationKey: ExerciseHistoryInvalidationKey?
    private var currentSnapshot: ExerciseHistoryViewSnapshot?

    init(
        resolveHistory: @escaping ExerciseHistoryViewSnapshot.ResolveHistory = ExerciseHistorySummary.makeResolvedHistory
    ) {
        self.resolveHistory = resolveHistory
    }

    func snapshot(
        sessions: [WorkoutSession],
        exercises: [Exercise],
        ownerTokenIdentifier: String?,
        syncCompletion: Date?
    ) -> ExerciseHistoryViewSnapshot {
        _ = syncCompletion
        let nextKey = ExerciseHistoryInvalidationKey(
            sessions: sessions,
            exercises: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier
        )
        if nextKey != invalidationKey || currentSnapshot == nil {
            invalidationKey = nextKey
            currentSnapshot = ExerciseHistoryViewSnapshot(
                sessions: sessions,
                exercises: exercises,
                ownerTokenIdentifier: ownerTokenIdentifier,
                resolveHistory: resolveHistory
            )
        }
        guard let currentSnapshot else {
            preconditionFailure("Exercise History state did not create its initial snapshot")
        }
        return currentSnapshot
    }
}

private struct ExerciseHistoryInvalidationKey: Equatable {
    private struct SessionContribution: Equatable {
        let id: UUID
        let startedAt: Date
        let exercises: [LoggedExerciseContribution]
    }

    private struct LoggedExerciseContribution: Equatable {
        let orderIndex: Int
        let linkedExerciseID: UUID?
        let snapshotName: String
        let snapshotEquipmentRaw: String?
        let snapshotPrimaryMuscleGroupRaw: String?
        let completedSetCount: Int
    }

    private struct ExerciseDefinition: Equatable {
        let id: UUID
        let name: String
        let equipmentRaw: String
    }

    private let ownerTokenIdentifier: String?
    private let sessions: [SessionContribution]
    private let exercises: [ExerciseDefinition]

    init(
        sessions: [WorkoutSession],
        exercises: [Exercise],
        ownerTokenIdentifier: String?
    ) {
        self.ownerTokenIdentifier = ownerTokenIdentifier
        self.sessions = WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).map { session in
            SessionContribution(
                id: session.id,
                startedAt: session.startedAt,
                exercises: session.sortedLoggedExercises.compactMap { loggedExercise in
                    let completedSetCount = loggedExercise.sortedSets.filter(\.isCompleted).count
                    guard completedSetCount > 0 else { return nil }
                    return LoggedExerciseContribution(
                        orderIndex: loggedExercise.orderIndex,
                        linkedExerciseID: loggedExercise.exercise?.id,
                        snapshotName: loggedExercise.exerciseSnapshotName,
                        snapshotEquipmentRaw: loggedExercise.resolvedSnapshotEquipmentRaw,
                        snapshotPrimaryMuscleGroupRaw: loggedExercise.resolvedSnapshotPrimaryMuscleGroupRaw,
                        completedSetCount: completedSetCount
                    )
                }
            )
        }
        self.exercises = Exercise.visibleActiveExercises(
            from: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).map { exercise in
            ExerciseDefinition(
                id: exercise.id,
                name: exercise.name,
                equipmentRaw: exercise.equipmentRaw
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }
    }
}

@MainActor
final class ExerciseHistoryViewSnapshot {
    typealias ResolveHistory = (
        _ sessions: [WorkoutSession],
        _ exercises: [Exercise],
        _ ownerTokenIdentifier: String?
    ) -> ResolvedExerciseHistory

    private let resolveHistory: () -> ResolvedExerciseHistory

    private(set) lazy var resolvedHistory = resolveHistory()

    init(
        sessions: [WorkoutSession],
        exercises: [Exercise],
        ownerTokenIdentifier: String?,
        resolveHistory: @escaping ResolveHistory = ExerciseHistorySummary.makeResolvedHistory
    ) {
        self.resolveHistory = {
            #if DEBUG
            let startedAt = ProcessInfo.processInfo.systemUptime
            defer {
                ExerciseHistoryUITestMetrics.shared.recordResolution(
                    elapsed: ProcessInfo.processInfo.systemUptime - startedAt
                )
            }
            #endif
            return resolveHistory(
                sessions,
                exercises,
                ownerTokenIdentifier
            )
        }
    }
}

#if DEBUG
@MainActor
final class ExerciseHistoryUITestMetrics {
    static let measurementArgument = "--uitest-measure-exercise-history-invalidation"
    static let shared = ExerciseHistoryUITestMetrics()

    let isEnabled: Bool
    private(set) var resolutionCount = 0
    private(set) var resolutionTimeMilliseconds = 0.0

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        isEnabled = arguments.contains(Self.measurementArgument)
    }

    func recordResolution(elapsed: TimeInterval) {
        guard isEnabled else { return }
        resolutionCount += 1
        resolutionTimeMilliseconds += elapsed * 1_000
    }
}
#endif
