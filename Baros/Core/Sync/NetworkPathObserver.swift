import Foundation
import Network

enum NetworkPathStatus: Equatable {
    case satisfied
    case unsatisfied
    case requiresConnection
}

@MainActor
final class NetworkRecoveryActivity {
    struct Candidate<Value> {
        fileprivate let generation: UInt
        let value: Value
    }

    private(set) var isActive = false
    private var generation: UInt = 0

    func setActive(_ isActive: Bool) {
        if self.isActive, !isActive {
            generation &+= 1
        }
        self.isActive = isActive
    }

    func makeCandidate<Value>(
        _ makeValue: () -> Value?
    ) -> Candidate<Value>? {
        guard isActive, let value = makeValue() else { return nil }
        return Candidate(generation: generation, value: value)
    }

    func performIfCurrent<Value>(
        _ candidate: Candidate<Value>,
        _ action: (Value) -> Void
    ) {
        guard isActive, candidate.generation == generation else { return }
        action(candidate.value)
    }
}

@MainActor
protocol NetworkPathMonitoring: AnyObject {
    func start(
        receiveStatus: @escaping @MainActor @Sendable (NetworkPathStatus) -> Void
    )
    func cancel()
}

@MainActor
final class SystemNetworkPathMonitor: NetworkPathMonitoring {
    private let queue = DispatchQueue(label: "com.tatooles.baros.network-path")
    private var monitor: NWPathMonitor?

    func start(
        receiveStatus: @escaping @MainActor @Sendable (NetworkPathStatus) -> Void
    ) {
        cancel()

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            let status: NetworkPathStatus = switch path.status {
            case .satisfied:
                .satisfied
            case .unsatisfied:
                .unsatisfied
            case .requiresConnection:
                .requiresConnection
            @unknown default:
                .unsatisfied
            }
            Task { @MainActor in
                receiveStatus(status)
            }
        }
        self.monitor = monitor
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor?.cancel()
        monitor = nil
    }

    deinit {
        monitor?.cancel()
    }
}

@MainActor
final class NetworkPathObserver<RecoveryCandidate> {
    private let monitor: any NetworkPathMonitoring
    private let settlingDelay: Duration
    private let makeRecoveryCandidate: @MainActor () -> RecoveryCandidate?
    private var latestStatus: NetworkPathStatus?
    private var settlingTask: Task<Void, Never>?
    private var isStarted = false

    init(
        monitor: any NetworkPathMonitoring = SystemNetworkPathMonitor(),
        settlingDelay: Duration = .milliseconds(500),
        makeRecoveryCandidate: @MainActor @escaping () -> RecoveryCandidate?
    ) {
        self.monitor = monitor
        self.settlingDelay = settlingDelay
        self.makeRecoveryCandidate = makeRecoveryCandidate
    }

    func start(
        onNetworkRecovery: @escaping @MainActor (RecoveryCandidate) -> Void
    ) {
        guard !isStarted else { return }
        isStarted = true

        monitor.start { [weak self] status in
            guard let self else { return }
            handle(status, onNetworkRecovery: onNetworkRecovery)
        }
    }

    func cancel() {
        isStarted = false
        latestStatus = nil
        settlingTask?.cancel()
        settlingTask = nil
        monitor.cancel()
    }

    private func handle(
        _ status: NetworkPathStatus,
        onNetworkRecovery: @escaping @MainActor (RecoveryCandidate) -> Void
    ) {
        guard status != latestStatus else { return }

        let previousStatus = latestStatus
        latestStatus = status
        settlingTask?.cancel()
        settlingTask = nil

        guard status == .satisfied,
              previousStatus == .unsatisfied || previousStatus == .requiresConnection,
              let recoveryCandidate = makeRecoveryCandidate() else {
            return
        }

        settlingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: settlingDelay)
            guard !Task.isCancelled, latestStatus == .satisfied else { return }
            settlingTask = nil
            onNetworkRecovery(recoveryCandidate)
        }
    }
}
