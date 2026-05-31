import SwiftData
import SwiftUI

enum WorkoutField: Hashable {
    case workoutTitle
    case workoutNotes
    case exerciseNotes(UUID)
    case setWeight(UUID)
    case setReps(UUID)
    case setRPE(UUID)
}

struct WorkoutSessionView: View {
    @Environment(\.modelContext) private var modelContext
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
    @FocusState private var focusedField: WorkoutField?
    private let contentBottomPadding: CGFloat = 180

    var body: some View {
        ScrollViewReader { scrollProxy in
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            TextField("Workout Name", text: workoutTitleBinding)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(AppTheme.textPrimary)
                                .focused($focusedField, equals: .workoutTitle)
                                .accessibilityIdentifier("WorkoutTitle")
                                .id(WorkoutField.workoutTitle)
                            Text(AppTheme.formatDate(session.startedAt))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        ForEach(Array(session.sortedLoggedExercises.enumerated()), id: \.element.id) { exerciseIndex, loggedExercise in
                            ExerciseCardView(
                                loggedExercise: loggedExercise,
                                exerciseIndex: exerciseIndex,
                                engine: engine,
                                isCollapsed: isCollapsedBinding(for: loggedExercise),
                                focusedField: $focusedField,
                                viewHistory: { selectedHistoryExercise = loggedExercise }
                            )
                            .id(loggedExercise.id)
                        }

                        Button {
                            isAddExercisePresented = true
                        } label: {
                            Label("Add Exercise", systemImage: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundStyle(AppTheme.accentBright)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 11)
                                .frame(minHeight: 44)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18)
                                        .stroke(style: StrokeStyle(lineWidth: 1.25, dash: [6, 4]))
                                        .foregroundStyle(AppTheme.accentBright.opacity(0.45))
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("AddExerciseButton")

                        SurfaceCard {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("WORKOUT NOTES")
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1.8)
                                    .foregroundStyle(AppTheme.textSecondary)
                                TextField(
                                    "How did this session feel? Any notes for next time...",
                                    text: workoutNotesBinding,
                                    axis: .vertical
                                )
                                .font(.system(size: 15))
                                .foregroundStyle(AppTheme.textPrimary)
                                .lineLimit(4...6)
                                .focused($focusedField, equals: .workoutNotes)
                                .id(WorkoutField.workoutNotes)

                                if let referenceNotes {
                                    Divider()
                                        .overlay(AppTheme.border)
                                        .padding(.vertical, 4)

                                    Text("LAST TIME")
                                        .font(.system(size: 10, weight: .bold))
                                        .tracking(1.4)
                                        .foregroundStyle(AppTheme.textTertiary)
                                    Text(referenceNotes)
                                        .font(.system(size: 14))
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
                    let metrics = WorkoutMetrics(session: session, now: timeline.date)
                    WorkoutHeaderView(
                        elapsedSeconds: metrics.durationSeconds,
                        completedSets: metrics.completedSetCount,
                        totalSets: metrics.totalSetCount,
                        canReorderExercises: session.sortedLoggedExercises.count >= 2,
                        onFinish: {
                            isFinishSheetPresented = true
                        },
                        onReorderExercises: {
                            isReorderExercisesPresented = true
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

    private var previousFocusedField: WorkoutField? {
        WorkoutFocusNavigator.adjacentField(from: focusedField, in: focusOrder, offset: -1)
    }

    private var nextFocusedField: WorkoutField? {
        WorkoutFocusNavigator.adjacentField(from: focusedField, in: focusOrder, offset: 1)
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
        case .setWeight, .setReps, .setRPE:
            return true
        case .workoutTitle, .workoutNotes, .exerciseNotes, nil:
            return false
        }
    }

    private static let focusRevealAnchor = UnitPoint(x: 0.5, y: 0.72)
}
