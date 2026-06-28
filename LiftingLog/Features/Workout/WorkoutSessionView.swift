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
    @State private var rpeEditingSetID: UUID?
    @State private var rpeEditingSourceField: WorkoutField?
    @FocusState private var focusedField: WorkoutField?
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]
    private let contentBottomPadding: CGFloat = 120

    var body: some View {
        let sortedLoggedExercises = session.sortedLoggedExercises
        let canReorderExercises = sortedLoggedExercises.count >= 2
        let previousSetsByExerciseID = previousSetsByExerciseID(for: sortedLoggedExercises)

        ScrollViewReader { scrollProxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        WorkoutTitleField(
                            placeholder: "Workout Name",
                            text: workoutTitleBinding,
                            focusTarget: .workoutTitle,
                            focusedField: $focusedField,
                            accessibilityIdentifier: "WorkoutTitle"
                        )

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
                            previousSets: previousSetsByExerciseID[loggedExercise.id] ?? [],
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

                    SurfaceCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("WORKOUT NOTES")
                                .font(.caption2.weight(.bold))
                                .tracking(1.8)
                                .foregroundStyle(AppTheme.textSecondary)
                            TextField(
                                "How did this session feel? Any notes for next time...",
                                text: workoutNotesBinding,
                                axis: .vertical
                            )
                            .font(.subheadline)
                            .foregroundStyle(AppTheme.textPrimary)
                            .lineLimit(4...6)
                            .focused($focusedField, equals: .workoutNotes)
                            .padding(12)
                            .background(
                                AppTheme.fieldFill,
                                in: RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.fieldCornerRadius, style: .continuous)
                                    .strokeBorder(
                                        focusedField == .workoutNotes ? AppTheme.accentBright.opacity(0.7) : .clear,
                                        lineWidth: 1.5
                                    )
                            )
                            .animation(.easeOut(duration: 0.15), value: focusedField == .workoutNotes)
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
                            isFinishSheetPresented = true
                        }
                    )
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
            .onChange(of: focusedField) { previousField, newField in
                if RPEEditingFocusPolicy.shouldReset(editingSetID: rpeEditingSetID, newFocusedField: newField) {
                    rpeEditingSetID = nil
                    rpeEditingSourceField = nil
                }

                if previousField == .workoutTitle, newField != .workoutTitle {
                    try? engine.finalizeWorkoutTitle(session, context: modelContext)
                }

                if let newField {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(250))
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            scrollProxy.scrollTo(newField, anchor: Self.focusRevealAnchor)
                        }
                    }
                } else if Self.isSetField(previousField), let recentlyAddedExerciseID {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(300))
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                            scrollProxy.scrollTo(recentlyAddedExerciseID, anchor: .top)
                        }
                        self.recentlyAddedExerciseID = nil
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
                            let scrollTarget = recentlyAddedExerciseID
                            focusedField = nil

                            if let scrollTarget {
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(500))
                                    withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
                                        scrollProxy.scrollTo(scrollTarget, anchor: .top)
                                    }
                                    self.recentlyAddedExerciseID = nil
                                }
                            }
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

    private var workoutTitleBinding: Binding<String> {
        Binding(
            get: { session.title },
            set: { newValue in
                try? engine.updateWorkoutTitle(newValue, session: session, context: modelContext)
            }
        )
    }

    private var workoutNotesBinding: Binding<String> {
        Binding(
            get: { session.notes },
            set: { newValue in
                try? engine.updateWorkoutNotes(newValue, session: session, context: modelContext)
            }
        )
    }

    private var referenceNotes: String? {
        let trimmed = session.referenceNotes?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var focusOrder: [WorkoutField] {
        WorkoutFocusNavigator.focusOrder(for: session, collapsedExerciseIDs: collapsedExerciseIDs)
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
