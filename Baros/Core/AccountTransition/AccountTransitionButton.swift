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
    @State private var showsError = false
    @State private var showsChoices = false
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

    var body: some View {
        Button(role: role) {
            let gate = WorkoutAccountTransition(context: context, engine: engine,
                syncScheduler: scheduler, owner: { currentOwner.localDataOwnerTokenIdentifier })
            transition = gate
            Task {
                await gate.request(destination: destination, action)
                showsChoices = gate.needsResolution
                showsError = gate.errorMessage != nil
            }
        } label: { label }
        .disabled(transition?.isRunning == true || engine.isAccountTransitionInProgress)
        .alert("Resolve your workout first", isPresented: $showsChoices) {
            Button("Finish Workout and \(destination.title)") { resolve(.finish) }
            Button("Discard Workout and \(destination.title)", role: .destructive) { resolve(.discard) }
            Button("Cancel", role: .cancel) { transition?.cancel() }
        } message: {
            Text("Finish or discard the current account’s unfinished workouts before continuing. Cancel keeps your workout and account unchanged.")
        }
        .alert("Couldn’t Continue", isPresented: $showsError) {
            Button("OK", role: .cancel) {}
        } message: { Text(transition?.errorMessage ?? "Try again.") }
        .onDisappear { transition?.cancel() }
    }

    private func resolve(_ resolution: WorkoutAccountTransition.Resolution) {
        Task {
            await transition?.resolve(resolution)
            showsError = transition?.errorMessage != nil
        }
    }
}

extension AccountTransitionButton where Label == Text {
    init(destination: WorkoutAccountTransition.Destination, role: ButtonRole? = nil,
         action: @escaping () async throws -> Void) {
        self.init(destination: destination, role: role, action: action) { Text(destination.title) }
    }
}
