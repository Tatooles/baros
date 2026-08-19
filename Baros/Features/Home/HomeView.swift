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
                            now: timeline.date
                        ),
                        action: primaryWorkoutAction
                    )

                    HomeWeeklyActivityView(activity: content.weeklyActivity)

                    if let recentWorkout = content.recentWorkout {
                        HomeRecentWorkoutView(session: recentWorkout) {
                            navigationState.openWorkoutHistory(recentWorkout.id)
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
                    onWorkoutStarted: { presentsWorkoutAfterStart = true }
                )
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
    let presentation: HomePrimaryWorkoutPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(presentation.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(AppTheme.onBrandAccent)
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = presentation.detail {
                        Text(detail)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.onBrandAccent.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(AppTheme.onBrandAccent.opacity(0.82))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, minHeight: 122, alignment: .leading)
            .background(
                AppTheme.brandAccentGradient,
                in: RoundedRectangle(cornerRadius: 32, style: .continuous)
            )
            .shadow(color: AppTheme.brandAccentGlow, radius: 20, y: 9)
            .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
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

private struct HomeRecentWorkoutView: View {
    let session: WorkoutSession
    let openWorkout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Workout")
                .font(.title3.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .padding(.horizontal, 2)

            Button(action: openWorkout) {
                WorkoutHistoryRow(session: session)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("HomeRecentWorkoutButton")
        }
        .padding(.top, 25)
        .padding(.bottom, 12)
    }
}
