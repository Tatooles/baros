import Foundation

enum UIHangScreen: String, CaseIterable {
    case launch, home, history, profile

    init(tab: AppTab) {
        switch tab {
        case .home: self = .home
        case .history: self = .history
        case .profile: self = .profile
        }
    }
}

enum UIHangPresentation: String, CaseIterable {
    case onboarding
    case whatsNew = "whats_new"
    case activeWorkout = "active_workout"
}

enum UIHangScenePhase: String, CaseIterable {
    case active, inactive, background
}

enum UIHangSurface: String, Equatable {
    case launch, home, history, profile, onboarding
    case whatsNew = "whats_new"
    case activeWorkout = "active_workout"
    case exercisePicker = "exercise_picker"
}

/// Count only the visible workout structure, without sorting or recording content.
struct UIHangWorkoutSize {
    let exerciseCount: Int
    let setCount: Int

    init(session: WorkoutSession) {
        var exercises = 0
        var sets = 0
        for exercise in session.loggedExercises where exercise.deletedAt == nil {
            exercises += 1
            for set in exercise.sets where set.deletedAt == nil { sets += 1 }
        }
        exerciseCount = exercises
        setCount = sets
    }
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
    case launchStarted = "launch_started"
    case homeShown = "home_shown"
    case historyShown = "history_shown"
    case profileShown = "profile_shown"
    case onboardingPresented = "onboarding_presented"
    case whatsNewPresented = "whats_new_presented"
    case activeWorkoutPresented = "active_workout_presented"
    case presentationDismissed = "presentation_dismissed"
    case sceneActive = "scene_active"
    case sceneInactive = "scene_inactive"
    case sceneBackground = "scene_background"
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

    var baseScreen: UIHangScreen? = nil
    var scenePhase: UIHangScenePhase? = nil
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
    private var baseScreen: UIHangScreen?
    private var presentation: UIHangPresentation?
    private var settingsWhatsNewIsPresented = false
    private var scenePhase: UIHangScenePhase?
    private var activeWorkoutIsCurrent = false
    private var exercisePickerIsCurrent = false
    private var exerciseSearchIsEditing = false
    private var exerciseCountBucket: UIHangCountBucket?
    private var setCountBucket: UIHangCountBucket?
    private var focusedField: UIHangFocusedField?

    init(sink: any UIHangContextSink) {
        self.sink = sink
    }

    func install(sink: any UIHangContextSink) {
        self.sink = sink
        sink.apply(snapshot)
    }

    func launchStarted() {
        shellChanged(screen: .launch, presentation: nil)
    }

    func shellChanged(screen: UIHangScreen, presentation: UIHangPresentation?) {
        if screen != baseScreen {
            let breadcrumb: UIHangBreadcrumb = switch screen {
            case .launch: .launchStarted
            case .home: .homeShown
            case .history: .historyShown
            case .profile: .profileShown
            }
            sink.addBreadcrumb(breadcrumb)
        }
        if presentation != self.presentation {
            let breadcrumb: UIHangBreadcrumb = switch presentation {
            case .onboarding: .onboardingPresented
            case .whatsNew: .whatsNewPresented
            case .activeWorkout: .activeWorkoutPresented
            case nil: .presentationDismissed
            }
            sink.addBreadcrumb(breadcrumb)
        }
        baseScreen = screen
        self.presentation = presentation
        if screen != .profile || presentation != nil { settingsWhatsNewIsPresented = false }
        if presentation != .activeWorkout { clearWorkout() }
        publish()
    }

    func settingsWhatsNewChanged(isPresented: Bool) {
        // This sheet belongs to Settings, independently of the shell's launch sheet.
        guard !isPresented || (baseScreen == .profile && presentation == nil),
              isPresented != settingsWhatsNewIsPresented else { return }
        settingsWhatsNewIsPresented = isPresented
        sink.addBreadcrumb(isPresented ? .whatsNewPresented : .presentationDismissed)
        publish()
    }

    func sceneChanged(to phase: UIHangScenePhase) {
        guard phase != scenePhase else { return }
        scenePhase = phase
        if phase != .active {
            focusedField = nil
            exerciseSearchIsEditing = false
        }
        let breadcrumb: UIHangBreadcrumb = switch phase {
        case .active: .sceneActive
        case .inactive: .sceneInactive
        case .background: .sceneBackground
        }
        sink.addBreadcrumb(breadcrumb)
        publish()
    }

    func activeWorkoutBecameCurrent(exerciseCount: Int, setCount: Int) {
        // Ignore a late child callback after the shell has changed presentation.
        guard baseScreen == nil || presentation == .activeWorkout else { return }
        activeWorkoutIsCurrent = true
        self.exerciseCountBucket = UIHangCountBucket(count: exerciseCount)
        self.setCountBucket = UIHangCountBucket(count: setCount)
        focusedField = nil
        publish()
    }

    func activeWorkoutStructureChanged(exerciseCount: Int, setCount: Int) {
        guard activeWorkoutIsCurrent else { return }
        exerciseCountBucket = UIHangCountBucket(count: exerciseCount)
        setCountBucket = UIHangCountBucket(count: setCount)
        publish()
    }

    func focusChanged(to field: WorkoutField?) {
        guard activeWorkoutIsCurrent, !exercisePickerIsCurrent,
              scenePhase == nil || scenePhase == .active else { return }
        focusedField = field.map(UIHangFocusedField.init)
        publish()
    }

    func addExercisePresented() {
        guard activeWorkoutIsCurrent, !exercisePickerIsCurrent else { return }
        exercisePickerIsCurrent = true
        exerciseSearchIsEditing = false
        focusedField = nil
        sink.addBreadcrumb(.addExercisePresented)
        publish()
    }

    func addExerciseDismissed() {
        guard activeWorkoutIsCurrent, exercisePickerIsCurrent else { return }
        if exerciseSearchIsEditing { exerciseSearchEditingChanged(isEditing: false) }
        exercisePickerIsCurrent = false
        sink.addBreadcrumb(.addExerciseDismissed)
        publish()
    }

    func exerciseSearchEditingChanged(isEditing: Bool) {
        guard activeWorkoutIsCurrent, exercisePickerIsCurrent,
              scenePhase != .background,
              isEditing != exerciseSearchIsEditing else { return }
        exerciseSearchIsEditing = isEditing
        sink.addBreadcrumb(isEditing ? .exerciseSearchBegan : .exerciseSearchEnded)
    }

    func activeWorkoutCeasedBeingCurrent() {
        clearWorkout()
        publish()
    }

    private func clearWorkout() {
        activeWorkoutIsCurrent = false
        exercisePickerIsCurrent = false
        exerciseSearchIsEditing = false
        exerciseCountBucket = nil
        setCountBucket = nil
        focusedField = nil
    }

    private func publish() {
        guard scenePhase != .background else {
            apply(.empty)
            return
        }
        let surface: UIHangSurface?
        if settingsWhatsNewIsPresented {
            surface = .whatsNew
        } else if exercisePickerIsCurrent {
            surface = .exercisePicker
        } else if activeWorkoutIsCurrent {
            surface = .activeWorkout
        } else if let presentation {
            surface = UIHangSurface(rawValue: presentation.rawValue)
        } else {
            surface = baseScreen.flatMap { UIHangSurface(rawValue: $0.rawValue) }
        }
        apply(UIHangContextSnapshot(
            baseScreen: baseScreen,
            scenePhase: scenePhase,
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
