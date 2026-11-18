import BarosCore
import SwiftData
import SwiftUI

/// Each presenter owns its confirmation so a pushed screen or sheet cannot
/// accidentally present another screen's account action.
struct AccountTransitionButton<Label: View>: View {
    @Environment(\.modelContext) private var context
    @Environment(ActiveWorkoutEngine.self) private var engine
    @Environment(CurrentOwnerCoordinator.self) private var currentOwner
    @Environment(SyncScheduler.self) private var scheduler
    @State private var transition: WorkoutAccountTransition?
    /// The gate whose finish-or-discard choice is on screen. The alert's buttons act on
    /// this gate, never on a later one, so a late action cannot reach another request.
    @State private var choiceGate: WorkoutAccountTransition?
    @State private var errorMessage: String?
    let destination: WorkoutAccountTransition.Destination
    var role: ButtonRole? = nil
    let action: () async throws -> Void
    let label: Label

    init(destination: WorkoutAccountTransition.Destination, role: ButtonRole? = nil,
         action: @escaping () async throws -> Void, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.role = role
        self.action = action
        self.label = label()
    }

    private enum Prompt {
        case choices(WorkoutAccountTransition)
        case error(String)
    }

    /// One alert presents both the choice and any failure. Two `.alert` modifiers on one
    /// view let SwiftUI drop the error under load after the choice alert closed (#403).
    private var prompt: Prompt? {
        if let choiceGate { return .choices(choiceGate) }
        return errorMessage.map(Prompt.error)
    }

    private var isPromptPresented: Binding<Bool> {
        Binding(
            get: { prompt != nil },
            set: { isPresented in
                guard !isPresented else { return }
                // Dismissal closes whatever is showing. An error that arrives while the
                // choice is still closing survives and is presented next.
                if choiceGate != nil { choiceGate = nil } else { errorMessage = nil }
            }
        )
    }

    var body: some View {
        Button(role: role) {
            let gate = WorkoutAccountTransition(context: context, engine: engine,
                syncScheduler: scheduler, owner: { currentOwner.localDataOwnerTokenIdentifier })
            transition = gate
            Task {
                await gate.request(destination: destination, action)
                if gate.needsResolution {
                    choiceGate = gate
                } else if let message = gate.errorMessage {
                    errorMessage = message
                }
            }
        } label: { label }
        .disabled(transition?.isRunning == true || engine.isAccountTransitionInProgress)
        .alert(promptTitle, isPresented: isPromptPresented, presenting: prompt) { prompt in
            switch prompt {
            case .choices(let gate):
                Button("Finish Workout and \(destination.title)") { resolve(.finish, on: gate) }
                Button("Discard Workout and \(destination.title)", role: .destructive) {
                    resolve(.discard, on: gate)
                }
                Button("Cancel", role: .cancel) { gate.cancel() }
            case .error:
                Button("OK", role: .cancel) {}
            }
        } message: { prompt in
            switch prompt {
            case .choices:
                Text("Finish or discard the current account’s unfinished workouts before continuing. Cancel keeps your workout and account unchanged.")
            case .error(let message):
                Text(message)
            }
        }
        .onDisappear { transition?.cancel() }
    }

    private var promptTitle: String {
        switch prompt {
        case .error: "Couldn’t Continue"
        case .choices, nil: "Resolve your workout first"
        }
    }

    private func resolve(_ resolution: WorkoutAccountTransition.Resolution, on gate: WorkoutAccountTransition) {
        Task {
            await gate.resolve(resolution)
            if let message = gate.errorMessage { errorMessage = message }
        }
    }
}

extension AccountTransitionButton where Label == Text {
    init(destination: WorkoutAccountTransition.Destination, role: ButtonRole? = nil,
         action: @escaping () async throws -> Void) {
        self.init(destination: destination, role: role, action: action) { Text(destination.title) }
    }
}
