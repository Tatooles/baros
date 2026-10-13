import SwiftData
import SwiftUI

struct HomeView: View {
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var navigationState: AppNavigationState
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    let activeSession: WorkoutSession?
    let presentWorkout: () -> Void
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @State private var startSheetPresentation: HomeStartSheetPresentation?
    @State private var quickStartSelection: HomeQuickStartSelection?
    @State private var presentsWorkoutAfterStart = false
    @State private var sessionIDHiddenDuringLaunchHandoff: UUID?
    @State private var now = Date.now
    @State private var replayID = 0
    @State private var ring = HomeRingModel(workouts: [], now: .now, calendar: .current)
    @AppStorage(HomeRingPeriod.storageKey) private var periodRaw = HomeRingPeriod.month.rawValue
    #if DEBUG
    private let fixture = HomeRingFixture.launchFixture
    #endif

    var body: some View {
        let snapshotNow = Date.now
        let content = HomeContent(
            sessions: sessions,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
            now: snapshotNow
        )
        let ringInput = HomeRingInput(workouts: ringWorkouts(content: content, now: snapshotNow),
                                      day: Calendar.current.startOfDay(for: snapshotNow), calendar: .current)
        let primary = HomePrimaryWorkoutPresentation(
            activeSession: activeSession,
            sessionIDHiddenDuringLaunchHandoff: sessionIDHiddenDuringLaunchHandoff,
            now: now
        )

        GeometryReader { geometry in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    Spacer(minLength: 20).frame(maxHeight: 40)
                    VStack(spacing: 12) {
                        HomeYearRingView(model: ring, period: effectivePeriod,
                                         diameter: min(geometry.size.width * 0.80, 350),
                                         now: now, replayID: replayID)
                        Picker("History period", selection: $periodRaw) {
                            ForEach(HomeRingPeriod.allCases, id: \.rawValue) { period in
                                Text(period.title).tag(period.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 164)
                        .accessibilityLabel("Ring history period")
                        .accessibilityIdentifier("HomeRingPeriodPicker")
                        // Preserve the control's space so the ring/actions do not jump.
                        .opacity(ring.showsPeriodToggle ? 1 : 0)
                        .disabled(!ring.showsPeriodToggle)
                        .accessibilityHidden(!ring.showsPeriodToggle)
                    }
                    .frame(maxWidth: .infinity)
                    Spacer(minLength: 28)
                    actions(content: content, primaryPresentation: primary, hasHistory: ring.totalWorkouts > 0)
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 18)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("HomeScrollView")
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $startSheetPresentation, onDismiss: presentStartedWorkoutIfNeeded) { _ in
            HomeStartWorkoutSheet(content: content, activeWorkoutEngine: activeWorkoutEngine,
                                  onWorkoutStarted: handOffStartedWorkout)
        }
        .sheet(item: $quickStartSelection, onDismiss: presentStartedWorkoutIfNeeded) { selection in
            // Re-resolve against the Current Owner before displaying a past workout.
            HomeQuickStartReviewSheet(
                session: content.completedSessions.first { $0.id == selection.id },
                activeWorkoutEngine: activeWorkoutEngine,
                onWorkoutStarted: handOffStartedWorkout
            )
        }
        .onChange(of: ringInput, initial: true) { previousInput, input in
            now = .now
            ring = HomeRingModel(workouts: input.workouts, now: now, calendar: input.calendar)
            if previousInput != input { replaySweep() }
        }
        .onAppear { now = .now; replaySweep() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, navigationState.selectedTab == .home { now = .now; replaySweep() }
        }
        .onChange(of: periodRaw) { _, _ in replaySweep() }
        .onChange(of: currentOwnerCoordinator.localDataOwnerTokenIdentifier) { _, _ in replaySweep() }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in now = .now }
        .onReceive(NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)) { _ in now = .now }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in now = .now }
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

    private var period: HomeRingPeriod { HomeRingPeriod(rawValue: periodRaw) ?? .month }
    private var effectivePeriod: HomeRingPeriod { ring.showsPeriodToggle ? period : .month }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(now.formatted(.dateTime.weekday(.wide)))
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(AppTheme.textPrimary)
                .accessibilityIdentifier("HomeTitle")
            Text(now.formatted(.dateTime.month(.wide).day()))
                .font(.headline.weight(.medium))
                .foregroundStyle(AppTheme.textSecondary)
            SignedOutReminderBanner(bottomSpacing: 0)
                .padding(.top, 12)
        }
    }

    private func replaySweep() {
        replayID += 1
    }

    private func ringWorkouts(content: HomeContent, now: Date) -> [RingWorkout] {
        #if DEBUG
        if fixture != .live { return fixture.workouts(now: now, calendar: .current) }
        #endif
        return RingWorkout.ringWorkouts(from: content.completedSessions, now: now)
    }

    private func actions(content: HomeContent, primaryPresentation: HomePrimaryWorkoutPresentation, hasHistory: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if hasHistory, !primaryPresentation.isActive {
                if !content.quickStartWorkouts.isEmpty { livePills(content: content) }
            }
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                let presentation = HomePrimaryWorkoutPresentation(
                    activeSession: activeSession,
                    sessionIDHiddenDuringLaunchHandoff: sessionIDHiddenDuringLaunchHandoff,
                    now: timeline.date
                )
                HomePrimaryWorkoutButton(presentation: presentation, action: primaryWorkoutAction)
            }
        }
    }

    private func livePills(content: HomeContent) -> some View {
        HomeStartFromPills(titles: content.quickStartWorkouts.map(\.title)) { index in
            quickStartSelection = HomeQuickStartSelection(id: content.quickStartWorkouts[index].id)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var iconDimension: CGFloat = 40

    let presentation: HomePrimaryWorkoutPresentation
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: presentation.isActive ? "figure.strengthtraining.traditional" : "plus")
                        .font(.title3.weight(.bold))
                        .frame(width: iconDimension, height: iconDimension)
                        .background(AppTheme.onBrandAccent.opacity(0.18), in: Circle())
                        .accessibilityHidden(true)
                }

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

/// Recent workouts retain their review-and-start behavior with neutral styling.
private struct HomeStartFromPills: View {
    let titles: [String]
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Start from")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textSecondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { index, title in
                        Button { select(index) } label: {
                            Text(title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .padding(.horizontal, 15)
                                .padding(.vertical, 13)
                                .background(AppTheme.groupedSurface, in: Capsule())
                                .overlay { Capsule().strokeBorder(AppTheme.subtleBorder, lineWidth: 0.6) }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(title)
                        .accessibilityHint("Review and start this workout")
                        .accessibilityIdentifier("HomeQuickStartButton-\(index)")
                    }
                }
            }
            .contentMargins(.horizontal, 24, for: .scrollContent)
            .padding(.horizontal, -24)
        }
    }
}


/// Value comparison invalidates bucketing only when history or its calendar window changes.
private struct HomeRingInput: Equatable {
    let workouts: [RingWorkout]
    let day: Date
    let calendar: Calendar
}
