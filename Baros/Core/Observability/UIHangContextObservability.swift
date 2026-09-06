import Foundation

enum UIHangSurface: String, Equatable {
    case activeWorkout = "active_workout"
    case exercisePicker = "exercise_picker"
}

/// Shared, bounded buckets keep workout scale useful without sending exact counts.
enum UIHangCountBucket: String, Equatable {
    case zero = "0"
    case one = "1"
    case twoToFive = "2_5"
    case sixToTen = "6_10"
    case elevenToTwenty = "11_20"
    case twentyOneOrMore = "21_plus"

    init(count: Int) {
        switch max(0, count) {
        case 0:
            self = .zero
        case 1:
            self = .one
        case 2...5:
            self = .twoToFive
        case 6...10:
            self = .sixToTen
        case 11...20:
            self = .elevenToTwenty
        default:
            self = .twentyOneOrMore
        }
    }
}

enum UIHangFocusedField: String, CaseIterable, Equatable {
    case workoutText = "workout_text"
    case exerciseNote = "exercise_note"
    case setWeight = "set_weight"
    case setReps = "set_reps"

    init(workoutField: WorkoutField) {
        switch workoutField {
        case .workoutTitle, .workoutNotes:
            self = .workoutText
        case .exerciseNotes:
            self = .exerciseNote
        case .setWeight:
            self = .setWeight
        case .setReps:
            self = .setReps
        }
    }
}

enum UIHangBreadcrumb: String, Equatable {
    case addExercisePresented = "add_exercise_presented"
    case addExerciseDismissed = "add_exercise_dismissed"
    case exerciseSearchBegan = "exercise_search_began"
    case exerciseSearchEnded = "exercise_search_ended"
}

struct UIHangContextSnapshot: Equatable {
    static let empty = UIHangContextSnapshot(
        surface: nil,
        exerciseCountBucket: nil,
        setCountBucket: nil,
        focusedField: nil
    )

    let surface: UIHangSurface?
    let exerciseCountBucket: UIHangCountBucket?
    let setCountBucket: UIHangCountBucket?
    let focusedField: UIHangFocusedField?
}

@MainActor
protocol UIHangContextSink: AnyObject {
    func apply(_ snapshot: UIHangContextSnapshot)
    func addBreadcrumb(_ breadcrumb: UIHangBreadcrumb)
}

@MainActor
final class UIHangContextObservability {
    static let shared = UIHangContextObservability(sink: DisabledUIHangContextSink.shared)

    private var sink: any UIHangContextSink
    private var snapshot = UIHangContextSnapshot.empty
    private var activeWorkoutIsCurrent = false
    private var exerciseSearchIsEditing = false

    init(sink: any UIHangContextSink) {
        self.sink = sink
    }

    func install(sink: any UIHangContextSink) {
        self.sink = sink
        sink.apply(snapshot)
    }

    func activeWorkoutBecameCurrent(exerciseCount: Int, setCount: Int) {
        activeWorkoutIsCurrent = true
        update(
            surface: .activeWorkout,
            exerciseCount: exerciseCount,
            setCount: setCount,
            focusedField: nil
        )
    }

    func activeWorkoutStructureChanged(exerciseCount: Int, setCount: Int) {
        guard activeWorkoutIsCurrent else { return }
        update(
            surface: snapshot.surface,
            exerciseCount: exerciseCount,
            setCount: setCount,
            focusedField: snapshot.focusedField
        )
    }

    func focusChanged(to field: WorkoutField?) {
        guard activeWorkoutIsCurrent, snapshot.surface == .activeWorkout else { return }
        update(
            surface: .activeWorkout,
            exerciseCountBucket: snapshot.exerciseCountBucket,
            setCountBucket: snapshot.setCountBucket,
            focusedField: field.map(UIHangFocusedField.init)
        )
    }

    func addExercisePresented() {
        guard activeWorkoutIsCurrent, snapshot.surface != .exercisePicker else { return }
        exerciseSearchIsEditing = false
        sink.addBreadcrumb(.addExercisePresented)
        update(
            surface: .exercisePicker,
            exerciseCountBucket: snapshot.exerciseCountBucket,
            setCountBucket: snapshot.setCountBucket,
            focusedField: nil
        )
    }

    func addExerciseDismissed() {
        guard activeWorkoutIsCurrent, snapshot.surface == .exercisePicker else { return }
        if exerciseSearchIsEditing {
            exerciseSearchEditingChanged(isEditing: false)
        }
        sink.addBreadcrumb(.addExerciseDismissed)
        update(
            surface: .activeWorkout,
            exerciseCountBucket: snapshot.exerciseCountBucket,
            setCountBucket: snapshot.setCountBucket,
            focusedField: nil
        )
    }

    func exerciseSearchEditingChanged(isEditing: Bool) {
        guard activeWorkoutIsCurrent,
              snapshot.surface == .exercisePicker,
              isEditing != exerciseSearchIsEditing else {
            return
        }
        exerciseSearchIsEditing = isEditing
        sink.addBreadcrumb(isEditing ? .exerciseSearchBegan : .exerciseSearchEnded)
    }

    func activeWorkoutCeasedBeingCurrent() {
        activeWorkoutIsCurrent = false
        exerciseSearchIsEditing = false
        apply(.empty)
    }

    private func update(
        surface: UIHangSurface?,
        exerciseCount: Int,
        setCount: Int,
        focusedField: UIHangFocusedField?
    ) {
        update(
            surface: surface,
            exerciseCountBucket: UIHangCountBucket(count: exerciseCount),
            setCountBucket: UIHangCountBucket(count: setCount),
            focusedField: focusedField
        )
    }

    private func update(
        surface: UIHangSurface?,
        exerciseCountBucket: UIHangCountBucket?,
        setCountBucket: UIHangCountBucket?,
        focusedField: UIHangFocusedField?
    ) {
        apply(UIHangContextSnapshot(
            surface: surface,
            exerciseCountBucket: exerciseCountBucket,
            setCountBucket: setCountBucket,
            focusedField: focusedField
        ))
    }

    private func apply(_ newSnapshot: UIHangContextSnapshot) {
        guard newSnapshot != snapshot else { return }
        snapshot = newSnapshot
        sink.apply(newSnapshot)
    }
}

@MainActor
private final class DisabledUIHangContextSink: UIHangContextSink {
    static let shared = DisabledUIHangContextSink()

    private init() {}

    func apply(_: UIHangContextSnapshot) {}
    func addBreadcrumb(_: UIHangBreadcrumb) {}
}
