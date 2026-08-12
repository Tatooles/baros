import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(SyncScheduler.self) private var syncScheduler
    @Bindable var navigationState: AppNavigationState
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    private var completedSessions: [WorkoutSession] {
        WorkoutSession.visibleCompletedSessions(
            from: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        )
    }

    var body: some View {
        let exerciseHistorySnapshot = ExerciseHistoryViewSnapshot(
            sessions: sessions,
            exercises: exercises,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
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
        .background(AppTheme.subtleBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: HistoryRoute.self) { route in
            switch route {
            case .exercise(let exerciseRoute):
                if let summary = exerciseHistorySnapshot.resolvedHistory.summary(for: exerciseRoute) {
                    ExerciseHistoryDetailView(summary: summary)
                } else {
                    EmptyStateView(
                        title: "No Exercise History",
                        message: "Completed sets for this exercise will appear here."
                    )
                    .background(AppTheme.subtleBackground.ignoresSafeArea())
                }
            }
        }
    }

    @ViewBuilder
    private var workoutContent: some View {
        if completedSessions.isEmpty {
            EmptyStateView(title: "No Workouts Yet", message: "Finished workouts will appear here.")
        } else {
            VStack(spacing: 10) {
                ForEach(Array(completedSessions.enumerated()), id: \.element.id) { index, session in
                    NavigationLink {
                        WorkoutHistoryDetailView(session: session)
                    } label: {
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
            EmptyStateView(title: "No Exercise History", message: "Completed sets will build exercise history.")
        } else {
            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(summaries.enumerated()), id: \.element.id) { index, summary in
                        NavigationLink {
                            ExerciseHistoryDetailView(summary: summary)
                        } label: {
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
            resolveHistory(
                sessions,
                exercises,
                ownerTokenIdentifier
            )
        }
    }
}
