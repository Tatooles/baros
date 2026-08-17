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
    @State private var cachedPreviousSets: [UUID: [PreviousSetPerformance]] = [:]
    @State private var rpeEditingSetID: UUID?
    @State private var rpeEditingSourceField: WorkoutField?
    @FocusState private var focusedField: WorkoutField?
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
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
                            focusedField: $focusedField,
                            weightUnit: weightUnit,
                            previousSets: cachedPreviousSets[loggedExercise.id] ?? [],
                            canReorder: canReorderExercises,
                            viewHistory: {
                                focusedField = nil
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
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let metrics = WorkoutMetrics(session: session, now: timeline.date)
                    WorkoutHeaderView(
                        elapsedSeconds: metrics.durationSeconds,
                        completedSets: metrics.completedSetCount,
                        totalSets: metrics.totalSetCount,
                        onFinish: {
                            // Flush any in-progress field edit through the
                            // commit path before the finish sheet reads the model.
                            focusedField = nil
                            isFinishSheetPresented = true
                        }
                    )
                }
            }
            .onChange(of: previousSetsCacheKey, initial: true) { _, _ in
                cachedPreviousSets = previousSetsByExerciseID(for: session.sortedLoggedExercises)
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Resigning focus routes pending drafts through the normal
                // commit path before the app is backgrounded or suspended.
                if newPhase != .active, focusedField != nil {
                    focusedField = nil
                }
            }
            .onChange(of: isAddExercisePresented) { _, isPresented in
                guard !isPresented else { return }

                let scrollTarget = pendingScrollTarget
                let focusedField = pendingFocusedField
                pendingScrollTarget = nil
                self.pendingFocusedField = nil
                recentlyAddedExerciseID = scrollTarget

                Task { @MainActor in
                    self.focusedField = focusedField

                    if let scrollTarget {
                        try? await Task.sleep(for: .milliseconds(350))
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            scrollProxy.scrollTo(scrollTarget, anchor: .top)
                        }
                    }
                }
            }
            .onChange(of: focusedField) { _, newField in
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

                if let newField, !shouldRetainNewExerciseReveal {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            scrollProxy.scrollTo(newField, anchor: Self.focusRevealAnchor)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if rpeEditingSetID != nil {
                        RPEChipRow(
                            selected: editingSet?.rpe,
                            onSelect: { value in
                                let nextField = rpeNextFocusedField
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
                                focusedField = nextField
                            }
                        )
                    } else {
                        let previousField = previousFocusedField
                        let nextField = nextFocusedField

                        Button {
                            focusedField = previousField
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .disabled(previousField == nil)
                        .accessibilityLabel("Previous field")
                        .accessibilityIdentifier("PreviousWorkoutFieldButton")

                        Button {
                            focusedField = nextField
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .disabled(nextField == nil)
                        .accessibilityLabel("Next field")
                        .accessibilityIdentifier("NextWorkoutFieldButton")

                        if let focusedSetID {
                            Button("RPE") {
                                rpeEditingSourceField = focusedField
                                rpeEditingSetID = focusedSetID
                            }
                            .font(.system(size: 16, weight: .semibold))
                            .accessibilityIdentifier("RPEToolbarButton")
                        }

                        Spacer()

                        Button("Done") {
                            focusedField = nil
                        }
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityIdentifier("DismissKeyboardButton")
                    }
                }
            }
        }
        .background(AppTheme.canvasBackground.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
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
            }
        }
    }

    private var focusOrder: [WorkoutField] {
        WorkoutFocusNavigator.focusOrder(
            for: session,
            collapsedExerciseIDs: collapsedExerciseIDs,
            revealedExerciseNoteIDs: revealedExerciseNoteIDs,
            isWorkoutNoteRevealed: isWorkoutNoteRevealed
        )
    }

    // The lookup scans completed history, so it is cached in @State and
    // recomputed only when its inputs change (see CacheKey) rather than on
    // every body evaluation.
    private var previousSetsCacheKey: PreviousSetPerformance.CacheKey {
        PreviousSetPerformance.CacheKey(
            session: session,
            sessions: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
            lastSyncedAt: syncScheduler.lastSyncedAt
        )
    }

    private func previousSetsByExerciseID(for loggedExercises: [LoggedExercise]) -> [UUID: [PreviousSetPerformance]] {
        PreviousSetPerformance.lastCompletedSetsByExerciseID(
            for: loggedExercises,
            in: sessions,
            ownerTokenIdentifier: syncScheduler.currentOwnerTokenIdentifier,
            sourceSessionID: session.source == .pastWorkout ? session.sourceSessionID : nil
        )
    }

    private var previousFocusedField: WorkoutField? {
        WorkoutFocusNavigator.adjacentField(from: focusedField, in: focusOrder, offset: -1)
    }

    private var nextFocusedField: WorkoutField? {
        WorkoutFocusNavigator.adjacentField(from: focusedField, in: focusOrder, offset: 1)
    }

    private var rpeNextFocusedField: WorkoutField? {
        WorkoutFocusNavigator.adjacentField(
            from: rpeEditingSourceField ?? focusedField,
            in: focusOrder,
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
                        focusedField = nil
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
