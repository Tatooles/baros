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
    @State private var openedWorkoutID: UUID?
    @State private var ringWorkoutChoice: HomeRingWorkoutChoice?
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
            let layout = HomeLayout(size: geometry.size, safeAreaInsets: geometry.safeAreaInsets)
            ScrollView(showsIndicators: false) {
                Group {
                    if layout.isWide {
                        // Landscape windows, such as the iPhone Duo's inner display, keep the
                        // ring and the actions in their own halves so neither crosses the fold.
                        HStack(alignment: .center, spacing: HomeLayout.columnSpacing) {
                            VStack(alignment: .leading, spacing: 0) {
                                header
                                WorkoutRecoveryNotice()
                                Spacer(minLength: 16)
                                ringSection(diameter: layout.ringDiameter, content: content)
                                Spacer(minLength: 0)
                            }
                            .frame(width: layout.leadingColumnWidth)
                            actions(content: content, primaryPresentation: primary, hasHistory: ring.totalWorkouts > 0,
                                    bleedsPills: false)
                                .frame(maxWidth: HomeLayout.actionsMaxWidth)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            header
                            WorkoutRecoveryNotice()
                            // Matching flexible spacers center the ring between the
                            // header and the actions instead of crowding the bottom.
                            Spacer(minLength: 20)
                            ringSection(diameter: layout.ringDiameter, content: content)
                            Spacer(minLength: 28)
                            actions(content: content, primaryPresentation: primary, hasHistory: ring.totalWorkouts > 0,
                                    bleedsPills: true)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 14)
                .padding(.bottom, 24)
                .frame(minHeight: geometry.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .accessibilityIdentifier("HomeScrollView")
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $openedWorkoutID) { id in
            WorkoutHistoryDestinationView(sessionID: id)
        }
        .confirmationDialog("Open a workout", isPresented: Binding(
            get: { ringWorkoutChoice != nil }, set: { if !$0 { ringWorkoutChoice = nil } }
        ), titleVisibility: .hidden, presenting: ringWorkoutChoice) { choice in
            ForEach(choice.options) { option in
                Button(option.label) { openedWorkoutID = option.id }
            }
        }
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
            if WorkoutRecovery.hiddenSessions(in: sessions,
                owner: currentOwnerCoordinator.localDataOwnerTokenIdentifier).isEmpty {
                SignedOutReminderBanner(bottomSpacing: 0)
                    .padding(.top, 12)
            }
        }
    }

    private func ringSection(diameter: CGFloat, content: HomeContent) -> some View {
        VStack(spacing: 12) {
            HomeYearRingView(model: ring, period: effectivePeriod,
                             diameter: diameter,
                             replayID: replayID,
                             exerciseCount: { id in
                                 content.completedSessions.first { $0.id == id }?.sortedLoggedExercises.count
                             },
                             open: { ids in openRingWorkouts(ids, content: content) },
                             holdsSelection: ringWorkoutChoice != nil)
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
    }

    /// Returns true when it presented a picker rather than opening a workout.
    private func openRingWorkouts(_ ids: [UUID], content: HomeContent) -> Bool {
        let sessions = ids.compactMap { id in content.completedSessions.first { $0.id == id } }
        guard sessions.count > 1 else {
            openedWorkoutID = sessions.first?.id
            return false
        }
        let sameDay = sessions.allSatisfy { Calendar.current.isDate($0.startedAt, inSameDayAs: sessions[0].startedAt) }
        ringWorkoutChoice = HomeRingWorkoutChoice(options: sessions.map { session in
            let when = sameDay ? session.startedAt.formatted(date: .omitted, time: .shortened)
                : session.startedAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            return HomeRingWorkoutChoice.Option(id: session.id, label: "\(session.title) · \(when)")
        })
        return true
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

    private func actions(content: HomeContent, primaryPresentation: HomePrimaryWorkoutPresentation, hasHistory: Bool,
                         bleedsPills: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            if hasHistory, !primaryPresentation.isActive {
                let quickStartWorkouts = content.quickStartWorkouts
                if !quickStartWorkouts.isEmpty { livePills(quickStartWorkouts, bleeds: bleedsPills) }
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

    private func livePills(_ quickStartWorkouts: [HomeQuickStartWorkout], bleeds: Bool) -> some View {
        HomeStartFromPills(titles: quickStartWorkouts.map(\.title), bleedsToScreenEdges: bleeds) { index in
            quickStartSelection = HomeQuickStartSelection(id: quickStartWorkouts[index].id)
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

/// Chooses between the phone column and the two-column layout that wide,
/// short windows (the iPhone Duo's inner display) use. The columns split at the
/// window's midpoint, where the Duo folds, rather than the middle of the safe area,
/// which the side tab rail pushes left.
struct HomeLayout: Equatable {
    static let columnSpacing: CGFloat = 48
    static let actionsMaxWidth: CGFloat = 420
    static let horizontalPadding: CGFloat = 24
    /// Header, period picker, and padding share the wide layout's height with the ring.
    static let wideVerticalChrome: CGFloat = 200
    static let maxRingDiameter: CGFloat = 350

    let isWide: Bool
    let ringDiameter: CGFloat
    /// Width of the ring column in the wide layout; it ends half a gap before the window's midpoint.
    let leadingColumnWidth: CGFloat

    init(size: CGSize, safeAreaInsets: EdgeInsets = EdgeInsets()) {
        isWide = size.width > size.height && size.width >= 600
        if isWide {
            let windowMidpoint = (size.width + safeAreaInsets.leading + safeAreaInsets.trailing) / 2
                - safeAreaInsets.leading
            let contentWidth = size.width - Self.horizontalPadding * 2
            leadingColumnWidth = min(max(0, windowMidpoint - Self.horizontalPadding - Self.columnSpacing / 2),
                                     contentWidth - Self.columnSpacing)
            ringDiameter = max(0, min(leadingColumnWidth * 0.80, size.height - Self.wideVerticalChrome,
                                      Self.maxRingDiameter))
        } else {
            leadingColumnWidth = size.width
            ringDiameter = min(size.width * 0.80, Self.maxRingDiameter)
        }
    }
}

private struct HomeStartSheetPresentation: Identifiable {
    let id = UUID()
}

/// Several workouts share the opened slot, so Home asks which one to show.
private struct HomeRingWorkoutChoice {
    struct Option: Identifiable {
        let id: UUID
        let label: String
    }

    let options: [Option]
}

private struct HomeQuickStartSelection: Identifiable {
    let id: UUID
}

/// Shares the capsule shape and centered label of the app's other primary
/// actions, so Home's Start Workout matches the one a tap later.
private struct HomePrimaryWorkoutButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Grows with text size so the main action stays a generous target.
    @ScaledMetric(relativeTo: .title3) private var scaledMinHeight: CGFloat = 60

    let presentation: HomePrimaryWorkoutPresentation
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: presentation.isActive ? "figure.strengthtraining.traditional" : "plus")
                        .font(.title3.weight(.bold))
                        .accessibilityHidden(true)
                }

                VStack(spacing: 2) {
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
                .multilineTextAlignment(.center)
            }
            .foregroundStyle(AppTheme.onBrandAccent)
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: min(scaledMinHeight, 120))
            .background(AppTheme.brandAccentGradient, in: Capsule())
            .contentShape(Capsule())
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
    /// The phone column scrolls the pills edge to edge. The wide layout keeps
    /// them inside the actions column so they never slide under the tab rail.
    let bleedsToScreenEdges: Bool
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
            .contentMargins(.horizontal, bleedsToScreenEdges ? 24 : 0, for: .scrollContent)
            .padding(.horizontal, bleedsToScreenEdges ? -24 : 0)
            // Only the wide layout clips; the expanded rectangle leaves the phone column as it was.
            .clipShape(Rectangle().inset(by: bleedsToScreenEdges ? -1_000 : 0))
        }
    }
}


/// Value comparison invalidates bucketing only when history or its calendar window changes.
private struct HomeRingInput: Equatable {
    let workouts: [RingWorkout]
    let day: Date
    let calendar: Calendar
}
