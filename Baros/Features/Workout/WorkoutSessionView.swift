import SwiftData
import SwiftUI

enum WorkoutField: Hashable {
    case workoutTitle
    case workoutNotes
    case exerciseNotes(UUID)
    case setWeight(UUID)
    case setReps(UUID)
}

extension Animation {
    /// Clearing workout focus with this animation collapses the keyboard bar's
    /// inset alongside the keyboard, rather than snapping the scroll offset
    /// once the keyboard is gone.
    static let workoutFocusDismissal = Animation.smooth(duration: 0.25)
}

struct WorkoutSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @Bindable var navigationState: AppNavigationState
    let onMinimizePreparationChanged: ((() -> Void)?) -> Void
    @State private var showsSetSaveFailure = false
    @State private var isFinishSheetPresented = false
    @State private var isReorderExercisesPresented = false
    @State private var isAddExercisePresented = false
    @State private var swappingLoggedExercise: LoggedExercise?
    @State private var selectedHistoryExercise: LoggedExercise?
    @State private var pendingScrollTarget: UUID?
    @State private var recentlyAddedExerciseID: UUID?
    @State private var collapsedExerciseIDs: Set<UUID> = []
    @State private var revealedExerciseNoteIDs: Set<UUID> = []
    @State private var isWorkoutNoteRevealed = false
    @State private var cachedSortedLoggedExercises: [LoggedExercise]?
    @State private var cachedPreviousSets: [UUID: [PreviousSetPerformance]] = [:]
    @State private var rpeEditingSetID: UUID?
    @State private var setInputRegistry = ActiveSetInputRegistry()
    @State private var focusTransitionCoordinator = WorkoutFocusTransitionCoordinator()
    @FocusState private var focusedField: WorkoutField?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var contentBottomPadding: CGFloat {
        // Extra room only for positioning a newly added exercise near the top
        // of the viewport. Padding that collapses on dismissal clamps the
        // scroll offset (a visible jump), so it is otherwise the minimum; the
        // keyboard bar's safe-area inset already gives focused fields room.
        recentlyAddedExerciseID != nil ? 120 : 24
    }

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    var body: some View {
        let sortedLoggedExercises = cachedSortedLoggedExercises ?? session.sortedLoggedExercises
        let canReorderExercises = sortedLoggedExercises.count >= 2

        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        WorkoutTitleDraftField(
                            title: session.title,
                            focusedField: $focusedField
                        ) { draft in
                            try? engine.commitWorkoutTitle(draft, session: session, context: modelContext)
                        }

                        Text(AppTheme.formatDate(session.startedAt))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(AppTheme.textSecondary)
                            .padding(.horizontal, 12)
                            .accessibilityIdentifier("WorkoutDate")

                        WorkoutProgressiveNoteControl(
                            notes: .constant(session.notes),
                            addTitle: "Add workout note",
                            addSystemImage: "square.and.pencil",
                            placeholder: "Notes about today's workout",
                            accessibilityLabel: "Workout note",
                            addAccessibilityIdentifier: "AddWorkoutNoteButton",
                            fieldAccessibilityIdentifier: "WorkoutNotesField",
                            addAccessibilityHint: "Adds a note for the whole workout.",
                            addButtonHorizontalPadding: 8,
                            focusTarget: .workoutNotes,
                            isRevealed: $isWorkoutNoteRevealed,
                            focusedField: $focusedField,
                            commitOnFocusLoss: { draft in
                                try? engine.updateWorkoutNotes(
                                    draft,
                                    session: session,
                                    context: modelContext
                                )
                            }
                        )
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 4)

                    // PROTOTYPE: superset looks. Groups are in-memory only.
                    let supersetPrototype = SupersetPrototype.shared
                    ForEach(supersetPrototype.blocks(for: sortedLoggedExercises)) { block in
                      SupersetPrototypeBlockView(variant: supersetPrototype.variant, block: block) { exerciseIndex, loggedExercise in
                        ExerciseCardView(
                            loggedExercise: loggedExercise,
                            exerciseIndex: exerciseIndex,
                            engine: engine,
                            isCollapsed: isCollapsedBinding(for: loggedExercise),
                            isNoteRevealed: isNoteRevealedBinding(for: loggedExercise),
                            setInputRegistry: setInputRegistry,
                            focusedField: $focusedField,
                            weightUnit: weightUnit,
                            previousSets: cachedPreviousSets[loggedExercise.id] ?? [],
                            canReorder: canReorderExercises,
                            viewHistory: {
                                guard prepareForPresentation() else { return }
                                selectedHistoryExercise = loggedExercise
                            },
                            onSwapExercise: {
                                guard prepareForPresentation() else { return }
                                swappingLoggedExercise = loggedExercise
                            },
                            onReorderExercises: {
                                guard prepareForPresentation() else { return }
                                isReorderExercisesPresented = true
                            },
                            onEditRPE: { set in
                                focusedField = .setReps(set.id)
                                rpeEditingSetID = set.id
                            }
                        )
                        .id(loggedExercise.id)
                      }
                    }

                    Button {
                        guard prepareForPresentation() else { return }
                        isAddExercisePresented = true
                    } label: {
                        Label("Add Exercise", systemImage: "plus")
                            .font(.headline)
                            .foregroundStyle(AppTheme.brandAccentForeground)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(AppTheme.brandAccentMuted, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("AddExerciseButton")
                }
                .padding(.horizontal, AppTheme.shellPadding)
                .padding(.top, 8)
                .padding(.bottom, contentBottomPadding)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                ActiveWorkoutMetricsHeader(session: session, restTimer: engine.restTimer) {
                    // Flush any in-progress field edit through the commit path
                    // before the finish sheet reads the model.
                    guard prepareForPresentation() else { return }
                    isFinishSheetPresented = true
                }
                .equatable()
                SupersetPrototypeSwitcher() // PROTOTYPE: superset looks
                    .padding(.bottom, 6)
                }
            }
            .onScrollPhaseChange { _, phase in
                if phase != .idle { engine.restTimer.collapseControls() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Resigning focus routes pending drafts through the normal
                // commit path before the app is backgrounded or suspended.
                if newPhase != .active, focusedField != nil {
                    resignFocus()
                }
                showsSetSaveFailure = newPhase == .active && engine.hasPendingSetSave
            }
            .onChange(of: isAddExercisePresented) { _, isPresented in
                if isPresented {
                    UIHangContextObservability.shared.addExercisePresented()
                    return
                }
                UIHangContextObservability.shared.addExerciseDismissed()
                completeExerciseSelection(scrollProxy: scrollProxy)
            }
            .onChange(of: focusedField) { previousField, newField in
                UIHangContextObservability.shared.focusChanged(to: newField)
                if newField != nil { engine.restTimer.collapseControls() }
                focusTransitionCoordinator.observeFocusChange(
                    from: previousField,
                    to: newField,
                    commit: setInputRegistry.commit
                )

                if engine.hasPendingSetSave {
                    focusTransitionCoordinator.cancelPendingReveal()
                    focusTransitionCoordinator.synchronizeFocus(nil)
                    focusedField = nil
                }
                if RPEEditingFocusPolicy.shouldReset(editingSetID: rpeEditingSetID, newFocusedField: newField) {
                    rpeEditingSetID = nil
                }

                let shouldRetainNewExerciseReveal = recentlyAddedExerciseID != nil && Self.isSetField(newField)
                if !shouldRetainNewExerciseReveal {
                    // The temporary reveal extent is only needed while moving
                    // between set fields. Clear it before revealing any other
                    // field or dismissing focus.
                    recentlyAddedExerciseID = nil
                }
            }
            // Replaces a `.keyboard` toolbar, whose full-width strip swallows taps
            // between its buttons. As a safe-area inset, the system's keyboard
            // reveal clears the bar, and only the buttons themselves take touches.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focusedField != nil, !isChildPresentationActive {
                    keyboardAccessory
                }
            }
            .background {
                PreviousSetsCacheLoader(session: session) {
                    cachedPreviousSets = $0
                }
                .frame(width: 0, height: 0)
            }
        }
        .disabled(engine.hasPendingSetSave)
        .alert("Couldn't save this edit", isPresented: $showsSetSaveFailure) {
            Button("Retry") {
                do {
                    try engine.retrySetSave(in: session, context: modelContext)
                } catch {
                    // Keep the failed edit pending; dismissal restores the recovery choices.
                }
            }
            .disabled(!engine.canRetrySetSave(in: session))
            Button("Discard Edit", role: .cancel) {
                engine.discardSetSave()
            }
        } message: {
            Text("Retry saving, or discard this edit to continue. Your previously saved sets will remain.")
        }
        .onChange(of: engine.pendingSetSaveID, initial: true) { _, failureID in
            if failureID != nil { resignFocus() }
            showsSetSaveFailure = failureID != nil && scenePhase == .active
        }
        .onChange(of: showsSetSaveFailure) { _, isPresented in
            guard !isPresented else { return }
            // Alert actions dismiss after running. Reconcile that dismissal with
            // the pending edit so another failed Retry cannot hide recovery.
            Task { @MainActor in
                await Task.yield()
                guard scenePhase == .active, engine.hasPendingSetSave else { return }
                showsSetSaveFailure = true
            }
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            updateUIHangWorkoutContext(becameCurrent: true)
            focusTransitionCoordinator.synchronizeFocus(focusedField)
            onMinimizePreparationChanged {
                // Resigning focus commits leaf-owned drafts before the shell
                // transitions this session into its minimized presentation.
                resignFocus()
            }
        }
        .onChange(of: loggedExerciseStructureKey, initial: true) { _, _ in
            cachedSortedLoggedExercises = session.sortedLoggedExercises
            SupersetPrototype.shared.updateOrder(session.sortedLoggedExercises.map(\.id))
            if ProcessInfo.processInfo.arguments.contains("--superset-prototype-collapsed"), collapsedExerciseIDs.isEmpty {
                collapsedExerciseIDs = Set(session.sortedLoggedExercises.map(\.id))
            }
            if ProcessInfo.processInfo.arguments.contains("--superset-prototype-collapse-first"),
               collapsedExerciseIDs.isEmpty, let first = session.sortedLoggedExercises.first {
                collapsedExerciseIDs = [first.id]
            }
            updateUIHangWorkoutContext(becameCurrent: false)
        }
        .onDisappear {
            resignFocus()
            UIHangContextObservability.shared.activeWorkoutCeasedBeingCurrent()
            onMinimizePreparationChanged(nil)
        }
        .sheet(isPresented: $isFinishSheetPresented) {
            FinishWorkoutSheet(session: session, engine: engine)
        }
        .sheet(isPresented: $isReorderExercisesPresented) {
            ReorderExercisesSheet(session: session, engine: engine)
        }
        .sheet(isPresented: $isAddExercisePresented) {
            AddExerciseSheet(session: session, engine: engine) { loggedExercise in
                pendingScrollTarget = loggedExercise.id
            }
        }
        .sheet(item: $swappingLoggedExercise) { loggedExercise in
            SwapExerciseSheet(loggedExercise: loggedExercise, engine: engine)
        }
        .sheet(item: $selectedHistoryExercise) { loggedExercise in
            ExerciseQuickHistorySheet(loggedExercise: loggedExercise) { route in
                selectedHistoryExercise = nil
                navigationState.openExerciseHistory(route)
                navigationState.minimizeActiveWorkout()
            }
        }
    }

    private var keyboardAccessory: some View {
        HStack(spacing: 8) {
            if rpeEditingSetID != nil {
                // A thin, even inset keeps the chip capsule the same height as the
                // RPE/Done buttons it replaces, so the bar doesn't grow.
                RPEChipRow(selected: editingSet?.rpe, onSelect: selectRPE)
                    .padding(.vertical, 2)
                    .clipShape(Capsule())
                    .glassEffect(.regular, in: Capsule())
            } else {
                if let focusedSetID {
                    Button("RPE") {
                        rpeEditingSetID = focusedSetID
                    }
                    .accessibilityIdentifier("RPEToolbarButton")
                }

                Spacer()

                Button("Done") {
                    resignFocus()
                }
                .accessibilityIdentifier("DismissKeyboardButton")
            }
        }
        .font(.system(size: 16, weight: .semibold))
        .buttonStyle(.glass)
        .padding(.horizontal, AppTheme.shellPadding)
        // The keyboard reveal clears the text field, not its taller rounded
        // container. Transparent top room keeps the whole field off the buttons.
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func selectRPE(_ value: Double?) {
        guard !engine.hasPendingSetSave else { return }
        if let set = editingSet {
            // Both of a set's fields share one input registration.
            let preparedValues = setInputRegistry.prepareSetValues(
                for: .setReps(set.id),
                completesSet: value != nil
            ) ?? .init(weight: set.weight, reps: set.reps)
            withAnimation(.easeInOut(duration: 0.2)) {
                do {
                    try RPEChipSelectionAction.apply(
                        value: value,
                        preparedValues: preparedValues,
                        to: set,
                        engine: engine,
                        context: modelContext
                    )
                } catch {
                    // The engine retains the action and the alert offers recovery.
                }
            }
        }
        rpeEditingSetID = nil
        // Choosing an RPE finishes the set, so the keyboard's job is done.
        // Clear keeps editing the same field.
        if value != nil || engine.hasPendingSetSave {
            resignFocus()
        }
    }

    private var isChildPresentationActive: Bool {
        isFinishSheetPresented
            || isReorderExercisesPresented
            || isAddExercisePresented
            || swappingLoggedExercise != nil
            || selectedHistoryExercise != nil
    }

    private func completeExerciseSelection(scrollProxy: ScrollViewProxy) {
        let scrollTarget = pendingScrollTarget
        pendingScrollTarget = nil
        recentlyAddedExerciseID = scrollTarget

        focusTransitionCoordinator.transition(
            to: nil,
            commit: setInputRegistry.commit,
            assign: { self.focusedField = $0 }
        )
        guard let scrollTarget else { return }
        focusTransitionCoordinator.scheduleReveal(after: .milliseconds(350)) {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                scrollProxy.scrollTo(scrollTarget, anchor: .top)
            }
        }
    }

    private var focusedSetID: UUID? {
        switch focusedField {
        case .setWeight(let id), .setReps(let id):
            return id
        default:
            return nil
        }
    }

    private var editingSet: LoggedSet? {
        guard let rpeEditingSetID else { return nil }
        for loggedExercise in cachedSortedLoggedExercises ?? session.sortedLoggedExercises {
            if let match = loggedExercise.sets.first(where: {
                $0.id == rpeEditingSetID && $0.deletedAt == nil
            }) {
                return match
            }
        }
        return nil
    }

    private var loggedExerciseStructureKey: Set<LoggedExerciseStructureValue> {
        Set(session.loggedExercises.map(LoggedExerciseStructureValue.init))
    }

    private func updateUIHangWorkoutContext(becameCurrent: Bool) {
        let size = UIHangWorkoutSize(session: session)
        if becameCurrent {
            UIHangContextObservability.shared.activeWorkoutBecameCurrent(
                exerciseCount: size.exerciseCount,
                setCount: size.setCount
            )
        } else {
            UIHangContextObservability.shared.activeWorkoutStructureChanged(
                exerciseCount: size.exerciseCount,
                setCount: size.setCount
            )
        }
    }

    private func isCollapsedBinding(for loggedExercise: LoggedExercise) -> Binding<Bool> {
        Binding(
            get: { collapsedExerciseIDs.contains(loggedExercise.id) },
            set: { isCollapsed in
                if isCollapsed {
                    guard prepareForPresentation() else { return }
                    revealedExerciseNoteIDs.remove(loggedExercise.id)
                    collapsedExerciseIDs.insert(loggedExercise.id)
                } else {
                    collapsedExerciseIDs.remove(loggedExercise.id)
                }
            }
        )
    }

    private func isNoteRevealedBinding(for loggedExercise: LoggedExercise) -> Binding<Bool> {
        Binding(
            get: { revealedExerciseNoteIDs.contains(loggedExercise.id) },
            set: { isRevealed in
                if isRevealed {
                    revealedExerciseNoteIDs.insert(loggedExercise.id)
                } else {
                    revealedExerciseNoteIDs.remove(loggedExercise.id)
                }
            }
        )
    }

    private func prepareForPresentation() -> Bool {
        resignFocus()
        return !engine.hasPendingSetSave
    }

    private func resignFocus() {
        focusTransitionCoordinator.transition(
            to: nil,
            commit: setInputRegistry.commit,
            assign: { field in
                withAnimation(.workoutFocusDismissal) { focusedField = field }
            }
        )
    }

    private static func isSetField(_ field: WorkoutField?) -> Bool {
        switch field {
        case .setWeight, .setReps:
            return true
        case .workoutTitle, .workoutNotes, .exerciseNotes, nil:
            return false
        }
    }
}

private struct LoggedExerciseStructureValue: Hashable {
    let id: UUID
    // This key also invalidates the rendered exercise-order cache.
    let orderIndex: Int
    let deletedAt: Date?
    let activeSetIDs: Set<UUID>

    init(_ loggedExercise: LoggedExercise) {
        id = loggedExercise.id
        orderIndex = loggedExercise.orderIndex
        deletedAt = loggedExercise.deletedAt
        activeSetIDs = Set(
            loggedExercise.sets.lazy.compactMap { set in
                set.deletedAt == nil ? set.id : nil
            }
        )
    }
}

/// Fetches completed history only when one of its inputs changes. A query-backed
/// child still refreshes its fetch during focus-only SwiftUI updates, so this
/// loader listens to model saves and ignores value edits confined to the active
/// workout graph.
private struct PreviousSetsCacheLoader: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    @Environment(SyncScheduler.self) private var syncScheduler
    @State private var cache = PreviousSetsCacheLoaderCache()

    let session: WorkoutSession
    let onUpdate: ([UUID: [PreviousSetPerformance]]) -> Void

    var body: some View {
        let reloadTrigger = PreviousSetsCacheReloadTrigger(
            sessionID: session.id,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
            lastSyncedAt: syncScheduler.lastSyncedAt
        )

        Color.clear
            .onChange(of: reloadTrigger, initial: true) { _, trigger in
                cache.reload(
                    session: session,
                    context: modelContext,
                    ownerTokenIdentifier: trigger.ownerTokenIdentifier,
                    lastSyncedAt: trigger.lastSyncedAt,
                    onUpdate: onUpdate
                )
            }
            .onReceive(NotificationCenter.default.publisher(for: ModelContext.didSave)) { notification in
                cache.reloadIfNeeded(
                    after: notification,
                    session: session,
                    context: modelContext,
                    ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier,
                    lastSyncedAt: syncScheduler.lastSyncedAt,
                    onUpdate: onUpdate
                )
            }
    }
}

struct PreviousSetsCacheSaveChanges {
    let insertedIDs: Set<PersistentIdentifier>
    let updatedIDs: Set<PersistentIdentifier>
    let deletedIDs: Set<PersistentIdentifier>
    let invalidatedAllIdentifiers: Bool

    /// Keep unknown entities conservative. Only these two model types are
    /// bookkeeping that cannot change historical values or route matching.
    var containsOnlySyncBookkeeping: Bool {
        guard !invalidatedAllIdentifiers else { return false }
        let identifiers = insertedIDs.union(updatedIDs).union(deletedIDs)
        guard !identifiers.isEmpty else { return false }
        return identifiers.allSatisfy {
            $0.entityName == String(describing: SyncOutboxEntry.self)
                || $0.entityName == String(describing: SyncCursorState.self)
        }
    }

    init(notification: Notification) {
        insertedIDs = Self.identifiers(for: .insertedIdentifiers, in: notification)
        updatedIDs = Self.identifiers(for: .updatedIdentifiers, in: notification)
        deletedIDs = Self.identifiers(for: .deletedIdentifiers, in: notification)
        invalidatedAllIdentifiers = notification.userInfo?[
            ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue
        ] as? Bool ?? false
    }

    private static func identifiers(
        for key: ModelContext.NotificationKey,
        in notification: Notification
    ) -> Set<PersistentIdentifier> {
        let value = notification.userInfo?[key.rawValue]
        if let identifiers = value as? Set<PersistentIdentifier> {
            return identifiers
        }
        if let identifiers = value as? [PersistentIdentifier] {
            return Set(identifiers)
        }
        return []
    }
}

@MainActor
final class PreviousSetsCacheLoaderCache {
    private struct ActiveStructureKey: Equatable {
        private struct ExerciseEntry: Equatable {
            let id: UUID
            let routeID: String
            let sourceLoggedExerciseID: UUID?
            let setIDs: [UUID]
        }

        let sessionID: UUID
        let sourceSessionID: UUID?
        private let exerciseEntries: [ExerciseEntry]

        init(session: WorkoutSession) {
            sessionID = session.id
            sourceSessionID = session.source == .pastWorkout ? session.sourceSessionID : nil
            exerciseEntries = session.sortedLoggedExercises.map { loggedExercise in
                ExerciseEntry(
                    id: loggedExercise.id,
                    routeID: ExerciseHistoryRoute(loggedExercise: loggedExercise).id,
                    sourceLoggedExerciseID: loggedExercise.sourceLoggedExerciseID,
                    setIDs: loggedExercise.sortedSets.map(\.id)
                )
            }
        }
    }

    private var activeStructureKey: ActiveStructureKey?
    private var cacheKey: PreviousSetPerformance.CacheKey?
    private let fetchSessions: @MainActor (ModelContext, String?) throws -> [WorkoutSession]

    init(
        fetchSessions: (@MainActor (ModelContext, String?) throws -> [WorkoutSession])? = nil
    ) {
        self.fetchSessions = fetchSessions ?? Self.fetchCompletedHistory
    }

    func reloadIfNeeded(
        after notification: Notification,
        session: WorkoutSession,
        context: ModelContext,
        ownerTokenIdentifier: String?,
        lastSyncedAt: Date?,
        onUpdate: ([UUID: [PreviousSetPerformance]]) -> Void
    ) {
        // Other contexts in this container can change history too. An
        // unrelated container cannot affect the values shown by this loader.
        if let savedContext = notification.object as? ModelContext,
           savedContext.container !== context.container {
            return
        }
        let changes = PreviousSetsCacheSaveChanges(notification: notification)
        guard !changes.containsOnlySyncBookkeeping else { return }
        guard PreviousSetsCacheReloadPolicy.shouldReload(
            insertedIDs: changes.insertedIDs,
            updatedIDs: changes.updatedIDs,
            deletedIDs: changes.deletedIDs,
            activeGraphIDs: activeGraphIDs(for: session),
            activeStructureChanged: activeStructureChanged(for: session),
            invalidatedAllIdentifiers: changes.invalidatedAllIdentifiers
        ) else { return }

        reload(
            session: session,
            context: context,
            ownerTokenIdentifier: ownerTokenIdentifier,
            lastSyncedAt: lastSyncedAt,
            onUpdate: onUpdate
        )
    }

    static func fetchCompletedHistory(
        context: ModelContext,
        ownerTokenIdentifier: String?
    ) throws -> [WorkoutSession] {
        let completedStatus = WorkoutSessionStatus.completed.rawValue
        return try context.fetch(FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { session in
                session.statusRaw == completedStatus
                    && session.deletedAt == nil
                    && (session.syncOwnerTokenIdentifier == ownerTokenIdentifier
                        || session.syncOwnerTokenIdentifier == nil)
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        ))
    }

    func activeGraphIDs(for session: WorkoutSession) -> Set<PersistentIdentifier> {
        var identifiers: Set<PersistentIdentifier> = [session.persistentModelID]
        for loggedExercise in session.loggedExercises {
            identifiers.insert(loggedExercise.persistentModelID)
            identifiers.formUnion(loggedExercise.sets.map(\.persistentModelID))
        }
        return identifiers
    }

    func activeStructureChanged(for session: WorkoutSession) -> Bool {
        ActiveStructureKey(session: session) != activeStructureKey
    }

    func reload(
        session: WorkoutSession,
        context: ModelContext,
        ownerTokenIdentifier: String?,
        lastSyncedAt: Date?,
        onUpdate: ([UUID: [PreviousSetPerformance]]) -> Void
    ) {
        guard let sessions = try? fetchSessions(context, ownerTokenIdentifier) else { return }

        let nextActiveStructureKey = ActiveStructureKey(session: session)
        let nextCacheKey = PreviousSetPerformance.CacheKey(
            session: session,
            sessions: sessions,
            ownerTokenIdentifier: ownerTokenIdentifier,
            lastSyncedAt: lastSyncedAt
        )
        activeStructureKey = nextActiveStructureKey
        guard nextCacheKey != cacheKey else { return }

        cacheKey = nextCacheKey
        onUpdate(
            PreviousSetPerformance.lastCompletedSetsByExerciseID(
                for: session.sortedLoggedExercises,
                in: sessions,
                ownerTokenIdentifier: ownerTokenIdentifier,
                sourceSessionID: session.source == .pastWorkout ? session.sourceSessionID : nil
            )
        )
    }
}

/// Separates the once-per-second duration tick from set aggregation. Set
/// totals are recomputed only when their value inputs change.
private struct ActiveWorkoutMetricsHeader: View, @MainActor Equatable {
    let session: WorkoutSession
    let restTimer: RestTimerCoordinator
    let onFinish: () -> Void
    @State private var cachedMetrics: WorkoutMetrics?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session.id == rhs.session.id
    }

    var body: some View {
        let cacheKey = WorkoutMetrics.CacheKey(session: session)

        WorkoutHeaderView(
            startedAt: session.startedAt,
            completedSets: cachedMetrics?.completedSetCount ?? 0,
            totalSets: cachedMetrics?.totalSetCount ?? 0,
            restTimer: restTimer,
            onFinish: onFinish
        )
        .onChange(of: cacheKey, initial: true) { _, _ in
            cachedMetrics = WorkoutMetrics(session: session, now: session.startedAt)
        }
    }
}

/// Owns the title draft so keystrokes re-render only this leaf, never the
/// whole form. Commits (one model write + save) when focus leaves the field.
private struct WorkoutTitleDraftField: View {
    let title: String
    var focusedField: FocusState<WorkoutField?>.Binding
    let commit: (String) -> Void
    @State private var draft: String?

    var body: some View {
        WorkoutTitleField(
            placeholder: "Workout Name",
            text: Binding(
                get: { draft ?? title },
                set: { newValue in
                    guard newValue != (draft ?? title) else { return }
                    draft = newValue
                }
            ),
            focusTarget: .workoutTitle,
            focusedField: focusedField,
            accessibilityIdentifier: "WorkoutTitle"
        )
        .onChange(of: focusedField.wrappedValue) { previousField, newField in
            if previousField == .workoutTitle, newField != .workoutTitle {
                commitIfNeeded()
            }
        }
        .onDisappear {
            // The view can leave the tree mid-edit (tab switch, active session
            // replaced); the focus-change commit no longer fires then.
            commitIfNeeded()
        }
    }

    private func commitIfNeeded() {
        guard let draft else { return }
        commit(draft)
        self.draft = nil
    }
}

enum RPEEditingFocusPolicy {
    static func shouldReset(editingSetID: UUID?, newFocusedField: WorkoutField?) -> Bool {
        guard let editingSetID else { return false }

        switch newFocusedField {
        case .setWeight(let focusedSetID), .setReps(let focusedSetID):
            return focusedSetID != editingSetID
        case .workoutTitle, .workoutNotes, .exerciseNotes, nil:
            return true
        }
    }
}

// MARK: - PROTOTYPE: superset looks (throwaway, never merge)
//
// Four looks for superset grouping on the real Active Workout screen,
// switchable from the yellow pill under the header. Grouping lives in memory
// only; nothing here touches the model or sync. Launch with
// `--uitest-seed-long-name-active-workout` to get a single, a pair and a trio.

@MainActor @Observable
final class SupersetPrototype {
    static let shared = SupersetPrototype()

    enum Variant: String, CaseIterable {
        case tintedBox = "A"
        case rail = "B"
        case oneCard = "C"
        case tintedCards = "D"

        var name: String {
            switch self {
            case .tintedBox: "Tinted box"
            case .rail: "Side rail"
            case .oneCard: "One card"
            case .tintedCards: "Tinted cards"
            }
        }
    }

    enum CardChrome {
        case standard
        case bare
        case tinted
    }

    struct Member {
        let index: Int
        let exercise: LoggedExercise
    }

    struct Block: Identifiable {
        let id: UUID
        let members: [Member]
    }

    private static let variantKey = "SupersetPrototype.variant"

    var variant: Variant {
        didSet { UserDefaults.standard.set(variant.rawValue, forKey: Self.variantKey) }
    }
    private(set) var groupIDs: [UUID: UUID] = [:]
    private var order: [UUID] = []
    private var didSeed = false

    private init() {
        variant = UserDefaults.standard.string(forKey: Self.variantKey)
            .flatMap(Variant.init(rawValue:)) ?? .tintedBox
    }

    func cycle(_ step: Int) {
        let all = Variant.allCases
        let index = all.firstIndex(of: variant) ?? 0
        variant = all[(index + step + all.count) % all.count]
    }

    func updateOrder(_ ids: [UUID]) {
        order = ids
        if !didSeed, ids.count >= 6 {
            // Exercise 1 alone, 2–3 as a pair, 4–6 as a giant set.
            didSeed = true
            let pair = UUID(), trio = UUID()
            groupIDs[ids[1]] = pair
            groupIDs[ids[2]] = pair
            for id in ids[3...5] { groupIDs[id] = trio }
        }
        normalize()
    }

    func blocks(for exercises: [LoggedExercise]) -> [Block] {
        var blocks: [Block] = []
        var index = 0
        while index < exercises.count {
            var end = index
            if let group = groupIDs[exercises[index].id] {
                while end + 1 < exercises.count, groupIDs[exercises[end + 1].id] == group { end += 1 }
            }
            blocks.append(Block(
                id: exercises[index].id,
                members: (index...end).map { Member(index: $0, exercise: exercises[$0]) }
            ))
            index = end + 1
        }
        return blocks
    }

    func canStartWithNext(_ id: UUID) -> Bool {
        guard let index = order.firstIndex(of: id), index + 1 < order.count else { return false }
        return groupIDs[id] == nil && groupIDs[order[index + 1]] == nil
    }

    func canJoinPrevious(_ id: UUID) -> Bool {
        guard let index = order.firstIndex(of: id) else { return false }
        return index > 0 && groupIDs[id] == nil
    }

    func isGrouped(_ id: UUID) -> Bool { groupIDs[id] != nil }

    func startWithNext(_ id: UUID) {
        guard let index = order.firstIndex(of: id), index + 1 < order.count else { return }
        let group = UUID()
        groupIDs[id] = group
        groupIDs[order[index + 1]] = group
        normalize()
    }

    func joinPrevious(_ id: UUID) {
        guard let index = order.firstIndex(of: id), index > 0 else { return }
        let previous = order[index - 1]
        let group = groupIDs[previous] ?? UUID()
        groupIDs[previous] = group
        groupIDs[id] = group
        normalize()
    }

    func remove(_ id: UUID) {
        groupIDs[id] = nil
        normalize()
    }

    /// Splits a group broken into separate runs and drops runs of one.
    private func normalize() {
        var seen: Set<UUID> = []
        var index = 0
        while index < order.count {
            guard let group = groupIDs[order[index]] else { index += 1; continue }
            var end = index
            while end + 1 < order.count, groupIDs[order[end + 1]] == group { end += 1 }
            if end == index {
                groupIDs[order[index]] = nil
            } else if seen.contains(group) {
                let fresh = UUID()
                for i in index...end { groupIDs[order[i]] = fresh }
            } else {
                seen.insert(group)
            }
            index = end + 1
        }
    }
}

extension EnvironmentValues {
    @Entry var supersetPrototypeChrome: SupersetPrototype.CardChrome = .standard
}

struct SupersetPrototypeSwitcher: View {
    var body: some View {
        let prototype = SupersetPrototype.shared
        HStack(spacing: 14) {
            Button { withAnimation(.snappy) { prototype.cycle(-1) } } label: {
                Image(systemName: "chevron.left")
            }
            Text("\(prototype.variant.rawValue) · \(prototype.variant.name)")
                .monospacedDigit()
            Button { withAnimation(.snappy) { prototype.cycle(1) } } label: {
                Image(systemName: "chevron.right")
            }
        }
        .font(.footnote.weight(.bold))
        .foregroundStyle(.black)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.yellow, in: Capsule())
        .buttonStyle(.plain)
        .accessibilityIdentifier("SupersetPrototypeSwitcher")
    }
}

struct SupersetPrototypeMenuItems: View {
    let exerciseID: UUID

    var body: some View {
        let prototype = SupersetPrototype.shared
        if prototype.canStartWithNext(exerciseID) {
            Button { withAnimation(.snappy) { prototype.startWithNext(exerciseID) } } label: {
                Label("Superset with Next", systemImage: "link")
            }
        }
        if prototype.canJoinPrevious(exerciseID) {
            Button { withAnimation(.snappy) { prototype.joinPrevious(exerciseID) } } label: {
                Label("Join Previous Superset", systemImage: "link")
            }
        }
        if prototype.isGrouped(exerciseID) {
            Button { withAnimation(.snappy) { prototype.remove(exerciseID) } } label: {
                Label("Remove from Superset", systemImage: "minus.circle")
            }
        }
    }
}

struct SupersetPrototypeCardChrome<Content: View>: View {
    let chrome: SupersetPrototype.CardChrome
    @ViewBuilder var content: Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
    }

    var body: some View {
        switch chrome {
        case .standard:
            SurfaceCard(role: .focus, padding: 0) { content }
        case .bare:
            content.frame(maxWidth: .infinity, alignment: .leading)
        case .tinted:
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    ZStack {
                        shape.fill(AppTheme.focusSurface)
                        shape.fill(AppTheme.brandAccentMuted)
                    }
                }
                .clipShape(shape)
                .overlay(shape.strokeBorder(AppTheme.brandAccentForeground.opacity(0.45), lineWidth: 1))
                .shadow(color: AppTheme.surfaceShadow, radius: 14, y: 5)
                .containerShape(shape)
        }
    }
}

private struct SupersetPrototypeLabel: View {
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "link")
            Text("SUPERSET")
                .tracking(1.2)
            Text("· \(count)")
                .foregroundStyle(AppTheme.brandAccentForeground.opacity(0.7))
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(AppTheme.brandAccentForeground)
    }
}

struct SupersetPrototypeBlockView<Card: View>: View {
    let variant: SupersetPrototype.Variant
    let block: SupersetPrototype.Block
    @ViewBuilder let card: (Int, LoggedExercise) -> Card

    var body: some View {
        if block.members.count < 2 {
            ForEach(block.members, id: \.exercise.id) { member in
                card(member.index, member.exercise)
            }
        } else {
            switch variant {
            case .tintedBox: tintedBox
            case .rail: rail
            case .oneCard: oneCard
            case .tintedCards: tintedCards
            }
        }
    }

    private var members: some View {
        ForEach(block.members, id: \.exercise.id) { member in
            card(member.index, member.exercise)
        }
    }

    /// A: the old web app's look. One tinted, dashed box holds the group's cards.
    private var tintedBox: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius + 7, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            SupersetPrototypeLabel(count: block.members.count)
                .padding(.horizontal, 14)
                .padding(.top, 4)
            members
        }
        .padding(7)
        .background(AppTheme.brandAccentMuted, in: shape)
        .overlay(
            shape.strokeBorder(
                AppTheme.brandAccentForeground.opacity(0.4),
                style: StrokeStyle(lineWidth: 1, dash: [5, 4])
            )
        )
        // Let the box run into the page margin so the cards keep their width.
        .padding(.horizontal, -7)
    }

    /// B: an accent rail in the page margin spans the group's cards.
    private var rail: some View {
        VStack(alignment: .leading, spacing: 6) {
            SupersetPrototypeLabel(count: block.members.count)
                .padding(.leading, 12)
            HStack(spacing: 6) {
                Capsule()
                    .fill(AppTheme.brandAccentForeground)
                    .frame(width: 4)
                VStack(spacing: 8) { members }
            }
        }
        .padding(.leading, -10)
    }

    /// C: the group's exercises fuse into one card under a tinted header band.
    private var oneCard: some View {
        let shape = RoundedRectangle(cornerRadius: AppTheme.cardCornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            SupersetPrototypeLabel(count: block.members.count)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.brandAccentMuted)
            ForEach(Array(block.members.enumerated()), id: \.element.exercise.id) { offset, member in
                if offset > 0 {
                    Rectangle()
                        .fill(AppTheme.brandAccentForeground.opacity(0.35))
                        .frame(height: 1)
                }
                card(member.index, member.exercise)
                    .environment(\.supersetPrototypeChrome, .bare)
            }
        }
        .background(AppTheme.focusSurface, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(AppTheme.brandAccentForeground.opacity(0.45), lineWidth: 1))
        .shadow(color: AppTheme.surfaceShadow, radius: 14, y: 5)
    }

    /// D: each card takes the tint, and link chips bridge the gaps between them.
    private var tintedCards: some View {
        VStack(spacing: 8) {
            ForEach(Array(block.members.enumerated()), id: \.element.exercise.id) { offset, member in
                card(member.index, member.exercise)
                    .environment(\.supersetPrototypeChrome, .tinted)
                    .overlay(alignment: .bottom) {
                        if offset < block.members.count - 1 {
                            Image(systemName: "link")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(AppTheme.onBrandAccent)
                                .frame(width: 26, height: 26)
                                .background(AppTheme.brandAccentFill, in: Circle())
                                .overlay(Circle().strokeBorder(AppTheme.canvasBackground, lineWidth: 2))
                                .offset(y: 17)
                        }
                    }
                    .zIndex(Double(block.members.count - offset))
            }
        }
    }
}
