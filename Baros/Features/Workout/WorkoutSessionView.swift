import SwiftData
import SwiftUI

enum WorkoutField: Hashable {
    case workoutTitle
    case workoutNotes
    case exerciseNotes(UUID)
    case setWeight(UUID)
    case setReps(UUID)
}

struct WorkoutSessionView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(SyncScheduler.self) private var syncScheduler
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @Bindable var navigationState: AppNavigationState
    let onMinimizePreparationChanged: ((() -> Void)?) -> Void
    @State private var isFinishSheetPresented = false
    @State private var isReorderExercisesPresented = false
    @State private var isAddExercisePresented = false
    @State private var selectedHistoryExercise: LoggedExercise?
    @State private var pendingFocusedField: WorkoutField?
    @State private var pendingScrollTarget: UUID?
    @State private var recentlyAddedExerciseID: UUID?
    @State private var collapsedExerciseIDs: Set<UUID> = []
    @State private var revealedExerciseNoteIDs: Set<UUID> = []
    @State private var isWorkoutNoteRevealed = false
    @State private var cachedFocusOrder: [WorkoutField] = []
    @State private var cachedPreviousSets: [UUID: [PreviousSetPerformance]] = [:]
    @State private var rpeEditingSetID: UUID?
    @State private var rpeEditingSourceField: WorkoutField?
    @State private var fieldCommitRegistry = WorkoutFieldCommitRegistry()
    @State private var focusTransitionCoordinator = WorkoutFocusTransitionCoordinator()
    @FocusState private var focusedField: WorkoutField?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var contentBottomPadding: CGFloat {
        // Any padding that appears while a field is focused collapses on
        // dismissal and clamps the scroll offset (a visible jump), so each
        // tier is the minimum the state needs. Full room is only for
        // positioning a newly added exercise near the top of the viewport.
        // Title and workout-note editing keep modest keyboard-navigation
        // room. Mid-list fields always have real content below them, so
        // keyboard avoidance reveals them with no extra room at all.
        if recentlyAddedExerciseID != nil { return 120 }
        switch focusedField {
        case .workoutTitle, .workoutNotes:
            return 64
        case .exerciseNotes, .setWeight, .setReps, nil:
            return 24
        }
    }

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    var body: some View {
        let sortedLoggedExercises = session.sortedLoggedExercises
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
                            notes: session.notes,
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
                            focusedField: $focusedField
                        ) { draft in
                            try? engine.updateWorkoutNotes(draft, session: session, context: modelContext)
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 4)

                    ForEach(Array(sortedLoggedExercises.enumerated()), id: \.element.id) { exerciseIndex, loggedExercise in
                        ExerciseCardView(
                            loggedExercise: loggedExercise,
                            exerciseIndex: exerciseIndex,
                            engine: engine,
                            isCollapsed: isCollapsedBinding(for: loggedExercise),
                            isNoteRevealed: isNoteRevealedBinding(for: loggedExercise),
                            fieldCommitRegistry: fieldCommitRegistry,
                            focusedField: $focusedField,
                            weightUnit: weightUnit,
                            previousSets: cachedPreviousSets[loggedExercise.id] ?? [],
                            canReorder: canReorderExercises,
                            viewHistory: {
                                resignFocus()
                                selectedHistoryExercise = loggedExercise
                            },
                            onReorderExercises: {
                                isReorderExercisesPresented = true
                            },
                            onEditRPE: { set in
                                focusedField = .setReps(set.id)
                                rpeEditingSourceField = .setReps(set.id)
                                rpeEditingSetID = set.id
                            }
                        )
                        .id(loggedExercise.id)
                    }

                    Button {
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
                ActiveWorkoutMetricsHeader(session: session) {
                    // Flush any in-progress field edit through the commit path
                    // before the finish sheet reads the model.
                    resignFocus()
                    isFinishSheetPresented = true
                }
                .equatable()
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Resigning focus routes pending drafts through the normal
                // commit path before the app is backgrounded or suspended.
                if newPhase != .active, focusedField != nil {
                    resignFocus()
                }
            }
            .onChange(of: isAddExercisePresented) { _, isPresented in
                guard !isPresented else { return }

                let scrollTarget = pendingScrollTarget
                let focusedField = pendingFocusedField
                pendingScrollTarget = nil
                self.pendingFocusedField = nil
                recentlyAddedExerciseID = scrollTarget

                focusTransitionCoordinator.transition(
                    to: focusedField,
                    delay: .milliseconds(350),
                    commit: fieldCommitRegistry.commit,
                    assign: { self.focusedField = $0 },
                    reveal: { _ in
                        if let scrollTarget {
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                                scrollProxy.scrollTo(scrollTarget, anchor: .top)
                            }
                        }
                    }
                )
            }
            .onChange(of: focusedField) { previousField, newField in
                focusTransitionCoordinator.observeFocusChange(
                    from: previousField,
                    to: newField,
                    commit: fieldCommitRegistry.commit,
                    reveal: { revealFocusedField($0, scrollProxy: scrollProxy) }
                )

                if RPEEditingFocusPolicy.shouldReset(editingSetID: rpeEditingSetID, newFocusedField: newField) {
                    rpeEditingSetID = nil
                    rpeEditingSourceField = nil
                }

                let shouldRetainNewExerciseReveal = recentlyAddedExerciseID != nil && Self.isSetField(newField)
                if !shouldRetainNewExerciseReveal {
                    // The temporary reveal extent is only needed while moving
                    // between set fields. Clear it before revealing any other
                    // field or dismissing focus.
                    recentlyAddedExerciseID = nil
                }
            }
            .toolbar {
                if !isChildPresentationActive {
                    ToolbarItemGroup(placement: .keyboard) {
                        if rpeEditingSetID != nil {
                            RPEChipRow(
                                selected: editingSet?.rpe,
                                onSelect: { value in
                                    let nextField = WorkoutFocusNavigator.adjacentField(
                                        from: rpeEditingSourceField ?? focusTransitionCoordinator.currentField,
                                        in: cachedFocusOrder,
                                        offset: 1
                                    )
                                    if let set = editingSet {
                                        try? RPEChipSelectionAction.apply(
                                            value: value,
                                            to: set,
                                            engine: engine,
                                            context: modelContext
                                        )
                                    }
                                    rpeEditingSetID = nil
                                    rpeEditingSourceField = nil
                                    transitionFocus(to: nextField, scrollProxy: scrollProxy)
                                }
                            )
                        } else {
                            Button {
                                moveFocus(offset: -1, scrollProxy: scrollProxy)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .disabled(previousFocusedField == nil)
                            .accessibilityLabel("Previous field")
                            .accessibilityIdentifier("PreviousWorkoutFieldButton")

                            Button {
                                moveFocus(offset: 1, scrollProxy: scrollProxy)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .disabled(nextFocusedField == nil)
                            .accessibilityLabel("Next field")
                            .accessibilityIdentifier("NextWorkoutFieldButton")

                            if let focusedSetID {
                                Button("RPE") {
                                    rpeEditingSourceField = focusTransitionCoordinator.currentField
                                    rpeEditingSetID = focusedSetID
                                }
                                .font(.system(size: 16, weight: .semibold))
                                .accessibilityIdentifier("RPEToolbarButton")
                            }

                            Spacer()

                            Button("Done") {
                                resignFocus()
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .accessibilityIdentifier("DismissKeyboardButton")
                        }
                    }
                }
            }
            .background {
                ZStack {
                    WorkoutFocusOrderLoader(
                        session: session,
                        inputs: WorkoutFocusNavigator.StructureInputs(
                            collapsedExerciseIDs: collapsedExerciseIDs,
                            revealedExerciseNoteIDs: revealedExerciseNoteIDs,
                            isWorkoutNoteRevealed: isWorkoutNoteRevealed
                        )
                    ) { order in
                        cachedFocusOrder = order
                        focusTransitionCoordinator.updateFocusOrder(order)
                        focusTransitionCoordinator.synchronizeFocus(focusedField)
                    }
                    .equatable()

                    PreviousSetsCacheLoader(session: session) {
                        cachedPreviousSets = $0
                    }
                }
                .frame(width: 0, height: 0)
            }
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            focusTransitionCoordinator.synchronizeFocus(focusedField)
            onMinimizePreparationChanged {
                // Resigning focus commits leaf-owned drafts before the shell
                // transitions this session into its minimized presentation.
                resignFocus()
            }
        }
        .onDisappear {
            resignFocus()
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
                pendingFocusedField = loggedExercise.sortedSets.first.map { .setWeight($0.id) }
            }
        }
        .sheet(item: $selectedHistoryExercise) { loggedExercise in
            ExerciseQuickHistorySheet(loggedExercise: loggedExercise) { route in
                selectedHistoryExercise = nil
                navigationState.openExerciseHistory(route)
                navigationState.minimizeActiveWorkout()
            }
        }
    }

    private var isChildPresentationActive: Bool {
        isFinishSheetPresented
            || isReorderExercisesPresented
            || isAddExercisePresented
            || selectedHistoryExercise != nil
    }

    private var previousFocusedField: WorkoutField? {
        WorkoutFocusNavigator.adjacentField(
            from: focusedField,
            in: cachedFocusOrder,
            offset: -1
        )
    }

    private var nextFocusedField: WorkoutField? {
        WorkoutFocusNavigator.adjacentField(
            from: focusedField,
            in: cachedFocusOrder,
            offset: 1
        )
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
        for loggedExercise in session.sortedLoggedExercises {
            if let match = loggedExercise.sortedSets.first(where: { $0.id == rpeEditingSetID }) {
                return match
            }
        }
        return nil
    }

    private func isCollapsedBinding(for loggedExercise: LoggedExercise) -> Binding<Bool> {
        Binding(
            get: { collapsedExerciseIDs.contains(loggedExercise.id) },
            set: { isCollapsed in
                if isCollapsed {
                    if focusedField == .exerciseNotes(loggedExercise.id) {
                        resignFocus()
                    }
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

    private func moveFocus(offset: Int, scrollProxy: ScrollViewProxy) {
        focusTransitionCoordinator.move(
            offset: offset,
            commit: fieldCommitRegistry.commit,
            assign: { focusedField = $0 },
            reveal: { revealFocusedField($0, scrollProxy: scrollProxy) }
        )
    }

    private func transitionFocus(to target: WorkoutField?, scrollProxy: ScrollViewProxy) {
        focusTransitionCoordinator.transition(
            to: target,
            commit: fieldCommitRegistry.commit,
            assign: { focusedField = $0 },
            reveal: { revealFocusedField($0, scrollProxy: scrollProxy) }
        )
    }

    private func resignFocus() {
        focusTransitionCoordinator.transition(
            to: nil,
            commit: fieldCommitRegistry.commit,
            assign: { focusedField = $0 },
            reveal: { _ in }
        )
    }

    private func revealFocusedField(_ field: WorkoutField, scrollProxy: ScrollViewProxy) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            scrollProxy.scrollTo(field, anchor: Self.focusRevealAnchor)
        }
    }

    private static func isSetField(_ field: WorkoutField?) -> Bool {
        switch field {
        case .setWeight, .setReps:
            return true
        case .workoutTitle, .workoutNotes, .exerciseNotes, nil:
            return false
        }
    }

    private static let focusRevealAnchor = UnitPoint(x: 0.5, y: 0.72)
}

/// Rebuilds the keyboard route only when structure, collapse, or note
/// disclosure changes. Focus-only parent updates do not reconstruct it.
private struct WorkoutFocusOrderLoader: View, @MainActor Equatable {
    let session: WorkoutSession
    let inputs: WorkoutFocusNavigator.StructureInputs
    let onUpdate: ([WorkoutField]) -> Void
    @State private var cache = WorkoutFocusOrderCache()

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session.id == rhs.session.id
            && lhs.inputs == rhs.inputs
    }

    var body: some View {
        let structureKey = WorkoutFocusNavigator.StructureKey(
            session: session,
            inputs: inputs
        )

        Color.clear
            .onChange(of: structureKey, initial: true) { _, _ in
                onUpdate(
                    cache.update(
                        for: session,
                        inputs: inputs,
                        structureKey: structureKey
                    )
                )
            }
    }
}

/// Fetches completed history only when one of its inputs changes. A query-backed
/// child still refreshes its fetch during focus-only SwiftUI updates, so this
/// loader listens to model saves and ignores value edits confined to the active
/// workout graph.
private struct PreviousSetsCacheLoader: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncScheduler.self) private var syncScheduler
    @State private var cache = PreviousSetsCacheLoaderCache()

    let session: WorkoutSession
    let onUpdate: ([UUID: [PreviousSetPerformance]]) -> Void

    var body: some View {
        let reloadTrigger = PreviousSetsCacheReloadTrigger(
            sessionID: session.id,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
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
                let changes = PreviousSetsCacheSaveChanges(notification: notification)
                let activeGraphIDs = cache.activeGraphIDs(for: session)
                let activeStructureChanged = cache.activeStructureChanged(for: session)

                guard PreviousSetsCacheReloadPolicy.shouldReload(
                    insertedIDs: changes.insertedIDs,
                    updatedIDs: changes.updatedIDs,
                    deletedIDs: changes.deletedIDs,
                    activeGraphIDs: activeGraphIDs,
                    activeStructureChanged: activeStructureChanged,
                    invalidatedAllIdentifiers: changes.invalidatedAllIdentifiers
                ) else { return }

                cache.reload(
                    session: session,
                    context: modelContext,
                    ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
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
private final class PreviousSetsCacheLoaderCache {
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
        let descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        guard let sessions = try? context.fetch(descriptor) else { return }

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
    let onFinish: () -> Void
    @State private var cachedMetrics: WorkoutMetrics?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.session.id == rhs.session.id
    }

    var body: some View {
        let cacheKey = WorkoutMetrics.CacheKey(session: session)

        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            WorkoutHeaderView(
                elapsedSeconds: session.effectiveDurationSeconds(now: timeline.date),
                completedSets: cachedMetrics?.completedSetCount ?? 0,
                totalSets: cachedMetrics?.totalSetCount ?? 0,
                onFinish: onFinish
            )
        }
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
                set: { draft = $0 }
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
