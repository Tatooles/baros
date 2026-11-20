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

    #if DEBUG
    /// Tells this view instance apart in the trace, to show whether SwiftUI replaced it.
    @State private var traceID = String(UUID().uuidString.prefix(4))
    #endif

    private func trace(_ event: @autoclosure () -> String) {
        #if DEBUG
        AccountGateTrace.shared.log("\(traceID) \(event())")
        #endif
    }

    private var isChoicePresented: Binding<Bool> {
        Binding(
            get: { choiceGate != nil },
            set: {
                trace("binding \($0)")
                if !$0 { choiceGate = nil }
            }
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
                trace("tap")
                Task {
                    await gate.request(destination: destination, action)
                    trace("request needs=\(gate.needsResolution) error=\(gate.errorMessage ?? "nil")")
                    if gate.needsResolution {
                        choiceGate = gate
                    } else {
                        errorMessage = gate.errorMessage
                    }
                }
            } label: { label }
            .disabled(transition?.isRunning == true || engine.isAccountTransitionInProgress)
            .accessibilityIdentifier(identifier)
            #if DEBUG
            .modifier(AccountGateTraceValue())
            #endif
            .alert("Resolve your workout first", isPresented: isChoicePresented, presenting: choiceGate) { gate in
                Button("Finish Workout and \(destination.title)") {
                    trace("finish action")
                    resolve(.finish, on: gate)
                }
                Button("Discard Workout and \(destination.title)", role: .destructive) {
                    trace("discard action")
                    resolve(.discard, on: gate)
                }
                Button("Cancel", role: .cancel) {
                    trace("cancel action")
                    gate.cancel()
                }
            } message: { _ in
                Text("Finish or discard the current account’s unfinished workouts before continuing. Cancel keeps your workout and account unchanged.")
            }
            .onChange(of: errorMessage) { _, message in
                trace("error state \(message == nil ? "cleared" : "set")")
                guard let message else { return }
                // High priority, so focus returning from the closing alert doesn't cut it off.
                var announcement = AttributedString(message)
                announcement.accessibilitySpeechAnnouncementPriority = .high
                AccessibilityNotification.Announcement(announcement).post()
            }
            .onAppear { trace("appear") }
            .onDisappear {
                trace("disappear")
                transition?.cancel()
            }

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
            trace("resolve start needs=\(gate.needsResolution) running=\(gate.isRunning) "
                + "busy=\(engine.isAccountTransitionInProgress) current=\(gate === transition)")
            await gate.resolve(resolution)
            trace("resolve end needs=\(gate.needsResolution) error=\(gate.errorMessage ?? "nil")")
            errorMessage = gate.errorMessage
        }
    }
}

#if DEBUG
/// UI-test-only record of the account gate's steps, on with `--uitest-account-gate-trace`.
/// Tests read it from the gate button's accessibility value to see where a choice stops on
/// the iOS 26.5 runner, where Finish and Discard do nothing (#417, #403).
@MainActor
@Observable
final class AccountGateTrace {
    static let shared = AccountGateTrace()
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("--uitest-account-gate-trace")
    private(set) var events: [String] = []

    func log(_ event: String) {
        guard Self.isEnabled else { return }
        events.append(event)
    }
}

private struct AccountGateTraceValue: ViewModifier {
    func body(content: Content) -> some View {
        if AccountGateTrace.isEnabled {
            content.accessibilityValue(AccountGateTrace.shared.events.joined(separator: " | "))
        } else {
            content
        }
    }
}
#endif

extension AccountTransitionButton where Label == Text {
    init(destination: WorkoutAccountTransition.Destination, role: ButtonRole? = nil, identifier: String,
         action: @escaping () async throws -> Void) {
        self.init(destination: destination, role: role, identifier: identifier, action: action) {
            Text(destination.title)
        }
    }
}
