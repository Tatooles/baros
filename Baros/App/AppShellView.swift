import SwiftData
import SwiftUI

struct AppShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncScheduler.self) private var syncScheduler
    @Environment(\.syncRecoveryAction) private var syncRecoveryAction
    @Bindable var navigationState: AppNavigationState
    @Bindable var activeWorkoutEngine: ActiveWorkoutEngine
    private let firstRunStore = FirstRunExperienceStore()
    @State private var dismissedSyncFailureSignature: String?
    @State private var launchPresentation: LaunchExperiencePresentation?
    @State private var prepareActiveWorkoutForMinimization: (() -> Void)?
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \SyncOutboxEntry.updatedAt, order: .reverse) private var outboxEntries: [SyncOutboxEntry]

    private var activeSession: WorkoutSession? {
        WorkoutSession.visibleActiveSessions(
            from: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first
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
                                    activeSession.syncOwnerTokenIdentifier = "issuer|uitest_replacement_owner"
                                    activeSession.touch()
                                    try? modelContext.save()
                                }
                                .font(.caption2)
                                .accessibilityIdentifier("UITestActiveWorkoutCurrentOwnerChangeButton")
                            }
                            #endif
                        }
                        .padding(.top, 16)
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .accessibilityIdentifier("ActiveWorkoutSheet")
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
                navigationState.reconcileActiveWorkout(sessionID: sessionID)
            }
            .task {
                if activeSession == nil {
                    presentLaunchExperienceIfNeeded()
                }
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
                    isEnabled: navigationState.showsActiveWorkoutAccessory && activeSession != nil
                ) {
                    activeWorkoutAccessory
                }
        } else if navigationState.showsActiveWorkoutAccessory, activeSession != nil {
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
                HistoryView(navigationState: navigationState)
            }
            .tabItem {
                Label(AppTab.history.title, systemImage: AppTab.history.symbolName)
                    .accessibilityIdentifier(AppTab.history.accessibilityIdentifier)
            }
            .tag(AppTab.history)

            NavigationStack {
                HomeView(
                    activeSession: activeSession,
                    returnToActiveWorkout: { navigationState.presentActiveWorkout() },
                    navigationState: navigationState,
                    activeWorkoutEngine: activeWorkoutEngine
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
