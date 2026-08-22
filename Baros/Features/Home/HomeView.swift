import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(SyncScheduler.self) private var syncScheduler
    @Bindable var navigationState: AppNavigationState
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    let activeSession: WorkoutSession?
    let presentWorkout: () -> Void
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var startSheetPresentation: HomeStartSheetPresentation?
    @State private var presentsWorkoutAfterStart = false
    @State private var sessionIDHiddenDuringLaunchHandoff: UUID?

    var body: some View {
        let ownerTokenIdentifier = syncScheduler.currentOwnerTokenIdentifier

        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let content = HomeContent(
                sessions: sessions,
                ownerTokenIdentifier: ownerTokenIdentifier,
                now: timeline.date
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(timeline.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                        .font(.caption.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(0.8)
                        .foregroundStyle(AppTheme.textSecondary)

                    Text("Home")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .padding(.top, 3)
                        .padding(.bottom, 18)
                        .accessibilityIdentifier("HomeTitle")

                    HomePrimaryWorkoutButton(
                        presentation: HomePrimaryWorkoutPresentation(
                            activeSession: activeSession,
                            sessionIDHiddenDuringLaunchHandoff: sessionIDHiddenDuringLaunchHandoff,
                            now: timeline.date
                        ),
                        action: primaryWorkoutAction
                    )

                    HomeWeeklyActivityView(activity: content.weeklyActivity)

                    if let lastWorkout = content.lastWorkout {
                        HomeLastWorkoutView(session: lastWorkout) {
                            navigationState.openWorkoutHistory(lastWorkout.id)
                        }
                    }
                }
                .padding(AppTheme.shellPadding)
            }
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $startSheetPresentation, onDismiss: presentStartedWorkoutIfNeeded) { _ in
                HomeStartWorkoutSheet(
                    content: content,
                    activeWorkoutEngine: activeWorkoutEngine,
                    onWorkoutStarted: { session in
                        sessionIDHiddenDuringLaunchHandoff = session.id
                        presentsWorkoutAfterStart = true
                    }
                )
            }
            .onChange(of: navigationState.isActiveWorkoutPresented) { wasPresented, isPresented in
                if wasPresented && !isPresented {
                    sessionIDHiddenDuringLaunchHandoff = nil
                }
            }
            .onChange(of: activeSession?.id) { _, activeSessionID in
                guard let sessionIDHiddenDuringLaunchHandoff else { return }
                if activeSessionID != sessionIDHiddenDuringLaunchHandoff {
                    self.sessionIDHiddenDuringLaunchHandoff = nil
                }
            }
        }
    }

    private func primaryWorkoutAction() {
        if activeSession != nil {
            presentWorkout()
        } else {
            startSheetPresentation = HomeStartSheetPresentation()
        }
    }

    private func presentStartedWorkoutIfNeeded() {
        guard presentsWorkoutAfterStart else { return }
        presentsWorkoutAfterStart = false
        navigationState.selectedTab = .home
        presentWorkout()
    }
}

private struct HomeStartSheetPresentation: Identifiable {
    let id = UUID()
}

private struct HomePrimaryWorkoutButton: View {
    private struct Layout {
        let systemImage: String
        let iconDimension: CGFloat
        let minimumHeight: CGFloat
        let verticalPadding: CGFloat
        let titleFont: Font
    }

    let presentation: HomePrimaryWorkoutPresentation
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    private var layout: Layout {
        if presentation.isActive {
            return Layout(
                systemImage: "figure.strengthtraining.traditional",
                iconDimension: 50,
                minimumHeight: 112,
                verticalPadding: 19,
                titleFont: .title2.weight(.bold)
            )
        }

        return Layout(
            systemImage: "plus",
            iconDimension: 50,
            minimumHeight: 100,
            verticalPadding: 16,
            titleFont: .title3.weight(.bold)
        )
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: layout.systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.onBrandAccent)
                    .frame(width: layout.iconDimension, height: layout.iconDimension)
                    .background(AppTheme.brandAccentGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(AppTheme.onBrandAccent.opacity(0.2), lineWidth: 1)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(presentation.title)
                        .font(layout.titleFont)
                        .foregroundStyle(AppTheme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = presentation.detail {
                        Text(detail)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, layout.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: layout.minimumHeight, alignment: .leading)
            .background(AppTheme.focusSurface, in: shape)
            .overlay(shape.strokeBorder(AppTheme.brandAccentForeground.opacity(0.9), lineWidth: 3))
            .overlay {
                shape
                    .inset(by: 4)
                    .strokeBorder(AppTheme.brandAccentForeground.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: AppTheme.brandAccentGlow, radius: 18, y: 8)
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.title)
            .accessibilityValue(presentation.detail ?? "")
            .accessibilityIdentifier(presentation.accessibilityIdentifier)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeWeeklyActivityView: View {
    let activity: HomeWeeklyActivity

    private var workoutCountLabel: String {
        "\(activity.completedWorkoutCount) "
            + (activity.completedWorkoutCount == 1 ? "workout" : "workouts")
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                Spacer()
                Text(workoutCountLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .padding(.horizontal, 2)

            SurfaceCard(padding: 15) {
                HStack(spacing: 4) {
                    ForEach(activity.days) { day in
                        HomeWeekDayView(day: day)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(activity.accessibilityDescription())
            .accessibilityIdentifier("HomeWeeklyActivity")
        }
        .padding(.top, 25)
    }
}

private struct HomeWeekDayView: View {
    let day: HomeWeeklyActivity.Day

    private var markerText: String {
        if day.hasCompletedWorkout {
            return "✓"
        }
        if day.isToday {
            return day.date.formatted(.dateTime.day())
        }
        return "—"
    }

    var body: some View {
        VStack(spacing: 7) {
            Text(day.date.formatted(.dateTime.weekday(.narrow)))
                .font(.caption2.weight(.bold))
                .foregroundStyle(day.isToday ? AppTheme.brandAccentForeground : AppTheme.textTertiary)

            Text(markerText)
                .font(.caption.weight(.bold))
                .foregroundStyle(day.hasCompletedWorkout ? AppTheme.onBrandAccent : AppTheme.textSecondary)
                .frame(width: 32, height: 32)
                .background(
                    day.hasCompletedWorkout ? AppTheme.brandAccentFill : AppTheme.recessedSurface,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
                .overlay {
                    if day.isToday {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(AppTheme.brandAccentForeground.opacity(0.42), lineWidth: 2)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }
}

private struct HomeLastWorkoutView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let session: WorkoutSession
    let openWorkout: () -> Void

    private var metrics: WorkoutMetrics {
        WorkoutMetrics(session: session)
    }

    var body: some View {
        Button(action: openWorkout) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Last Workout")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)

                    Spacer()

                    Text("View")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(AppTheme.brandAccentForeground)
                }
                .padding(.horizontal, 2)

                SurfaceCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 12) {
                            Capsule()
                                .fill(AppTheme.brandAccentFill)
                                .frame(width: 4, height: 48)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(session.title)
                                    .font(.headline)
                                    .foregroundStyle(AppTheme.textPrimary)

                                Text(WorkoutFormatters.compactDate(session.startedAt))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(AppTheme.textSecondary)
                            }

                            Spacer(minLength: 8)

                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textTertiary)
                                .padding(.top, 4)
                                .accessibilityHidden(true)
                        }

                        Group {
                            if dynamicTypeSize.isAccessibilitySize {
                                VStack(alignment: .leading, spacing: 6) {
                                    workoutMetadata
                                }
                            } else {
                                HStack(spacing: 12) {
                                    workoutMetadata
                                }
                            }
                        }
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textTertiary)

                        Divider()

                        VStack(spacing: 10) {
                            ForEach(session.sortedLoggedExercises.prefix(3)) { loggedExercise in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(loggedExercise.exerciseSnapshotName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(AppTheme.textPrimary)
                                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Spacer(minLength: 8)

                                    let setCount = loggedExercise.sortedSets.lazy.filter(\.isCompleted).count
                                    Text("\(setCount) \(setCount == 1 ? "set" : "sets")")
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(AppTheme.textSecondary)
                                }
                            }

                            let remainingExerciseCount = max(session.sortedLoggedExercises.count - 3, 0)
                            if remainingExerciseCount > 0 {
                                Text("+ \(remainingExerciseCount) more")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(AppTheme.brandAccentForeground)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("HomeLastWorkoutButton")
        .padding(.top, 25)
        .padding(.bottom, 12)
    }

    @ViewBuilder
    private var workoutMetadata: some View {
        Label(AppTheme.formatDuration(metrics.durationSeconds), systemImage: "clock")
        Text("\(session.visibleExerciseCount) exercises")
        Text("\(metrics.completedSetCount) sets")
    }
}
