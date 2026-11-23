import BarosCore
import SwiftData
import SwiftUI

extension Animation {
    static let workoutFocusDismissal = Animation.smooth(duration: 0.25)
}

struct WorkoutSessionView: View {
    @AppStorage(RPEPreference.storageKey) private var rpeEnabled = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(CurrentOwnerCoordinator.self) private var currentOwnerCoordinator
    let session: WorkoutSession
    @Bindable var engine: ActiveWorkoutEngine
    @Bindable var navigationState: AppNavigationState
    let onMinimizePreparationChanged: ((() -> Void)?) -> Void
    @State private var showsSetSaveFailure = false
    @State private var showsSupersetSaveFailure = false
    @State private var isFinishSheetPresented = false
    @State private var isReorderExercisesPresented = false
    @State private var isAddExercisePresented = false
    @State private var swappingLoggedExercise: LoggedExercise?
    @State private var selectedHistoryExercise: LoggedExercise?
    @State private var pendingScrollTarget: UUID?
    @State private var collapsedExerciseIDs: Set<UUID> = []
    @State private var revealedExerciseNoteIDs: Set<UUID> = []
    @State private var isWorkoutNoteRevealed = false
    @State private var cachedSortedLoggedExercises: [LoggedExercise]?
    @State private var cachedPreviousSets: [UUID: [PreviousSetPerformance]] = [:]
    @State private var rpeEditingSetID: UUID?
    @State private var timeEntry: SetTimeEntry?
    @State private var bottomSafeAreaInset: CGFloat = 0
    @State private var setInputRegistry = ActiveSetInputRegistry()
    @State private var focusTransitionCoordinator = WorkoutFocusTransitionCoordinator()
    @FocusState private var focusedField: WorkoutField?
    @Query(sort: \UserSettings.createdAt) private var settingsRecords: [UserSettings]

    private var weightUnit: MeasurementUnit {
        UserSettings.visibleSettingsRecords(
            from: settingsRecords,
            ownerTokenIdentifier: currentOwnerCoordinator.localDataOwnerTokenIdentifier
        ).first?.weightUnit ?? .pounds
    }

    var body: some View {
        let sortedLoggedExercises = cachedSortedLoggedExercises ?? session.sortedLoggedExercises

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

                    let supersetGroupIDs = sortedLoggedExercises.map(\.supersetGroupID)
                    let exerciseIndexes = Dictionary(
                        uniqueKeysWithValues: sortedLoggedExercises.enumerated().map { ($1.id, $0) }
                    )
                    ForEach(SupersetGrouping.blocks(sortedLoggedExercises, groupID: \.supersetGroupID)) { block in
                        if block.isSuperset {
                            SupersetRail(count: block.members.count) {
                                ForEach(block.members) { loggedExercise in
                                    exerciseCard(loggedExercise, index: exerciseIndexes[loggedExercise.id] ?? 0,
                                                 supersetGroupIDs: supersetGroupIDs)
                                }
                            }
                        } else {
                            exerciseCard(block.members[0], index: exerciseIndexes[block.id] ?? 0,
                                         supersetGroupIDs: supersetGroupIDs)
                        }
                    }

                    if !showsBottomActionBar {
                        workoutActions
                    }
                }
                .padding(.horizontal, AppTheme.shellPadding)
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .safeAreaBar(edge: .top, spacing: 0) {
                ActiveWorkoutMetricsHeader(session: session, restTimer: engine.restTimer) {
                    guard prepareForPresentation() else { return }
                    isFinishSheetPresented = true
                }
                .equatable()
            }
            .onScrollPhaseChange { _, phase in
                if phase != .idle { engine.restTimer.collapseControls() }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase != .active, focusedField != nil || timeEntry != nil {
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
                if newField != nil {
                    engine.restTimer.collapseControls()
                    keepShownTime()
                    timeEntry = nil
                }
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
                if timeEntry?.setID != rpeEditingSetID,
                   RPEEditingFocusPolicy.shouldReset(editingSetID: rpeEditingSetID, newFocusedField: newField) {
                    rpeEditingSetID = nil
                }
            }
            .revealsSetTimeCell(editing: timeEntry?.setID)
            .onChange(of: timeEntry?.setID) { _, setID in
                if setID != nil { engine.restTimer.collapseControls() }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                if showsBottomActionBar {
                    workoutActions
                        .padding(.horizontal, AppTheme.shellPadding)
                        .padding(.top, 12)
                        .padding(.bottom, workoutActionsBottomPadding)
                }
            }
            // Replaces a `.keyboard` toolbar, whose full-width strip swallows taps
            // between its buttons. As a safe-area inset, the system's keyboard
            // reveal clears the bar, and only the buttons themselves take touches.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isChildPresentationActive {
                    EmptyView()
                } else if focusedField != nil || timeEntrySet != nil {
                    keyboardAccessory
                }
            }
            .ignoresSafeArea(.container, edges: showsBottomActionBar ? .bottom : [])
            .background {
                PreviousSetsCacheLoader(session: session) {
                    cachedPreviousSets = $0
                    engine.previousSetsByLoggedExerciseID = $0
                }
                .frame(width: 0, height: 0)
            }
        }
        .background {
            Color.clear
                .ignoresSafeArea(.keyboard)
                .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: {
                    bottomSafeAreaInset = $0
                }
        }
        .disabled(engine.hasPendingSetSave)
        .alert("Couldn't save this edit", isPresented: $showsSetSaveFailure) {
            Button("Retry") {
                do {
                    try engine.retrySetSave(in: session, context: modelContext)
                } catch {
                }
            }
            .disabled(!engine.canRetrySetSave(in: session))
            Button("Discard Edit", role: .cancel) {
                engine.discardSetSave()
            }
        } message: {
            Text("Retry saving, or discard this edit to continue. Your previously saved sets will remain.")
        }
        .alert("Couldn't Change Superset", isPresented: $showsSupersetSaveFailure) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Your workout wasn't changed. Try again from the exercise menu.")
        }
        .onChange(of: engine.pendingSetSaveID, initial: true) { _, failureID in
            if failureID != nil { resignFocus() }
            showsSetSaveFailure = failureID != nil && scenePhase == .active
        }
        .onChange(of: showsSetSaveFailure) { _, isPresented in
            guard !isPresented else { return }
            Task { @MainActor in
                await Task.yield()
                guard scenePhase == .active, engine.hasPendingSetSave else { return }
                showsSetSaveFailure = true
            }
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            engine.setInputRegistry = setInputRegistry
            updateUIHangWorkoutContext(becameCurrent: true)
            focusTransitionCoordinator.synchronizeFocus(focusedField)
            onMinimizePreparationChanged {
                resignFocus()
            }
        }
        .onChange(of: loggedExerciseStructureKey, initial: true) { _, _ in
            cachedSortedLoggedExercises = session.sortedLoggedExercises
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

    private var showsBottomActionBar: Bool {
        focusedField == nil && timeEntrySet == nil && !isChildPresentationActive
    }

    private var workoutActionsBottomPadding: CGFloat {
        min(bottomSafeAreaInset + 4, 22)
    }

    private var workoutActions: some View {
        let actionLayout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return actionLayout {
            if !(cachedSortedLoggedExercises ?? session.sortedLoggedExercises).isEmpty {
                editWorkoutPill
            }

            Button {
                guard prepareForPresentation() else { return }
                isAddExercisePresented = true
            } label: {
                Label("Add Exercise", systemImage: "plus")
                    .font(.headline)
                    .foregroundStyle(AppTheme.brandAccentForeground)
                    .frame(maxWidth: .infinity, minHeight: actionMinHeight)
                    .glassEffect(.regular.tint(AppTheme.brandAccentMuted).interactive(), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("AddExerciseButton")
        }
    }

    @ScaledMetric(relativeTo: .headline) private var scaledActionHeight: CGFloat = 50

    private var actionMinHeight: CGFloat { max(50, scaledActionHeight) }

    private var editWorkoutPill: some View {
        Button {
            guard prepareForPresentation() else { return }
            isReorderExercisesPresented = true
        } label: {
            Label("Edit", systemImage: "pencil")
                .font(.headline)
                .foregroundStyle(AppTheme.brandAccentForeground)
                .fixedSize()
                .padding(.horizontal, 20)
                .frame(minWidth: 108, minHeight: actionMinHeight)
                .glassEffect(.regular.interactive(), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Edit Workout")
        .accessibilityIdentifier("ActiveWorkoutEditButton")
    }

    private var showsRPEButton: Bool {
        rpeEnabled && accessorySetID != nil
    }

    private var accessorySetID: UUID? {
        focusedSetID ?? timeEntry?.setID
    }

    private var keyboardAccessory: some View {
        HStack(spacing: 8) {
            if rpeEditingSetID != nil {
                RPEChipRow(selected: editingSet?.rpe, onSelect: selectRPE)
                    .padding(.vertical, 2)
                    .clipShape(Capsule())
                    .glassEffect(.regular, in: Capsule())
            } else {
                if let accessorySetID, showsRPEButton {
                    Button("RPE") {
                        rpeEditingSetID = accessorySetID
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
        .padding(4)
        .background {
            Capsule()
                .fill(AppTheme.keyboardBandFill)
                .shadow(color: AppTheme.keyboardBandShadow, radius: 10, y: -2)
                .opacity(rpeEditingSetID == nil && showsRPEButton ? 1 : 0)
                .allowsHitTesting(false)
        }
        .padding(.horizontal, AppTheme.shellPadding - 4)
        // The keyboard reveal clears the text field, not its taller rounded
        // container. Transparent top room keeps the whole field off the buttons.
        .padding(.top, 20)
        .padding(.bottom, 8)
    }

    private func selectRPE(_ value: Double?) {
        guard !engine.hasPendingSetSave else { return }
        var shownTime: Int?
        if let timeEntry, timeEntry.setID == rpeEditingSetID, value != nil {
            guard timeEntry.seconds > 0 else { return }
            shownTime = timeEntry.seconds
        }
        if let set = editingSet {
            var preparedValues = setInputRegistry.prepareSetValues(
                for: .setReps(set.id),
                completesSet: value != nil
            ) ?? .init(set)
            if let shownTime { preparedValues = preparedValues.settingDuration(shownTime) }
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
                }
            }
        }
        rpeEditingSetID = nil
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
        activeSet(rpeEditingSetID)
    }

    private var timeEntrySet: LoggedSet? {
        activeSet(timeEntry?.setID)
    }

    private func activeSet(_ id: UUID?) -> LoggedSet? {
        guard let id else { return nil }
        for loggedExercise in cachedSortedLoggedExercises ?? session.sortedLoggedExercises {
            if let match = loggedExercise.sets.first(where: {
                $0.id == id && $0.deletedAt == nil
            }) {
                return match
            }
        }
        return nil
    }

    private func editTime(_ set: LoggedSet, _ edit: SetTimeEdit) {
        switch edit {
        case .open(let startingSeconds):
            guard timeEntry?.setID != set.id else { return }
            setInputRegistry.commit(focusedField)
            guard !engine.hasPendingSetSave else { return }
            keepShownTime()
            rpeEditingSetID = nil
            timeEntry = SetTimeEntry(setID: set.id, startingSeconds: startingSeconds)
        case .change(let seconds):
            guard timeEntry?.setID == set.id else { return }
            timeEntry?.seconds = seconds
            saveTime(seconds, forSetID: set.id)
        case .close:
            guard timeEntry?.setID == set.id else { return }
            keepShownTime()
            timeEntry = nil
            rpeEditingSetID = nil
        }
    }

    private func keepShownTime() {
        guard let timeEntry, timeEntry.seconds > 0 else { return }
        saveTime(timeEntry.seconds, forSetID: timeEntry.setID)
    }

    private func saveTime(_ seconds: Int, forSetID setID: UUID) {
        guard !engine.hasPendingSetSave, let set = activeSet(setID) else { return }
        let duration = seconds > 0 ? seconds : nil
        guard WorkoutNumericInputPolicy.validatedDuration(set.durationSeconds) != duration else { return }
        do {
            try engine.commitActiveSetDraft(
                set,
                values: ActiveWorkoutSetInput.Values(set).settingDuration(duration),
                context: modelContext
            )
        } catch {
        }
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

    private func exerciseCard(
        _ loggedExercise: LoggedExercise,
        index exerciseIndex: Int,
        supersetGroupIDs: [UUID?]
    ) -> some View {
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
            supersetActions: supersetActions(for: loggedExercise, at: exerciseIndex, groupIDs: supersetGroupIDs),
            viewHistory: {
                guard prepareForPresentation() else { return }
                selectedHistoryExercise = loggedExercise
            },
            onSwapExercise: {
                guard prepareForPresentation() else { return }
                swappingLoggedExercise = loggedExercise
            },
            onEditRPE: { set in
                if timeEntry?.setID != set.id { focusedField = .setReps(set.id) }
                rpeEditingSetID = set.id
            },
            timeEntry: timeEntry,
            onEditTime: editTime
        )
        .id(loggedExercise.id)
    }

    private func supersetActions(
        for loggedExercise: LoggedExercise,
        at index: Int,
        groupIDs: [UUID?]
    ) -> ExerciseCardView.SupersetActions {
        func action(_ change: ActiveWorkoutEngine.SupersetChange) -> () -> Void {
            { changeSuperset(change, for: loggedExercise) }
        }
        return ExerciseCardView.SupersetActions(
            joinPrevious: index > 0 && !SupersetGrouping.areGrouped(groupIDs, index, index - 1)
                ? action(.joinPrevious) : nil,
            joinNext: index + 1 < groupIDs.count && !SupersetGrouping.areGrouped(groupIDs, index, index + 1)
                ? action(.joinNext) : nil,
            remove: SupersetGrouping.isGrouped(groupIDs, at: index) ? action(.remove) : nil
        )
    }

    private func changeSuperset(_ change: ActiveWorkoutEngine.SupersetChange, for loggedExercise: LoggedExercise) {
        guard prepareForPresentation() else { return }
        do {
            try withAnimation(.snappy) {
                try engine.changeSuperset(change, for: loggedExercise, context: modelContext)
            }
        } catch {
            showsSupersetSaveFailure = true
        }
    }

    private func prepareForPresentation() -> Bool {
        resignFocus()
        return !engine.hasPendingSetSave
    }

    private func resignFocus() {
        if timeEntry != nil {
            keepShownTime()
            withAnimation(.workoutFocusDismissal) { timeEntry = nil }
            rpeEditingSetID = nil
        }
        focusTransitionCoordinator.transition(
            to: nil,
            commit: setInputRegistry.commit,
            assign: { field in
                withAnimation(.workoutFocusDismissal) { focusedField = field }
            }
        )
    }

}

private struct LoggedExerciseStructureValue: Hashable {
    let id: UUID
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
            workoutID: session.id,
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
