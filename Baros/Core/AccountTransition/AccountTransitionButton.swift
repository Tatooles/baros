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
    /// Shown under the button instead of in a second alert. An alert presented while the
    /// choice alert was still closing could be dropped, so a failed choice looked like
    /// nothing happened (#403, #417).
    @State private var errorMessage: String?
    let destination: WorkoutAccountTransition.Destination
    var role: ButtonRole? = nil
    /// Applied to the button alone. An identifier added outside would also replace the
    /// error message's own identifier.
    let identifier: String
    let action: () async throws -> Void
    let label: Label

    init(destination: WorkoutAccountTransition.Destination, role: ButtonRole? = nil, identifier: String,
         action: @escaping () async throws -> Void, @ViewBuilder label: () -> Label) {
        self.destination = destination
        self.role = role
        self.identifier = identifier
        self.action = action
        self.label = label()
    }

    private var isChoicePresented: Binding<Bool> {
        Binding(
            get: { choiceGate != nil },
            set: { if !$0 { choiceGate = nil } }
        )
    }

    /// The message is the button's sibling, so a Form shows it as its own row and the
    /// button keeps its usual row and tap area.
    var body: some View {
        Group {
            Button(role: role) {
                let gate = WorkoutAccountTransition(context: context, engine: engine,
                    syncScheduler: scheduler, owner: { currentOwner.localDataOwnerTokenIdentifier })
                transition = gate
                choiceGate = nil
                errorMessage = nil
                Task {
                    await gate.request(destination: destination, action)
                    if gate.needsResolution {
                        choiceGate = gate
                    } else {
                        errorMessage = gate.errorMessage
                    }
                }
            } label: { label }
            .disabled(transition?.isRunning == true || engine.isAccountTransitionInProgress)
            .accessibilityIdentifier(identifier)
            .alert("Resolve your workout first", isPresented: isChoicePresented, presenting: choiceGate) { gate in
                Button("Finish Workout and \(destination.title)") { resolve(.finish, on: gate) }
                Button("Discard Workout and \(destination.title)", role: .destructive) {
                    resolve(.discard, on: gate)
                }
                Button("Cancel", role: .cancel) { gate.cancel() }
            } message: { _ in
                Text("Finish or discard the current account’s unfinished workouts before continuing. Cancel keeps your workout and account unchanged.")
            }
            .onChange(of: errorMessage) { _, message in
                if let message { AccessibilityNotification.Announcement(message).post() }
            }
            .onDisappear { transition?.cancel() }

            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.destructiveForeground)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("AccountTransitionErrorMessage")
            }
        }
    }

    private func resolve(_ resolution: WorkoutAccountTransition.Resolution, on gate: WorkoutAccountTransition) {
        Task {
            await gate.resolve(resolution)
            errorMessage = gate.errorMessage
        }
    }
}

extension AccountTransitionButton where Label == Text {
    init(destination: WorkoutAccountTransition.Destination, role: ButtonRole? = nil, identifier: String,
         action: @escaping () async throws -> Void) {
        self.init(destination: destination, role: role, identifier: identifier, action: action) {
            Text(destination.title)
        }
    }
}
