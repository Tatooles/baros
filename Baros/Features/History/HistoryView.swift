import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(SyncScheduler.self) private var syncScheduler
    @Bindable var navigationState: AppNavigationState
    @State private var exerciseHistoryState = ExerciseHistoryViewState()
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

        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("History")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .accessibilityIdentifier("HistoryTitle")

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
                    exerciseContent(snapshot: exerciseHistorySnapshot)
                }
            }
            .padding(AppTheme.shellPadding)
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HistoryRoute.self) { route in
            switch route {
            case .workout(let sessionID):
                if let session = completedSessions.first(where: { $0.id == sessionID }) {
                    WorkoutHistoryDetailView(session: session)
                } else {
                    EmptyStateView(
                        title: "Workout Unavailable",
                        message: "This workout is no longer available in History."
                    )
                    .background(AppTheme.canvasBackground.ignoresSafeArea())
                }
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

    @ViewBuilder
    private var workoutContent: some View {
        if completedSessions.isEmpty {
            EmptyHistoryStateView(
                recoveryTitle: "Looking for your workouts?",
                emptyTitle: "No Workouts Yet",
                emptyMessage: "Finished workouts will appear here."
            )
        } else {
            VStack(spacing: 10) {
                ForEach(Array(completedSessions.enumerated()), id: \.element.id) { index, session in
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
    private func exerciseContent(snapshot: ExerciseHistoryViewSnapshot) -> some View {
        let summaries = snapshot.resolvedHistory.summaries
        if summaries.isEmpty {
            EmptyHistoryStateView(
                recoveryTitle: "Looking for your exercise history?",
                emptyTitle: "No Exercise History",
                emptyMessage: "Completed sets will build exercise history.",
                hasVisibleCompletedWorkouts: !completedSessions.isEmpty
            )
        } else {
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                        NavigationLink(value: HistoryRoute.exercise(ExerciseHistoryRoute(summary: summary))) {
                            ExerciseHistoryRow(
                                summary: summary,
                                showsDivider: index < summaries.count - 1
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
