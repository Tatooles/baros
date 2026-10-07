import SwiftData
import SwiftUI

struct HomeView: View {
    private static let topPadding: CGFloat = 12
    private static let bottomPadding: CGFloat = 8
    private static let minimumActionSpacing: CGFloat = 20

    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var navigationState: AppNavigationState
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    let activeSession: WorkoutSession?
    let presentWorkout: () -> Void
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var startSheetPresentation: HomeStartSheetPresentation?
    @State private var quickStartSelection: HomeQuickStartSelection?
    @State private var presentsWorkoutAfterStart = false
    @State private var sessionIDHiddenDuringLaunchHandoff: UUID?
    @State private var layoutMetrics = HomeLayoutMetrics()
    @State private var calendarDayChoice: HomeTrainingCalendar.Day?

    var body: some View {
        let ownerTokenIdentifier = currentOwnerCoordinator.localDataOwnerTokenIdentifier

        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            let content = HomeContent(
                sessions: sessions,
                ownerTokenIdentifier: ownerTokenIdentifier,
                now: timeline.date
            )
            let primaryPresentation = HomePrimaryWorkoutPresentation(
                activeSession: activeSession,
                sessionIDHiddenDuringLaunchHandoff: sessionIDHiddenDuringLaunchHandoff,
                now: timeline.date
            )
            // Accessibility sizes put the actions first and keep the calendar at its minimum.
            let visibleWeeks = content.trainingCalendar.visibleWeeks(
                fitting: dynamicTypeSize.isAccessibilitySize ? 0 : layoutMetrics.calendarWeekCapacity(
                    rowSpacing: HomeTrainingCalendarView.rowSpacing,
                    fixedSpacing: Self.topPadding + Self.bottomPadding + Self.minimumActionSpacing
                )
            )

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(timeline.date.formatted(.dateTime.weekday(.wide)))
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(AppTheme.textPrimary)
                            .accessibilityIdentifier("HomeTitle")

                        Text(timeline.date.formatted(.dateTime.month(.wide).day()))
                            .font(.headline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.top, 2)
                            .padding(.bottom, 20)

                        SignedOutReminderBanner(bottomSpacing: 18)
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                        layoutMetrics.headerHeight = $0
                    }

                    if dynamicTypeSize.isAccessibilitySize {
                        actions(content: content, primaryPresentation: primaryPresentation)
                            .padding(.bottom, 24)
                        trainingCalendar(content.trainingCalendar, visibleWeeks: visibleWeeks)
                    } else {
                        trainingCalendar(content.trainingCalendar, visibleWeeks: visibleWeeks)
                        Spacer(minLength: Self.minimumActionSpacing)
                        actions(content: content, primaryPresentation: primaryPresentation)
                    }
                }
                .padding(.horizontal, AppTheme.shellPadding)
                .padding(.top, Self.topPadding)
                .padding(.bottom, Self.bottomPadding)
                .frame(minHeight: layoutMetrics.viewportHeight, alignment: .top)
            }
            // The page fills the viewport exactly, so only scroll when content overflows.
            .scrollBounceBehavior(.basedOnSize)
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                // Already excludes the safe areas (status bar, tab bar).
                geometry.containerSize.height
            } action: { _, height in
                layoutMetrics.viewportHeight = height
            }
            .background(AppTheme.canvasBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $startSheetPresentation, onDismiss: presentStartedWorkoutIfNeeded) { _ in
                HomeStartWorkoutSheet(
                    content: content,
                    activeWorkoutEngine: activeWorkoutEngine,
                    onWorkoutStarted: handOffStartedWorkout
                )
            }
            .sheet(item: $quickStartSelection, onDismiss: presentStartedWorkoutIfNeeded) { selection in
                // Resolve from the current owner's visible workouts on every render so an owner change never
                // leaves the previous owner's workout on screen.
                HomeQuickStartReviewSheet(
                    session: content.completedSessions.first { $0.id == selection.id },
                    activeWorkoutEngine: activeWorkoutEngine,
                    onWorkoutStarted: handOffStartedWorkout
                )
            }
            .confirmationDialog(
                "Open Workout",
                isPresented: Binding(
                    get: { calendarDayChoice != nil },
                    set: { if !$0 { calendarDayChoice = nil } }
                ),
                titleVisibility: .visible,
                presenting: calendarDayChoice
            ) { day in
                ForEach(day.workouts) { workout in
                    Button("\(workout.title) · \(workout.startedAt.formatted(date: .omitted, time: .shortened))") {
                        navigationState.openWorkoutHistory(workout.id)
                    }
                }
            }
            .onChange(of: navigationState.fullyPresentedActiveWorkoutID) { _, presentedSessionID in
                if presentedSessionID == sessionIDHiddenDuringLaunchHandoff {
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

    private func trainingCalendar(
        _ trainingCalendar: HomeTrainingCalendar,
        visibleWeeks: ArraySlice<HomeTrainingCalendar.Week>
    ) -> some View {
        HomeTrainingCalendarView(
            trainingCalendar: trainingCalendar,
            visibleWeeks: visibleWeeks,
            layoutMetrics: $layoutMetrics,
            openDay: openCalendarDay
        )
        // A legible grid matters more than larger glyphs; VoiceOver reads the summary label instead.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func actions(
        content: HomeContent,
        primaryPresentation: HomePrimaryWorkoutPresentation
    ) -> some View {
        VStack(spacing: 12) {
            if !primaryPresentation.isActive, !content.quickStartWorkouts.isEmpty {
                HomeQuickStartRow(workouts: content.quickStartWorkouts) { workout in
                    quickStartSelection = HomeQuickStartSelection(id: workout.id)
                }
            }

            HomePrimaryWorkoutButton(
                presentation: primaryPresentation,
                action: primaryWorkoutAction
            )
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            layoutMetrics.actionsHeight = $0
        }
    }

    private func openCalendarDay(_ day: HomeTrainingCalendar.Day) {
        if day.workouts.count == 1, let workout = day.workouts.first {
            navigationState.openWorkoutHistory(workout.id)
        } else if day.workouts.count > 1 {
            calendarDayChoice = day
        }
    }

    private func primaryWorkoutAction() {
        if activeSession != nil {
            presentWorkout()
        } else {
            startSheetPresentation = HomeStartSheetPresentation()
        }
    }

    private func handOffStartedWorkout(_ session: WorkoutSession) {
        sessionIDHiddenDuringLaunchHandoff = session.id
        presentsWorkoutAfterStart = true
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

private struct HomeQuickStartSelection: Identifiable {
    let id: UUID
}

private struct HomePrimaryWorkoutButton: View {
    @ScaledMetric(relativeTo: .title3) private var iconDimension: CGFloat = 40

    let presentation: HomePrimaryWorkoutPresentation
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: presentation.isActive ? "figure.strengthtraining.traditional" : "plus")
                    .font(.title3.weight(.bold))
                    .frame(width: iconDimension, height: iconDimension)
                    .background(AppTheme.onBrandAccent.opacity(0.18), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.title)
                        .font(.title3.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    if let detail = presentation.detail {
                        Text(detail)
                            .font(.subheadline.weight(.semibold))
                            .opacity(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.headline.weight(.bold))
                    .accessibilityHidden(true)
            }
            .foregroundStyle(AppTheme.onBrandAccent)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .background(AppTheme.brandAccentGradient, in: shape)
            .shadow(color: AppTheme.brandAccentGlow, radius: 14, y: 6)
            .contentShape(shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(presentation.title)
            .accessibilityValue(presentation.detail ?? "")
            .accessibilityIdentifier(presentation.accessibilityIdentifier)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeTrainingCalendarView: View {
    /// Rows carry their own vertical padding so completed days get taller tap targets.
    static let rowSpacing: CGFloat = 0
    private static let rowPadding: CGFloat = 5

    @ScaledMetric(relativeTo: .caption2) private var weekLabelWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .footnote) private var countWidth: CGFloat = 26
    @ScaledMetric(relativeTo: .caption) private var markerSize: CGFloat = 28

    let trainingCalendar: HomeTrainingCalendar
    let visibleWeeks: ArraySlice<HomeTrainingCalendar.Week>
    @Binding var layoutMetrics: HomeLayoutMetrics
    let openDay: (HomeTrainingCalendar.Day) -> Void

    var body: some View {
        SurfaceCard(padding: 16) {
            VStack(spacing: Self.rowPadding) {
                weekdayHeader

                VStack(spacing: Self.rowSpacing) {
                    ForEach(visibleWeeks) { week in
                        weekRow(week)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    layoutMetrics.calendarRowsHeight = height
                    layoutMetrics.calendarRowCount = visibleWeeks.count
                }

                if !trainingCalendar.hasCompletedWorkouts {
                    Text("Each workout you finish adds a check here.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
            layoutMetrics.calendarCardHeight = $0
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Training calendar")
        .accessibilityIdentifier("HomeTrainingCalendar")
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: weekLabelWidth, height: 1)
            ForEach(visibleWeeks.last?.days ?? []) { day in
                Text(day.date.formatted(.dateTime.weekday(.narrow)))
                    .frame(maxWidth: .infinity)
            }
            Color.clear.frame(width: countWidth, height: 1)
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(AppTheme.textTertiary)
        .accessibilityHidden(true)
    }

    private func weekRow(_ week: HomeTrainingCalendar.Week) -> some View {
        HStack(spacing: 0) {
            // VoiceOver reads the week summary here, then each completed day as a button.
            Text(week.isCurrent ? "This week" : week.start.formatted(.dateTime.month(.abbreviated).day()))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(week.isCurrent ? AppTheme.brandAccentForeground : AppTheme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: weekLabelWidth, alignment: .leading)
                .padding(.vertical, Self.rowPadding)
                .accessibilityLabel(trainingCalendar.accessibilityLabel(for: week))
                .accessibilityIdentifier(week.isCurrent ? "HomeTrainingCalendarCurrentWeek" : "HomeTrainingCalendarWeek")

            ForEach(week.days) { day in
                if day.workouts.isEmpty {
                    dayCell(day)
                        .accessibilityHidden(true)
                } else {
                    Button { openDay(day) } label: {
                        dayCell(day)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(trainingCalendar.accessibilityLabel(for: day))
                    .accessibilityHint(day.workouts.count == 1 ? "Opens in History" : "Choose a workout to open in History")
                    .accessibilityIdentifier(day.isToday ? "HomeTrainingCalendarToday" : "HomeTrainingCalendarDay")
                }
            }

            Text("\(week.completedWorkoutCount)")
                .font(.footnote.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(week.completedWorkoutCount > 0 ? AppTheme.textPrimary : AppTheme.textTertiary)
                .frame(width: countWidth, alignment: .trailing)
                .padding(.vertical, Self.rowPadding)
                .accessibilityHidden(true)
        }
    }

    private func dayCell(_ day: HomeTrainingCalendar.Day) -> some View {
        dayMarker(day)
            .frame(maxWidth: markerSize, maxHeight: markerSize)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Self.rowPadding)
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private func dayMarker(_ day: HomeTrainingCalendar.Day) -> some View {
        ZStack {
            switch day.state {
            case .completed:
                Circle()
                    .fill(AppTheme.brandAccentFill)
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(AppTheme.onBrandAccent)
            case .noWorkout:
                Circle()
                    .fill(AppTheme.recessedSurface)
            case .upcoming:
                Circle()
                    .strokeBorder(AppTheme.subtleBorder)
            case .beforeFirstWorkout:
                Color.clear
            }

            if day.isToday {
                Circle()
                    .strokeBorder(AppTheme.brandAccentForeground, lineWidth: 2)
            }
        }
    }
}

private struct HomeQuickStartRow: View {
    @ScaledMetric(relativeTo: .headline) private var cardWidth: CGFloat = 168

    let workouts: [HomeQuickStartWorkout]
    let start: (HomeQuickStartWorkout) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    Button { start(workout) } label: {
                        HomeQuickStartCard(workout: workout)
                            .frame(width: cardWidth)
                            .frame(maxHeight: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Review and start this workout")
                    .accessibilityIdentifier("HomeQuickStartButton-\(index)")
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .contentMargins(.horizontal, AppTheme.shellPadding, for: .scrollContent)
        .padding(.horizontal, -AppTheme.shellPadding)
    }
}

private struct HomeQuickStartCard: View {
    let workout: HomeQuickStartWorkout

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(workout.title)
                    .font(.headline)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "arrow.counterclockwise")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .accessibilityHidden(true)
            }

            Text(workout.lastCompletedDescription)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)

            // One line per exercise so a long name can't hide the ones after it.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(workout.previewExerciseNames.enumerated()), id: \.offset) { _, name in
                    Text(name)
                        .lineLimit(1)
                }
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(AppTheme.textSecondary)
            .padding(.top, 2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTheme.groupedSurface, in: shape)
        .overlay(shape.strokeBorder(AppTheme.subtleBorder))
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            ([workout.title, workout.lastCompletedDescription] + workout.previewExerciseNames)
                .joined(separator: ", ")
        )
    }
}
