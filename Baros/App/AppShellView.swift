import SwiftData
import SwiftUI
import UIKit

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncScheduler.self) private var syncScheduler
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(\.syncRecoveryAction) private var syncRecoveryAction
    @Bindable var navigationState: AppNavigationState
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    let workoutLiveActivityCoordinator: WorkoutLiveActivityCoordinator
    private let firstRunStore = FirstRunExperienceStore()
    @State private var dismissedSyncFailureSignature: String?
    @State private var launchPresentation: LaunchExperiencePresentation?
    @State private var hasMadeLaunchExperienceDecision = false
    @State private var historySearchText = ""
    @State private var prepareActiveWorkoutForMinimization: (() -> Void)?
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \SyncOutboxEntry.updatedAt, order: .reverse) private var outboxEntries: [SyncOutboxEntry]

    private var activeSession: WorkoutSession? {
        WorkoutSession.visibleActiveSessions(
            from: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first
    }

    private var workoutLiveActivitySnapshot: WorkoutLiveActivitySnapshot? {
        activeSession.map(WorkoutLiveActivitySnapshot.init(session:))
    }

    private var activeV1OutboxEntries: [SyncOutboxEntry] {
        outboxEntries.filter { entry in
            guard entry.isActive else { return false }
            guard entry.entityKind?.isV1Synced == true else { return false }
            if let owner = syncScheduler.currentOwnerTokenIdentifier {
                return entry.ownerTokenIdentifier == owner || entry.ownerTokenIdentifier == nil
            }
            return false
        }
    }

    private var syncDisplayState: SyncStatusDisplayState {
        let activeEntries = activeV1OutboxEntries
        return SyncStatusDisplayState.make(
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
            isSyncing: syncScheduler.isSyncing,
            lastSyncedAt: syncScheduler.lastSyncedAt,
            lastFailureMessage: syncScheduler.lastFailure?.message,
            lastFailureReason: syncScheduler.lastFailure?.reason,
            pendingCount: activeEntries.filter { $0.status == .pending || $0.status == .inFlight }.count,
            failedCount: activeEntries.filter { $0.status == .failed }.count
        )
    }

    private var currentSyncFailureSignature: String? {
        var components: [String] = []
        if let lastFailure = syncScheduler.lastFailure {
            components.append("scheduler:\(lastFailure.occurredAt.timeIntervalSince1970):\(lastFailure.reason):\(lastFailure.message)")
        }
        let failedEntries = activeV1OutboxEntries
            .filter { $0.status == .failed }
            .sorted { lhs, rhs in lhs.id.uuidString < rhs.id.uuidString }
        for entry in failedEntries {
            components.append(
                [
                    entry.id.uuidString,
                    entry.entityKindRaw,
                    entry.operationRaw,
                    entry.statusRaw,
                    String(entry.attemptCount),
                    String(entry.updatedAt.timeIntervalSince1970),
                    entry.lastErrorMessage ?? "",
                ].joined(separator: "|")
            )
        }
        guard !components.isEmpty else { return nil }
        return components.joined(separator: "\n")
    }

    private var shouldShowGlobalSyncFailureBanner: Bool {
        SyncFailureNoticePresentation().shouldShowNotice(
            showsGlobalFailureNotice: syncDisplayState.showsGlobalFailureNotice,
            currentFailureSignature: currentSyncFailureSignature,
            dismissedFailureSignature: dismissedSyncFailureSignature
        )
    }

    var body: some View {
        tabShell
            .tint(AppTheme.brandAccentForeground)
            .tabBarMinimizeBehavior(.never)
            .safeAreaInset(edge: .bottom) {
                if shouldShowGlobalSyncFailureBanner {
                    GlobalSyncFailureBanner(
                        title: syncDisplayState.failureNoticeTitle ?? "Cloud sync failed",
                        message: syncDisplayState.failureNoticeMessage ?? "Your data is saved on this iPhone.",
                        retry: { syncRecoveryAction(.manualRetry) },
                        details: { navigationState.openSyncSettings() },
                        dismiss: { dismissGlobalSyncFailureBanner() }
                    )
                    .padding(.horizontal, AppTheme.shellPadding)
                    .padding(.bottom, 8)
                }
            }
            .sheet(isPresented: activeWorkoutPresentationBinding) {
                if let activeSession {
                    NavigationStack {
                        ZStack(alignment: .topTrailing) {
                            WorkoutSessionView(
                                session: activeSession,
                                engine: activeWorkoutEngine,
                                navigationState: navigationState,
                                onMinimizePreparationChanged: { action in
                                    prepareActiveWorkoutForMinimization = action
                                }
                            )

                            #if DEBUG
                            if ProcessInfo.processInfo.arguments.contains("--uitest-active-workout-current-owner-change-control") {
                                Button("Simulate Current Owner Change") {
                                    let ownerTokenIdentifier = syncScheduler.currentOwnerTokenIdentifier
                                    activeSession.syncOwnerTokenIdentifier = "issuer|uitest_replacement_owner"
                                    activeSession.touch()
                                    try? modelContext.save()
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(500))
                                        _ = try? activeWorkoutEngine.startBlankWorkout(
                                            ownerTokenIdentifier: ownerTokenIdentifier,
                                            context: modelContext
                                        )
                                    }
                                }
                                .font(.caption2)
                                .accessibilityIdentifier("UITestActiveWorkoutCurrentOwnerChangeButton")
                            }
                            #endif
                        }
                        .padding(.top, 16)
                        .background(AppTheme.canvasBackground.ignoresSafeArea())
                    }
                    .tint(AppTheme.brandAccentForeground)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .accessibilityIdentifier("ActiveWorkoutSheet")
                    .background {
                        ActiveWorkoutPresentationCompletionObserver {
                            navigationState.activeWorkoutPresentationDidFinish()
                        }
                        .frame(width: 0, height: 0)
                    }
                }
            }
            .sheet(item: $launchPresentation) { presentation in
                LaunchExperienceSheet(presentation: presentation) {
                    switch presentation {
                    case .onboarding:
                        completeLaunchPresentation(presentation)
                    case .whatsNew:
                        launchPresentation = nil
                    }
                }
                .onDisappear {
                    markWhatsNewSeenIfNeeded(presentation)
                }
            }
            .onChange(of: activeSession?.id, initial: true) { _, sessionID in
                if sessionID != nil {
                    launchPresentation = nil
                }
                navigationState.reconcileActiveWorkout(sessionID: sessionID)
                chooseLaunchExperienceIfReady()
            }
            .onChange(of: currentOwnerCoordinator.state, initial: true) { _, _ in
                chooseLaunchExperienceIfReady()
            }
            .workoutLiveActivityIntegration(
                snapshot: workoutLiveActivitySnapshot,
                navigationState: navigationState,
                coordinator: workoutLiveActivityCoordinator,
                willHandleWorkoutLiveActivityLink: { launchPresentation = nil }
            )
            .task {
                activeWorkoutEngine.loadActiveSession(
                    ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
                    context: modelContext
                )
            }
            .accessibilityDynamicTypeForUITesting()
    }

    @ViewBuilder
    private var tabShell: some View {
        if #available(iOS 26.1, *) {
            tabs
                .tabViewBottomAccessory(
                    isEnabled: navigationState.mountsActiveWorkoutAccessory && activeSession != nil
                ) {
                    activeWorkoutAccessory
                }
        } else if navigationState.mountsActiveWorkoutAccessory, activeSession != nil {
            tabs
                .tabViewBottomAccessory {
                    activeWorkoutAccessory
                }
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $navigationState.selectedTab) {
            NavigationStack(path: $navigationState.historyPath) {
                HistoryView(
                    navigationState: navigationState,
                    searchText: $historySearchText
                )
            }
            .tabItem {
                Label(AppTab.history.title, systemImage: AppTab.history.symbolName)
                    .accessibilityIdentifier(AppTab.history.accessibilityIdentifier)
            }
            .tag(AppTab.history)

            NavigationStack {
                HomeView(
                    navigationState: navigationState,
                    activeWorkoutEngine: activeWorkoutEngine,
                    activeSession: activeSession,
                    presentWorkout: { navigationState.presentActiveWorkout() }
                )
            }
            .tabItem {
                Label(AppTab.home.title, systemImage: AppTab.home.symbolName)
                    .accessibilityIdentifier(AppTab.home.accessibilityIdentifier)
            }
            .tag(AppTab.home)

            NavigationStack(path: $navigationState.profilePath) {
                ProfileView(navigationState: navigationState)
            }
            .tabItem {
                Label(AppTab.profile.title, systemImage: AppTab.profile.symbolName)
                    .accessibilityIdentifier(AppTab.profile.accessibilityIdentifier)
            }
            .tag(AppTab.profile)
        }
    }

    @ViewBuilder
    private var activeWorkoutAccessory: some View {
        if let activeSession {
            ActiveWorkoutAccessoryView(
                session: activeSession,
                showsReturnAction: navigationState.showsActiveWorkoutReturnAction,
                returnToActiveWorkout: { navigationState.presentActiveWorkout() }
            )
            .accessibilityDynamicTypeForUITesting()
        }
    }

    private var activeWorkoutPresentationBinding: Binding<Bool> {
        Binding(
            get: {
                navigationState.isActiveWorkoutPresented && activeSession != nil
            },
            set: { isPresented in
                if isPresented {
                    navigationState.presentActiveWorkout()
                } else {
                    prepareActiveWorkoutForMinimization?()
                    navigationState.minimizeActiveWorkout()
                }
            }
        )
    }

    private func presentLaunchExperienceIfNeeded() {
        guard launchPresentation == nil else {
            return
        }

        let currentAppVersion = AppBuildInfo.current.version
        let currentRelease = AppReleaseCatalog.definition(for: currentAppVersion)
        let state = firstRunStore.state
        launchPresentation = LaunchExperienceCoordinator.nextPresentation(
            state: state,
            currentRelease: currentRelease
        )

        if launchPresentation == nil, state.hasCompletedOnboarding {
            firstRunStore.markAppVersionProcessed(currentAppVersion)
        }
    }

    private func chooseLaunchExperienceIfReady() {
        guard !hasMadeLaunchExperienceDecision else { return }

        switch LaunchExperienceCoordinator.decision(
            currentOwnerState: currentOwnerCoordinator.state,
            activeWorkoutID: activeSession?.id
        ) {
        case .deferUntilOwnerScopeResolves:
            return
        case .skipForActiveWorkout:
            hasMadeLaunchExperienceDecision = true
        case .evaluateStore:
            hasMadeLaunchExperienceDecision = true
            presentLaunchExperienceIfNeeded()
        }
    }

    private func completeLaunchPresentation(_ presentation: LaunchExperiencePresentation) {
        switch presentation {
        case .onboarding:
            firstRunStore.markOnboardingCompleted(
                currentRelease: AppReleaseCatalog.definition(for: AppBuildInfo.current.version)
            )
        case .whatsNew(let release):
            firstRunStore.markWhatsNewSeen(version: release.version)
            firstRunStore.markAppVersionProcessed(AppBuildInfo.current.version)
        }

        launchPresentation = nil
    }

    private func markWhatsNewSeenIfNeeded(_ presentation: LaunchExperiencePresentation) {
        guard case .whatsNew(let release) = presentation else {
            return
        }

        firstRunStore.markWhatsNewSeen(version: release.version)
        firstRunStore.markAppVersionProcessed(AppBuildInfo.current.version)
    }

    private func dismissGlobalSyncFailureBanner() {
        dismissedSyncFailureSignature = SyncFailureNoticePresentation().dismissedSignature(
            currentFailureSignature: currentSyncFailureSignature,
            dismissedFailureSignature: dismissedSyncFailureSignature
        )
    }
}

private extension View {
    @ViewBuilder
    func accessibilityDynamicTypeForUITesting() -> some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest-accessibility-dynamic-type") {
            dynamicTypeSize(.accessibility3)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

private struct ActiveWorkoutPresentationCompletionObserver: UIViewControllerRepresentable {
    let onPresentationCompleted: () -> Void

    func makeUIViewController(context: Context) -> ObserverViewController {
        ObserverViewController(onPresentationCompleted: onPresentationCompleted)
    }

    func updateUIViewController(_ viewController: ObserverViewController, context: Context) {
        viewController.onPresentationCompleted = onPresentationCompleted
    }

    final class ObserverViewController: UIViewController {
        var onPresentationCompleted: () -> Void
        private var hasReportedAppearance = false

        init(onPresentationCompleted: @escaping () -> Void) {
            self.onPresentationCompleted = onPresentationCompleted
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !hasReportedAppearance else { return }
            hasReportedAppearance = true
            onPresentationCompleted()
        }
    }
}

private struct GlobalSyncFailureBanner: View {
    let title: String
    let message: String
    let retry: () -> Void
    let details: () -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.icloud")
                    .foregroundStyle(AppTheme.destructiveForeground)
                    .font(.title3.weight(.semibold))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 8)

                Button(action: dismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
                .accessibilityIdentifier("GlobalSyncDismissButton")
            }

            HStack(spacing: 8) {
                Button("Retry", action: retry)
                    .buttonStyle(.glassProminent)
                    .tint(AppTheme.brandAccentFill)
                    .accessibilityIdentifier("GlobalSyncRetryButton")
                Button("Details", action: details)
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("GlobalSyncDetailsButton")
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(AppTheme.destructiveForeground)
        )
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if abs(value.translation.width) > 40 || abs(value.translation.height) > 40 {
                        dismiss()
                    }
                }
        )
        .accessibilityAction(.escape, dismiss)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("GlobalSyncFailureBanner")
    }
}
