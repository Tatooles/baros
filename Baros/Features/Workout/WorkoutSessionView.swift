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
        // The workout notes card is the last element, so editing it needs
        // enough room to clear the floating keyboard accessory buttons,
        // which sit ~48pt above the keyboard's safe-area inset. Mid-list
        // fields always have real content below them, so keyboard avoidance
        // reveals them with no extra room at all.
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
                    }
                    .padding(.horizontal, 4)

                    ForEach(Array(sortedLoggedExercises.enumerated()), id: \.element.id) { exerciseIndex, loggedExercise in
                        ExerciseCardView(
                            loggedExercise: loggedExercise,
                            exerciseIndex: exerciseIndex,
                            engine: engine,
                            isCollapsed: isCollapsedBinding(for: loggedExercise),
                            focusedField: $focusedField,
                            weightUnit: weightUnit,
                            previousSets: cachedPreviousSets[loggedExercise.id] ?? [],
                            canReorder: canReorderExercises,
                            viewHistory: { selectedHistoryExercise = loggedExercise },
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
                            .foregroundStyle(AppTheme.accentBright)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(AppTheme.accentMuted, in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("AddExerciseButton")

                    WorkoutNotesDraftCard(
                        notes: session.notes,
                        referenceNotes: referenceNotes,
                        focusedField: $focusedField
                    ) { draft in
                        try? engine.updateWorkoutNotes(draft, session: session, context: modelContext)
                    }
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
        .background(AppTheme.subtleBackground.ignoresSafeArea())
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

    private var referenceNotes: String? {
        let trimmed = session.referenceNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var focusOrder: [WorkoutField] {
        WorkoutFocusNavigator.focusOrder(for: session, collapsedExerciseIDs: collapsedExerciseIDs)
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
                    collapsedExerciseIDs.insert(loggedExercise.id)
                } else {
                    collapsedExerciseIDs.remove(loggedExercise.id)
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

/// Owns the workout-notes draft; same leaf-scoped commit-on-focus-loss
/// contract as WorkoutTitleDraftField.
private struct WorkoutNotesDraftCard: View {
    let notes: String
    let referenceNotes: String?
    var focusedField: FocusState<WorkoutField?>.Binding
    let commit: (String) -> Void
    @State private var draft: String?

    var body: some View {
        SurfaceCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("WORKOUT NOTES")
                    .font(.caption2.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(AppTheme.textSecondary)
                TextField(
                    "How did this session feel? Any notes for next time...",
                    text: Binding(
                        get: { draft ?? notes },
                        set: { draft = $0 }
                    ),
                    axis: .vertical
                )
                .font(.subheadline)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(4...6)
                .focused(focusedField, equals: .workoutNotes)
                .padding(12)
                .workoutInputTapTarget(focusedField, equals: .workoutNotes)
                .background(
                    AppTheme.fieldFill,
                    in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                        .strokeBorder(
                            focusedField.wrappedValue == .workoutNotes ? AppTheme.accentBright.opacity(0.7) : .clear,
                            lineWidth: 1.5
                        )
                )
                .animation(.easeOut(duration: 0.15), value: focusedField.wrappedValue == .workoutNotes)
                .id(WorkoutField.workoutNotes)

                if let referenceNotes {
                    Divider()
                        .padding(.vertical, 4)

                    Text("LAST TIME")
                        .font(.caption2.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(AppTheme.textTertiary)
                    Text(referenceNotes)
                        .font(.footnote)
                        .foregroundStyle(AppTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .onChange(of: focusedField.wrappedValue) { previousField, newField in
            if previousField == .workoutNotes, newField != .workoutNotes {
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
