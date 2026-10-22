import Observation
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
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
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        )
    }

    var body: some View {
        let ownerTokenIdentifier = currentOwnerCoordinator.localDataOwnerTokenIdentifier
        let exerciseHistorySnapshot = exerciseHistoryState.snapshot(
            sessions: sessions,
            exercises: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier
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
        .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
            exerciseHistoryState.recordSave(notification, in: modelContext)
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

                // An empty list already explains the sign-out in its empty state.
                if !isCurrentModeEmpty {
                    SignedOutReminderBanner()
                }

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

    private var isCurrentModeEmpty: Bool {
        switch navigationState.historyMode {
        case .workouts:
            completedSessions.isEmpty
        case .exercises:
            exerciseHistorySnapshot.resolvedHistory.summaries.isEmpty
        }
    }

    @ViewBuilder
    private var workoutContent: some View {
        let filteredCompletedSessions = workoutSearchIndex.sessions(
            from: completedSessions,
            matching: searchState.text
        )
        if completedSessions.isEmpty {
            EmptyHistoryStateView(
                emptyTitle: "No Workouts Yet",
                emptyMessage: "Finished workouts will appear here."
            )
        } else if HistorySearch.hasQuery(searchState.text), filteredCompletedSessions.isEmpty {
            EmptyStateView(
                title: "No Matching Workouts",
                message: "Try a workout title or exercise name."
            )
        } else {
            SurfaceCard(padding: 0) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(filteredCompletedSessions.enumerated()), id: \.element.id) { index, session in
                        NavigationLink(value: HistoryRoute.workout(session.id)) {
                            WorkoutHistoryRow(
                                session: session,
                                presentation: .historyList,
                                showsDivider: index < filteredCompletedSessions.count - 1
                            )
                        }
                        .buttonStyle(HistoryOverviewRowButtonStyle())
                        .accessibilityIdentifier("WorkoutHistoryButton-\(index)")
                    }
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
                        .buttonStyle(HistoryOverviewRowButtonStyle())
                        .accessibilityIdentifier("ExerciseHistoryButton-\(index)")
                    }
                }
            }
        }
    }
}

/// Caches the resolved Exercise History between `HistoryView` body updates.
/// The invalidation key reads only session-level fields: walking every logged
/// exercise and set on each update faults the whole history in on the main
/// thread. Changes below the session level still reach the key. Completed-workout
/// edits touch their session's `updatedAt`, and any save that changes completed
/// history bumps `savedHistoryChangeCount`. That includes sync, which applies
/// remote exercises and sets without touching their parent session.
@MainActor
@Observable
final class ExerciseHistoryViewState {
    @ObservationIgnored private let resolveHistory: ExerciseHistoryViewSnapshot.ResolveHistory
    @ObservationIgnored private var invalidationKey: ExerciseHistoryInvalidationKey?
    @ObservationIgnored private var currentSnapshot: ExerciseHistoryViewSnapshot?
    private var savedHistoryChangeCount = 0

    init(
        resolveHistory: @escaping ExerciseHistoryViewSnapshot.ResolveHistory = ExerciseHistorySummary.makeResolvedHistory
    ) {
        self.resolveHistory = resolveHistory
    }

    func snapshot(
        sessions: [WorkoutSession],
        exercises: [Exercise],
        ownerTokenIdentifier: String?
    ) -> ExerciseHistoryViewSnapshot {
        let nextKey = ExerciseHistoryInvalidationKey(
            sessions: sessions,
            exercises: exercises,
            ownerTokenIdentifier: ownerTokenIdentifier,
            savedHistoryChangeCount: savedHistoryChangeCount
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

    func recordSave(_ notification: Notification, in context: ModelContext) {
        if let savedContext = notification.object as? ModelContext,
           savedContext.container !== context.container {
            return
        }
        let changes = PreviousSetsCacheSaveChanges(notification: notification)
        guard ExerciseHistorySaveChanges(changes).affectsCompletedHistory(in: context) else { return }
        savedHistoryChangeCount &+= 1
    }
}

/// Exercise History reads only sessions, logged exercises, sets, and exercises,
/// so saves of other models are ignored. Saves confined to an active workout are
/// ignored too, so logging sets does not rebuild completed history.
///
/// Inserted models are not classified. When `HistoryView` receives `didSave`,
/// they may not be registered under their saved identifiers yet, so their
/// session can't be looked up. They don't need to be: a new session or exercise
/// changes the History queries, and a new logged exercise or set changes its
/// parent's relationship, so the parent is saved as updated.
struct ExerciseHistorySaveChanges {
    private let changes: PreviousSetsCacheSaveChanges

    init(_ changes: PreviousSetsCacheSaveChanges) {
        self.changes = changes
    }

    @MainActor
    func affectsCompletedHistory(in context: ModelContext) -> Bool {
        if changes.invalidatedAllIdentifiers {
            return true
        }
        // A deleted model can no longer be traced to its session.
        if changes.deletedIDs.contains(where: Self.isHistoryInput) {
            return true
        }
        return changes.updatedIDs.contains { identifier in
            Self.isHistoryInput(identifier)
                && !Self.belongsToActiveWorkout(identifier, in: context)
        }
    }

    private static func isHistoryInput(_ identifier: PersistentIdentifier) -> Bool {
        switch identifier.entityName {
        case String(describing: WorkoutSession.self),
             String(describing: LoggedExercise.self),
             String(describing: LoggedSet.self),
             String(describing: Exercise.self):
            true
        default:
            false
        }
    }

    @MainActor
    private static func belongsToActiveWorkout(
        _ identifier: PersistentIdentifier,
        in context: ModelContext
    ) -> Bool {
        let session: WorkoutSession?
        switch identifier.entityName {
        case String(describing: WorkoutSession.self):
            session = context.registeredModel(for: identifier)
        case String(describing: LoggedExercise.self):
            let loggedExercise: LoggedExercise? = context.registeredModel(for: identifier)
            session = loggedExercise?.session
        case String(describing: LoggedSet.self):
            let set: LoggedSet? = context.registeredModel(for: identifier)
            session = set?.loggedExercise?.session
        default:
            session = nil
        }
        return session?.status == .active
    }
}

private struct ExerciseHistoryInvalidationKey: Equatable {
    private struct SessionContribution: Equatable {
        let id: UUID
        let startedAt: Date
        let updatedAt: Date
    }

    private struct ExerciseDefinition: Equatable {
        let id: UUID
        let name: String
        let equipmentRaw: String
    }

    private let ownerTokenIdentifier: String?
    private let savedHistoryChangeCount: Int
    private let sessions: [SessionContribution]
    private let exercises: [ExerciseDefinition]

    init(
        sessions: [WorkoutSession],
        exercises: [Exercise],
        ownerTokenIdentifier: String?,
        savedHistoryChangeCount: Int
    ) {
        self.ownerTokenIdentifier = ownerTokenIdentifier
        self.savedHistoryChangeCount = savedHistoryChangeCount
        self.sessions = WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier
        ).map { session in
            SessionContribution(
                id: session.id,
                startedAt: session.startedAt,
                updatedAt: session.updatedAt
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
